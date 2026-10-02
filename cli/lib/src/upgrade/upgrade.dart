import 'dart:io';

import 'package:mason/mason.dart';

import '../command_result.dart';
import '../commands.dart';
import '../manifest/content_hash.dart';
import '../manifest/framework_manifest.dart';
import '../manifest/managed_artifact.dart';
import '../manifest/modification_detection.dart';
import '../result_family.dart';
import '../version.dart';

/// Result of the upgrade operation classification.
class UpgradeClassification {
  const UpgradeClassification({
    required this.added,
    required this.deleted,
    required this.renamed,
    required this.modified,
    required this.conflicts,
    required this.unmodified,
    required this.productPreserved,
  });

  /// Paths introduced by the incoming framework revision and present in the
  /// merged result.
  final List<String> added;

  /// Paths removed by the incoming framework revision and absent from the merged
  /// result.
  final List<String> deleted;

  /// Content moves detected within the framework's own change (from -> to).
  final List<MapEntry<String, String>> renamed;

  /// Paths whose content differs from the base render.
  final List<String> modified;

  /// Paths that require human resolution: real three-way conflicts, plus a
  /// locally modified artifact that the incoming revision deletes.
  final List<String> conflicts;

  /// Paths whose merged content matches the incoming render exactly.
  final List<String> unmodified;

  /// Locally customized artifacts whose local content survived the merge.
  final List<String> productPreserved;

  bool get hasChanges =>
      added.isNotEmpty ||
      deleted.isNotEmpty ||
      renamed.isNotEmpty ||
      modified.isNotEmpty ||
      conflicts.isNotEmpty;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Raised when an upgrade step cannot complete; carries structured blockers so
/// the caller can return a precise result instead of a generic error.
class _UpgradeFailure implements Exception {
  _UpgradeFailure(this.blockers, {this.message, this.family});

  final List<String> blockers;
  final String? message;
  final ResultFamily? family;
}

/// Synthetic refs encoding the three inputs of the upgrade merge
/// (ADR 0004 § 3). `local` and `incoming` share `base` as their parent, so git
/// resolves `base` as the merge base.
const String _baseRef = 'refs/aef-upgrade/base';
const String _localRef = 'refs/aef-upgrade/local';
const String _incomingRef = 'refs/aef-upgrade/incoming';

/// Scratch workspace for a single upgrade run: a clone of the product
/// repository plus the two framework renders, all outside the product repository
/// (ADR 0004 § 3).
class _UpgradeScratch {
  _UpgradeScratch({
    required this.root,
    required this.repo,
    required this.baseRender,
    required this.incomingRender,
    required this.mergedDir,
    required this.localDir,
  });

  final Directory root;
  final Directory repo;
  final Directory baseRender;
  final Directory incomingRender;

  /// The merged tree materialized on disk (conflict markers included).
  final Directory mergedDir;

  /// The product's own state materialized on disk, for local-modification
  /// inspection.
  final Directory localDir;

  /// Scratch state is always discarded (ADR 0004 § 6): the deliverable is a ref
  /// in the product repository, so nothing needs to survive the process.
  void dispose() {
    if (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort: a leftover temp directory never invalidates the result.
      }
    }
  }
}

/// Performs the core upgrade logic and delivers the merged result as a single
/// review commit on the product repository's real history.
///
/// Steps (ADR 0004):
/// 1. Read the current manifest (revision A) from the product repository.
/// 2. Refuse a re-run that would overwrite an existing upgrade branch.
/// 3. Create a scratch clone of the product repository outside that repository.
/// 4. Render base (revision A) and incoming (revision B) with Mason.
/// 5. Build the synthetic base/local/incoming commits and merge them with
///    `git merge-tree --write-tree`.
/// 6. Materialize the merged tree, classify every managed path, and refresh
///    `framework-manifest.yaml` inside it.
/// 7. Deliver the result as one commit parented on the product's `HEAD`, pushed
///    to `framework/upgrade-<A>-<B>`.
/// 8. Return the structured result; always discard the scratch state.
///
/// [frameworkRootOverride] selects the framework checkout used as the render
/// source; when null the CLI's own framework checkout is used if it contains the
/// requested revision, otherwise the canonical source.
Future<CommandResult> runUpgradeCore({
  required Directory productRepo,
  required String targetRevision,
  String? frameworkRootOverride,
}) async {
  // 1. Read current manifest (revision A)
  final manifestFile = File('${productRepo.path}/framework-manifest.yaml');
  if (!manifestFile.existsSync()) {
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'No framework-manifest.yaml found — product not bootstrapped.',
      blockers: [
        'Product repository has no framework manifest. Run bootstrap first.',
      ],
      humanActionRequired: true,
    );
  }

  FrameworkManifest currentManifest;
  try {
    currentManifest = FrameworkManifest.parse(manifestFile.readAsStringSync());
  } on ManifestFormatException catch (e) {
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'Invalid framework-manifest.yaml',
      blockers: ['Manifest parse error: $e'],
      humanActionRequired: true,
    );
  }

  final revisionA = currentManifest.revision;
  final revisionB = targetRevision;

  // Re-run safety: if already at target revision, no-op
  if (revisionA == revisionB) {
    return CommandResult(
      family: ResultFamily.upgradeNoop,
      command: CommandNames.upgrade,
      message:
          'Already at target revision $revisionB — no upgrade needed (re-run safety).',
    );
  }

  final branch = 'framework/upgrade-${_shortRevision(revisionA)}-'
      '${_shortRevision(revisionB)}';

  // Re-run safety: never overwrite an upgrade that is already awaiting review.
  final existing = _git(
    productRepo,
    ['show-ref', '--verify', '--quiet', 'refs/heads/$branch'],
  );
  if (existing.exitCode == 0) {
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'Upgrade branch $branch already exists.',
      blockers: [
        'Branch $branch already exists in the product repository. '
        'Review or delete it before re-running the upgrade.',
      ],
      humanActionRequired: true,
    );
  }

  _UpgradeScratch? scratch;
  try {
    scratch = _createScratch(productRepo);

    // 4. Render both framework revisions with Mason.
    final baseRender = await _renderFrameworkRevision(
      revision: revisionA,
      targetDir: scratch.baseRender,
      frameworkRoot: frameworkRootOverride,
    );
    if (baseRender != null) return baseRender;

    final incomingRender = await _renderFrameworkRevision(
      revision: revisionB,
      targetDir: scratch.incomingRender,
      frameworkRoot: frameworkRootOverride,
    );
    if (incomingRender != null) return incomingRender;

    final repo = scratch.repo;

    // 5. Synthetic topology: base (render A) <- local (product HEAD) and
    //    base <- incoming (render B).
    final productHead = _gitOut(repo, ['rev-parse', 'HEAD']);
    final localTree = _gitOut(repo, ['rev-parse', 'HEAD^{tree}']);

    _createRef(repo, _baseRef, _commitTree(repo, _treeFromDirectory(repo, scratch.baseRender),
        'Base: framework render of $revisionA'));
    _createRef(repo, _incomingRef,
        _commitTree(repo, _treeFromDirectory(repo, scratch.incomingRender),
            'Incoming: framework render of $revisionB', parent: _baseRef));
    _createRef(repo, _localRef,
        _commitTree(repo, localTree, 'Local: product state at $productHead',
            parent: _baseRef));

    final merge = _git(
      repo,
      ['merge-tree', '--write-tree', '--name-only', _localRef, _incomingRef],
    );
    // Exit 0 = clean merge, 1 = conflicts (expected and reviewable).
    if (merge.exitCode != 0 && merge.exitCode != 1) {
      throw _UpgradeFailure(
        ['git merge-tree failed: ${_stderrOf(merge)}'],
        message: 'Three-way merge failed',
        family: ResultFamily.internalError,
      );
    }
    final mergeLines = _stdoutOf(merge).split('\n');
    final mergedTree = mergeLines.first.trim();
    if (mergedTree.isEmpty) {
      throw _UpgradeFailure(
        ['git merge-tree produced no merged tree: ${_stderrOf(merge)}'],
        message: 'Three-way merge produced no result tree',
        family: ResultFamily.internalError,
      );
    }
    final mergeConflicts = <String>[];
    for (final line in mergeLines.skip(1)) {
      if (line.trim().isEmpty) break; // path list is terminated by a blank line
      mergeConflicts.add(line.trim());
    }

    // 6. Materialize both sides so classification and hashing work on files.
    _materializeTree(repo, mergedTree, scratch.mergedDir);
    _materializeTree(repo, localTree, scratch.localDir);

    final classification = _classifyChanges(
      mergedDir: scratch.mergedDir,
      baseDir: scratch.baseRender,
      incomingDir: scratch.incomingRender,
      localDir: scratch.localDir,
      mergeConflicts: mergeConflicts,
      currentManifest: currentManifest,
    );

    // Refresh the manifest inside the merged tree so the delivered commit pins
    // the product to the revision it just adopts (ADR 0004 § 5).
    _writeUpgradedManifest(
      mergedDir: scratch.mergedDir,
      baseRender: scratch.baseRender,
      incomingRender: scratch.incomingRender,
      currentManifest: currentManifest,
      revisionB: revisionB,
    );

    // 7. Deliver: one commit on the product's real history, pushed last so a
    //    failed upgrade leaves no ref behind.
    final deliveredTree = _treeFromDirectory(repo, scratch.mergedDir);
    final deliveredCommit = _commitTree(
      repo,
      deliveredTree,
      'framework: upgrade $revisionA -> $revisionB\n\n'
          'Merge base: framework render of $revisionA.\n'
          'Incoming:  framework render of $revisionB.\n'
          'Local:     product repository state at $productHead.\n'
          'Conflicts: ${classification.conflicts.length}\n',
      parent: productHead,
    );
    final push = _git(
      repo,
      ['push', 'origin', '$deliveredCommit:refs/heads/$branch'],
    );
    if (push.exitCode != 0) {
      throw _UpgradeFailure(
        [
          'Could not push $branch to the product repository: '
              '${_stderrOf(push)}',
        ],
        message: 'Failed to deliver the upgrade branch',
      );
    }

    // 8. Result family: conflicts first, then real changes, then no-op.
    final ResultFamily family;
    final blockers = <String>[];
    var humanActionRequired = false;
    if (classification.hasConflicts) {
      family = ResultFamily.upgradeConflict;
      blockers.add(
        'Three-way merge produced ${classification.conflicts.length} '
        'conflict(s): ${classification.conflicts.join(', ')}',
      );
      humanActionRequired = true;
    } else if (classification.hasChanges) {
      family = ResultFamily.upgradeReadyForReview;
    } else {
      family = ResultFamily.upgradeNoop;
    }

    final message = StringBuffer()
      ..writeln('Upgrade from $revisionA to $revisionB')
      ..writeln('Branch: $branch (commit $deliveredCommit)')
      ..writeln('Added: ${classification.added.length}')
      ..writeln('Deleted: ${classification.deleted.length}')
      ..writeln('Renamed: ${classification.renamed.length}')
      ..writeln('Modified: ${classification.modified.length}')
      ..writeln('Conflicts: ${classification.conflicts.length}')
      ..writeln('Product customizations preserved: '
          '${classification.productPreserved.length}')
      ..writeln('Unmodified: ${classification.unmodified.length}')
      ..writeln('Manifest refreshed to revision $revisionB.')
      ..writeln('Review: git diff HEAD..$branch');

    return CommandResult(
      family: family,
      command: CommandNames.upgrade,
      message: message.toString().trim(),
      blockers: blockers,
      humanActionRequired: humanActionRequired,
    );
  } on _UpgradeFailure catch (failure) {
    return CommandResult(
      family: failure.family ?? ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: failure.message ?? 'Upgrade blocked',
      blockers: failure.blockers,
      humanActionRequired: true,
    );
  } catch (e) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Upgrade failed with exception: $e',
      blockers: ['Internal error during upgrade: $e'],
    );
  } finally {
    scratch?.dispose();
  }
}

/// Clones the product repository into the system temp directory. The clone lives
/// outside the product repository so that no operation can ever copy a directory
/// into itself (ADR 0004 § 3).
_UpgradeScratch _createScratch(Directory productRepo) {
  final root = Directory.systemTemp.createTempSync('aef_upgrade_');
  final repo = Directory('${root.path}/product');
  final clone = Process.runSync(
    'git',
    [
      'clone',
      '--no-hardlinks',
      productRepo.absolute.path,
      repo.path,
    ],
    // Never inherit the ambient working directory: the upgrade must not depend
    // on where the process happens to be.
    workingDirectory: Directory.systemTemp.path,
  );
  if (clone.exitCode != 0) {
    final scratch = _UpgradeScratch(
      root: root,
      repo: repo,
      baseRender: Directory('${root.path}/base'),
      incomingRender: Directory('${root.path}/incoming'),
      mergedDir: Directory('${root.path}/merged'),
      localDir: Directory('${root.path}/local'),
    );
    scratch.dispose();
    throw _UpgradeFailure(
      ['Could not clone the product repository: ${_stderrOf(clone)}'],
      message: 'Failed to create the upgrade scratch clone',
    );
  }

  if (!_gitSupportsWriteTreeMerge(repo)) {
    root.deleteSync(recursive: true);
    throw _UpgradeFailure(
      [
        'git >= 2.38 is required for `git merge-tree --write-tree`, which '
            'computes the upgrade merge without a working tree.',
      ],
      message: 'Unsupported git version',
    );
  }

  // A deterministic author keeps the synthetic and delivered commits stable.
  Process.runSync(
    'git',
    ['config', 'user.email', 'framework-cli@upgrade'],
    workingDirectory: repo.path,
  );
  Process.runSync(
    'git',
    ['config', 'user.name', 'Framework CLI Upgrade'],
    workingDirectory: repo.path,
  );

  return _UpgradeScratch(
    root: root,
    repo: repo,
    baseRender: Directory('${root.path}/base'),
    incomingRender: Directory('${root.path}/incoming'),
    mergedDir: Directory('${root.path}/merged'),
    localDir: Directory('${root.path}/local'),
  );
}

/// `git merge-tree --write-tree` landed in git 2.38.
bool _gitSupportsWriteTreeMerge(Directory cwd) {
  final version = _git(cwd, ['--version']);
  final match = RegExp(r'(\d+)\.(\d+)').firstMatch(_stdoutOf(version));
  if (match == null) return false;
  final major = int.parse(match.group(1)!);
  final minor = int.parse(match.group(2)!);
  return major > 2 || (major == 2 && minor >= 38);
}

/// Renders a framework revision with Mason.
///
/// Prefers the CLI's own framework checkout when it already contains [revision]
/// (no network round-trip, hermetic under test), otherwise clones the canonical
/// source. The clone always carries full history because an upgrade renders the
/// pinned base revision as well as the incoming one, and a shallow clone cannot
/// check out any revision other than the branch tip (ADR 0004 § 2).
///
/// Returns null on success, or a [CommandResult] describing the blocker.
Future<CommandResult?> _renderFrameworkRevision({
  required String revision,
  required Directory targetDir,
  String? frameworkRoot,
}) async {
  final source = _resolveRenderSource(revision, frameworkRoot: frameworkRoot);
  final tempDir = Directory.systemTemp.createTempSync('framework_render_');
  try {
    final cloneResult = Process.runSync(
      'git',
      ['clone', source, tempDir.path],
      // Explicit working directory: the render must not depend on the process
      // cwd, which may be a directory that no longer exists.
      workingDirectory: Directory.systemTemp.path,
    );
    if (cloneResult.exitCode != 0) {
      return CommandResult(
        family: ResultFamily.upgradeBlocked,
        command: CommandNames.upgrade,
        message: 'Failed to clone framework source',
        blockers: [
          'Could not clone the framework from $source at revision $revision: '
              '${_stderrOf(cloneResult)}',
        ],
        humanActionRequired: true,
      );
    }

    final checkoutResult = Process.runSync(
      'git',
      ['checkout', revision],
      workingDirectory: tempDir.path,
    );
    if (checkoutResult.exitCode != 0) {
      return CommandResult(
        family: ResultFamily.upgradeBlocked,
        command: CommandNames.upgrade,
        message: 'Failed to checkout framework revision',
        blockers: [
          'Revision $revision not found in framework source $source',
        ],
        humanActionRequired: true,
      );
    }

    final brickDir = Directory('${tempDir.path}/framework/templates');
    if (!brickDir.existsSync()) {
      return CommandResult(
        family: ResultFamily.upgradeBlocked,
        command: CommandNames.upgrade,
        message: 'Framework brick not found',
        blockers: ['framework/templates not found at revision $revision'],
        humanActionRequired: true,
      );
    }

    targetDir.createSync(recursive: true);
    final brick = Brick.path(brickDir.path);
    final generator = await MasonGenerator.fromBrick(brick);
    await generator.generate(
      DirectoryGeneratorTarget(targetDir),
      vars: <String, dynamic>{'frameworkRevision': revision},
      fileConflictResolution: FileConflictResolution.overwrite,
    );

    return null;
  } catch (e) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Failed to render framework revision $revision',
      blockers: ['Mason render failed for $revision: $e'],
    );
  } finally {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort.
      }
    }
  }
}

/// The local framework checkout when it contains [revision], otherwise the
/// canonical source.
String _resolveRenderSource(String revision, {String? frameworkRoot}) {
  final localRoot = frameworkRoot ?? resolveFrameworkSourceRoot();
  if (localRoot != null && Directory(localRoot).existsSync()) {
    final hasRevision = Process.runSync(
      'git',
      ['cat-file', '-e', '$revision^{commit}'],
      workingDirectory: localRoot,
    );
    if (hasRevision.exitCode == 0) return localRoot;
  }
  return approvedFrameworkSource;
}

/// Builds a git tree from the contents of [dir] without touching [repo]'s own
/// working tree, using a temporary index.
///
/// `-f` is required: a product `.gitignore` may exclude paths the framework
/// renders (for example a generated `.claude/` adapter directory), and silently
/// dropping them from the merge inputs would resurrect exactly the class of bug
/// this engine replaces.
String _treeFromDirectory(Directory repo, Directory dir) {
  final index = File('${repo.path}/.git/aef-upgrade-input-index');
  if (index.existsSync()) index.deleteSync();
  final environment = {'GIT_INDEX_FILE': index.path};

  final add = Process.runSync(
    'git',
    ['--work-tree=${dir.absolute.path}', 'add', '-A', '-f'],
    workingDirectory: repo.path,
    environment: environment,
  );
  if (add.exitCode != 0) {
    throw _UpgradeFailure(
      ['Could not stage the render at ${dir.path}: ${_stderrOf(add)}'],
      message: 'Failed to build a merge input tree',
    );
  }
  return _gitOut(repo, ['write-tree'], environment: environment);
}

/// Creates a commit from [tree] and points [ref] at it.
String _commitTree(
  Directory repo,
  String tree,
  String message, {
  String? parent,
}) {
  final args = ['commit-tree', tree, '-m', message];
  if (parent != null) args.addAll(['-p', parent]);
  final commit = _git(repo, args);
  if (commit.exitCode != 0) {
    throw _UpgradeFailure(
      ['git commit-tree failed: ${_stderrOf(commit)}'],
      message: 'Failed to create a merge commit',
      family: ResultFamily.internalError,
    );
  }
  return _stdoutOf(commit);
}

void _createRef(Directory repo, String ref, String commit) {
  final result = _git(repo, ['update-ref', ref, commit]);
  if (result.exitCode != 0) {
    throw _UpgradeFailure(
      ['Could not create $ref: ${_stderrOf(result)}'],
      message: 'Failed to construct the merge topology',
      family: ResultFamily.internalError,
    );
  }
}

/// Writes the contents of [tree] into [dest], so the merged result can be
/// hashed, classified, and patched like ordinary files.
void _materializeTree(Directory repo, String tree, Directory dest) {
  dest.createSync(recursive: true);
  final index = File('${repo.path}/.git/aef-upgrade-output-index');
  if (index.existsSync()) index.deleteSync();
  final environment = {'GIT_INDEX_FILE': index.path};

  final read = _git(repo, ['read-tree', tree], environment: environment);
  if (read.exitCode != 0) {
    throw _UpgradeFailure(
      ['Could not read tree $tree: ${_stderrOf(read)}'],
      message: 'Failed to materialize the merged tree',
      family: ResultFamily.internalError,
    );
  }
  final checkout = _git(
    repo,
    [
      '--git-dir=${repo.path}/.git',
      '--work-tree=${dest.absolute.path}',
      'checkout-index',
      '-a',
      '-f',
    ],
    environment: environment,
  );
  if (checkout.exitCode != 0) {
    throw _UpgradeFailure(
      ['Could not write the merged tree: ${_stderrOf(checkout)}'],
      message: 'Failed to materialize the merged tree',
      family: ResultFamily.internalError,
    );
  }
}

/// Regenerates `framework-manifest.yaml` inside the merged tree so the delivered
/// commit pins the product to the revision it adopts.
///
/// `source_hash` records what the framework ships at the incoming revision and
/// `install_hash` records what the product will carry, so a locally customized
/// artifact stays detectable as `source_hash != install_hash`. Framework paths
/// that upstream deleted are dropped; non-managed product files are never added.
void _writeUpgradedManifest({
  required Directory mergedDir,
  required Directory baseRender,
  required Directory incomingRender,
  required FrameworkManifest currentManifest,
  required String revisionB,
}) {
  final managedPaths = <String>{
    ..._collectFiles(baseRender).keys,
    ..._collectFiles(incomingRender).keys,
  }..remove('framework-manifest.yaml');

  final artifacts = <ManagedArtifact>[];
  for (final path in managedPaths) {
    final mergedFile = File('${mergedDir.path}/$path');
    if (!mergedFile.existsSync()) continue; // deleted by this upgrade
    final incomingFile = File('${incomingRender.path}/$path');
    final baseFile = File('${baseRender.path}/$path');
    final sourceFile = incomingFile.existsSync() ? incomingFile : baseFile;
    if (!sourceFile.existsSync()) continue;
    artifacts.add(
      ManagedArtifact(
        path: path,
        sourceHash: ContentHash.ofFile(sourceFile),
        installHash: ContentHash.ofFile(mergedFile),
      ),
    );
  }

  final upgraded = FrameworkManifest(
    source: currentManifest.source.isEmpty
        ? approvedFrameworkSource
        : currentManifest.source,
    revision: revisionB,
    version: frameworkCliVersion,
    instantiatedAt: currentManifest.instantiatedAt,
    upgradedAt: DateTime.now().toUtc(),
    artifacts: artifacts,
    templateInputs: currentManifest.templateInputs,
  );
  File('${mergedDir.path}/framework-manifest.yaml')
      .writeAsStringSync(upgraded.write());
}

/// Classifies every managed path across the base render, the incoming render,
/// the product's own state, and the merged result.
UpgradeClassification _classifyChanges({
  required Directory mergedDir,
  required Directory baseDir,
  required Directory incomingDir,
  required Directory localDir,
  required List<String> mergeConflicts,
  required FrameworkManifest currentManifest,
}) {
  final baseFiles = _collectFiles(baseDir);
  final incomingFiles = _collectFiles(incomingDir);
  final mergedFiles = _collectFiles(mergedDir);
  final localFiles = _collectFiles(localDir);
  final manifestPaths = currentManifest.managedPaths.toSet();

  final added = <String>[];
  final deleted = <String>[];
  final renamed = <MapEntry<String, String>>[];
  final modified = <String>[];
  final conflicts = <String>[];
  final unmodified = <String>[];
  final productPreserved = <String>[];

  final allPaths = <String>{
    ...baseFiles.keys,
    ...incomingFiles.keys,
    ...manifestPaths,
  }..remove('framework-manifest.yaml');

  bool isLocallyModified(String path) {
    final artifact = currentManifest.artifacts
        .where((a) => a.path == path)
        .firstOrNull;
    if (artifact == null) return false;
    final inspection = ModificationDetector().inspect(artifact, localDir);
    return inspection.state == ArtifactState.locallyModified;
  }

  for (final path in allPaths) {
    final inBase = baseFiles.containsKey(path);
    final inIncoming = incomingFiles.containsKey(path);
    
    final inMerged = mergedFiles.containsKey(path);
    final inLocal = localFiles.containsKey(path);

    if (mergeConflicts.contains(path)) {
      conflicts.add(path);
      continue;
    }

    if (!inBase && inIncoming) {
      // Introduced by the incoming revision. A product file at the same path is
      // an add/add collision unless both sides are identical.
      if (inLocal &&
          ContentHash.ofFile(localFiles[path]!) !=
              ContentHash.ofFile(incomingFiles[path]!)) {
        conflicts.add(path);
        continue;
      }
      added.add(path);
      continue;
    }

    if (inBase && !inIncoming) {
      // Deleted upstream. Never applied over a local customization silently.
      if (isLocallyModified(path)) {
        conflicts.add(path);
        continue;
      }
      if (!inMerged) deleted.add(path);
      continue;
    }

    // Present on both sides.
    final baseHash = ContentHash.ofFile(baseFiles[path]!);
    final incomingHash = ContentHash.ofFile(incomingFiles[path]!);
    final mergedHash =
        inMerged ? ContentHash.ofFile(mergedFiles[path]!) : null;

    if (baseHash == incomingHash) {
      // The framework did not touch this path.
      if (mergedHash != null && mergedHash != baseHash) {
        if (isLocallyModified(path)) {
          productPreserved.add(path);
        } else {
          modified.add(path);
        }
      } else {
        unmodified.add(path);
      }
      continue;
    }

    // The framework changed this path.
    if (mergedHash == incomingHash) {
      unmodified.add(path);
      continue;
    }
    if (inLocal && ContentHash.ofFile(localFiles[path]!) != baseHash) {
      productPreserved.add(path);
    }
    modified.add(path);
  }

  // Content that moved within the framework's own change is a rename, not a
  // delete plus an add.
  for (final entry in List<String>.from(added)) {
    final addedHash = ContentHash.ofFile(incomingFiles[entry]!);
    for (final candidate in baseFiles.entries) {
      if (candidate.key == entry) continue;
      if (ContentHash.ofFile(candidate.value) == addedHash) {
        renamed.add(MapEntry(candidate.key, entry));
        added.remove(entry);
        deleted.remove(candidate.key);
        break;
      }
    }
  }

  // Preserve declaration order for determinism.
  final conflictsSet = conflicts.toSet();
  return UpgradeClassification(
    added: added..sort(),
    deleted: deleted..sort(),
    renamed: renamed..sort((a, b) => a.key.compareTo(b.key)),
    modified: modified..sort(),
    conflicts: conflictsSet.toList()..sort(),
    unmodified: unmodified..sort(),
    productPreserved: productPreserved..sort(),
  );
}

/// Collects all files in a directory recursively, returning relative path -> File.
Map<String, File> _collectFiles(Directory dir) {
  final result = <String, File>{};
  if (!dir.existsSync()) return result;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relPath = entity.path
          .replaceFirst(dir.absolute.path, '')
          .replaceAll('\\', '/');
      final normalized = relPath.startsWith('/')
          ? relPath.substring(1)
          : relPath;
      if (normalized.isNotEmpty) {
        result[normalized] = entity;
      }
    }
  }
  return result;
}

ProcessResult _git(
  Directory cwd,
  List<String> args, {
  Map<String, String>? environment,
}) {
  return Process.runSync(
    'git',
    args,
    workingDirectory: cwd.path,
    environment: environment,
  );
}

String _gitOut(
  Directory cwd,
  List<String> args, {
  Map<String, String>? environment,
}) {
  final result = _git(cwd, args, environment: environment);
  if (result.exitCode != 0) {
    throw _UpgradeFailure(
      ['git ${args.join(' ')} failed: ${_stderrOf(result)}'],
      message: 'Git operation failed',
      family: ResultFamily.internalError,
    );
  }
  return _stdoutOf(result);
}

String _stdoutOf(ProcessResult result) => (result.stdout as String).trim();

String _stderrOf(ProcessResult result) => (result.stderr as String).trim();

String _shortRevision(String revision) =>
    revision.length > 12 ? revision.substring(0, 12) : revision;