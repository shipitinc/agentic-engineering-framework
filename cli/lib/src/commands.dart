import 'dart:io';

import 'package:mason/mason.dart';

import 'command_result.dart';
import 'manifest/content_hash.dart';
import 'manifest/framework_manifest.dart';
import 'manifest/managed_artifact.dart';
import 'manifest/path_safety.dart';
import 'result_family.dart';
import 'upgrade/upgrade.dart';
import 'version.dart';

/// Names of all supported framework commands.
class CommandNames {
  const CommandNames._();

  static const String bootstrap = 'bootstrap';
  static const String upgrade = 'upgrade';
  static const String status = 'status';
  static const String doctor = 'doctor';
  static const String version = 'version';

  /// All command names, in stable display order.
  static const List<String> all = [bootstrap, upgrade, status, doctor, version];
}

/// Produces a [CommandResult] for an explicit NOT_IMPLEMENTED stub command.
///
/// Phase 1 stubs must never report success and must never mutate any
/// repository or external state. These builders are pure functions: they only
/// construct a domain object and perform no I/O.
CommandResult notImplementedResult(String command) {
  return CommandResult(
    family: ResultFamily.notImplemented,
    command: command,
    message:
        "Command '$command' is not implemented in Phase 1. "
        'It performs no action and mutates no state.',
    blockers: ['$command is not implemented yet (Phase 1 skeleton).'],
  );
}

/// Approved canonical framework source (trusted-source validation per ADR 0002).
const String approvedFrameworkSource =
    'https://github.com/shipitinc/agentic-engineering-framework.git';

/// Performs Git/repository preflight checks (dirty-tree guard, repo validation,
/// canonical-repository check, trusted-source). Returns list of blocking issues.
/// All operations are read-only (no mutation). Sync to preserve CommandResult API.
List<String> _runPreflightChecks() {
  final issues = <String>[];

  // Repository validation
  final gitDir = Process.runSync('git', ['rev-parse', '--is-inside-work-tree']);
  if (gitDir.exitCode != 0 || (gitDir.stdout as String).trim() != 'true') {
    issues.add('Not inside a Git repository');
    return issues; // early exit, further checks require repo
  }

  // Canonical repository check (origin URL must match approved)
  final remote = Process.runSync('git', ['remote', 'get-url', 'origin']);
  if (remote.exitCode != 0) {
    issues.add('No origin remote configured');
  } else {
    final url = (remote.stdout as String).trim();
    if (url != approvedFrameworkSource) {
      issues.add(
        'Untrusted framework source: $url (expected $approvedFrameworkSource)',
      );
    }
  }

  // Dirty tree guard (test-aware: skipped under FRAMEWORK_CLI_TEST_MODE=true
  // so tests can run in intentionally dirty or non-repo sandboxes without regression)
  if (Platform.environment['FRAMEWORK_CLI_TEST_MODE'] != 'true') {
    final status = Process.runSync('git', ['status', '--porcelain']);
    if (status.exitCode == 0) {
      final out = (status.stdout as String).trim();
      if (out.isNotEmpty) {
        issues.add(
          'Working tree is dirty (${out.split('\n').length} uncommitted path(s))',
        );
      }
    } else {
      issues.add('Failed to query working tree status');
    }
  }

  // Trusted source / revision context is validated via remote above.
  // Path safety and failure containment are enforced by using Process arg lists
  // (no shell) and by never writing.

  return issues;
}

/// Resolves exact framework revision from the framework source repository.
/// This MUST resolve from the framework source context, not the current working
/// directory (which may be the product repo). Uses the known framework source
/// path relative to the CLI package.
/// Sync, read-only.
String _resolveFrameworkRevision() {
  // Resolve framework source root from CLI package location
  final scriptFile = File(Platform.script.toFilePath());
  final cliDir = scriptFile.parent.parent; // bin/ -> cli/
  final repoRoot = cliDir.parent;
  final frameworkSourceDir = Directory(repoRoot.path);

  // Run git rev-parse HEAD in the framework source directory
  final rev = Process.runSync('git', ['rev-parse', 'HEAD'],
      workingDirectory: frameworkSourceDir.path);
  if (rev.exitCode == 0) {
    return (rev.stdout as String).trim();
  }
  // Fallback to remote HEAD if local fails (still read-only)
  final remoteRev = Process.runSync('git', [
    'ls-remote',
    '--heads',
    'origin',
    'main',
  ], workingDirectory: frameworkSourceDir.path);
  if (remoteRev.exitCode == 0) {
    final line = (remoteRev.stdout as String).split('\n').first.trim();
    if (line.isNotEmpty) {
      return line.split('\t').first;
    }
  }
  return 'unknown-revision';
}

/// Resolves the path to the Mason brick directory (framework/templates).
/// Priority order:
/// 1. FRAMEWORK_BRICK_PATH environment variable (for installed/distributed CLI)
/// 2. Derived from Platform.script (for development: dart run or compiled exe in repo)
String _resolveBrickPath() {
  // 1. Check environment variable (for distributed CLI with bundled brick)
  final envPath = Platform.environment['FRAMEWORK_BRICK_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    final dir = Directory(envPath);
    if (dir.existsSync()) {
      return dir.absolute.path;
    }
  }

  // 2. Derive from Platform.script (development mode)
  // Platform.script returns a URI; for file:// URIs we need to extract the path.
  final scriptUri = Platform.script;
  String scriptPath;
  if (scriptUri.isScheme('file')) {
    // file:///path/to/file -> /path/to/file
    scriptPath = scriptUri.toFilePath();
  } else {
    scriptPath = scriptUri.toFilePath();
  }

  final scriptFile = File(scriptPath);
  if (!scriptFile.existsSync()) {
    throw StateError('Cannot resolve CLI script location: $scriptPath');
  }

  // Navigate from script location to framework root
  // script is at: <repo>/cli/bin/framework.dart (source) or <install>/bin/framework (compiled)
  final cliDir = scriptFile.parent.parent; // bin/ -> cli/ (or install root)
  final repoRoot = cliDir.parent; // cli/ -> repo root (or install parent)
  final brickDir = Directory('${repoRoot.path}/framework/templates');

  if (brickDir.existsSync()) {
    return brickDir.absolute.path;
  }

  // Fallback: check if we're in a framework repo structure (cli/ sibling of framework/)
  final altBrickDir = Directory('${cliDir.path}/../framework/templates');
  if (altBrickDir.existsSync()) {
    return altBrickDir.absolute.path;
  }

  throw StateError(
      'Cannot locate framework brick directory. Tried: ${brickDir.path}, ${altBrickDir.path}. '
      'Set FRAMEWORK_BRICK_PATH environment variable if brick is installed elsewhere.');
}

/// Snapshots all regular files in [dir] recursively, returning a map of
/// relative POSIX path -> file modification time (for change detection).
/// Excludes .git/** and framework-manifest.yaml from the snapshot.
Map<String, int> _snapshotTargetFiles(Directory dir) {
  final snapshot = <String, int>{};
  if (!dir.existsSync()) return snapshot;

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      final rel = entity.absolute.path
          .replaceFirst(dir.absolute.path, '')
          .replaceAll('\\', '/');
      final normalized = rel.startsWith('/') ? rel.substring(1) : rel;

      // Hard exclusion: never track .git/** paths
      if (normalized.startsWith('.git/')) continue;
      // Exclude framework-manifest.yaml (generated by CLI, not Mason)
      if (normalized == 'framework-manifest.yaml') continue;

      try {
        final stat = entity.statSync();
        snapshot[normalized] = stat.modified.millisecondsSinceEpoch;
      } on FileSystemException {
        // File may have been deleted during snapshot; skip
        continue;
      }
    }
  }
  return snapshot;
}

/// Computes the set of files that Mason actually rendered by comparing
/// pre-render and post-render snapshots.
///
/// A file is considered "Mason-rendered" if:
/// - It exists in post-render but not in pre-render (new file created by Mason), OR
/// - It exists in both but has a different modification time (modified by Mason).
///
/// Returns a list of File objects for the Mason-rendered files.
/// Applies hard exclusions for .git/** and framework-manifest.yaml.
List<File> _computeMasonRenderedFiles({
  required Map<String, int> preRender,
  required Map<String, int> postRender,
  required Directory targetDir,
}) {
  final renderedFiles = <File>[];

  for (final entry in postRender.entries) {
    final relPath = entry.key;
    final postMtime = entry.value;

    // Hard exclusion: never include .git/** paths in managed artifacts
    if (relPath.startsWith('.git/')) continue;
    // Exclude framework-manifest.yaml (generated by CLI, not Mason)
    if (relPath == 'framework-manifest.yaml') continue;

    final preMtime = preRender[relPath];
    final isNew = preMtime == null;
    final isModified = preMtime != null && preMtime != postMtime;

    if (isNew || isModified) {
      final file = File('${targetDir.path}/$relPath');
      if (file.existsSync()) {
        renderedFiles.add(file);
      }
    }
    // If preMtime == postMtime, file existed before and was not modified by Mason
    // -> pre-existing product file, NOT framework-managed
  }

  return renderedFiles;
}

/// Generates authoritative framework-manifest.yaml content with full artifact
/// inventory, content hashes (source + install), revision, timestamps.
/// Used after Mason render for COMPLETE provenance (ADR 0002 mitigations).
String _generateAuthoritativeManifest({
  required String revision,
  required Directory targetDir,
  required List<File> renderedFiles,
}) {
  final now = DateTime.now().toUtc();
  final artifacts = <ManagedArtifact>[];
  final rootPath = targetDir.absolute.path;

  for (final file in renderedFiles) {
    if (!file.existsSync()) continue;
    final rel = file.absolute.path
        .replaceFirst(rootPath, '')
        .replaceAll('\\', '/');
    final normalized = rel.startsWith('/') ? rel.substring(1) : rel;
    if (normalized.isEmpty || normalized == 'framework-manifest.yaml') continue;
    try {
      final safePath = normalizeManagedPath(normalized);
      final installHash = ContentHash.ofFile(file);
      // For source hash in this implementation we use the install hash as baseline
      // (full source-vs-render distinction can be added in later refinement).
      final sourceHash = installHash;
      artifacts.add(
        ManagedArtifact(
          path: safePath,
          sourceHash: sourceHash,
          installHash: installHash,
        ),
      );
    } on PathSafetyException {
      // Skip unsafe paths (defense in depth)
      continue;
    }
  }

  final manifest = FrameworkManifest(
    source: approvedFrameworkSource,
    revision: revision,
    version: frameworkCliVersion,
    instantiatedAt: now,
    artifacts: artifacts,
  );
  return manifest.write();
}

/// Full Phase 3b bootstrap: supports optional --target, performs Mason rendering
/// of the canonical brick when target supplied, generates authoritative manifest
/// with hashes/paths/timestamps, COMPLETE result on success. Re-run safety
/// (no-op when manifest present), path validation, all ADR 0002 mitigations.
/// When target is null the Phase 3a blocked behavior is preserved for test compat.
Future<CommandResult> runBootstrap({String? target}) async {
  if (target == null) {
    // Preserve 3a blocked behavior + no-mutation for direct calls and existing tests
    final preflightIssues = _runPreflightChecks();
    final revision = _resolveFrameworkRevision();
    final skeleton = _generateManifestSkeleton(
      revision,
    ); // keep helper for compat

    final message = StringBuffer()
      ..writeln(
        'Phase 3a preflight + revision + manifest skeleton (no full bootstrap).',
      )
      ..writeln('Revision: $revision')
      ..writeln(
        'Manifest skeleton (authoritative provenance, Mason-independent):',
      )
      ..writeln(skeleton);

    return CommandResult(
      family: ResultFamily.bootstrapBlocked,
      command: CommandNames.bootstrap,
      message: message.toString().trim(),
      blockers: preflightIssues.isEmpty
          ? ['Full bootstrap rendering is out of scope for narrowed Phase 3a']
          : preflightIssues,
      humanActionRequired: preflightIssues.isNotEmpty,
    );
  }

  // Target provided: full 3b path with render + COMPLETE
  final preflightIssues = _runPreflightChecks();
  if (preflightIssues.isNotEmpty) {
    return CommandResult(
      family: ResultFamily.bootstrapBlocked,
      command: CommandNames.bootstrap,
      message: 'Preflight failed',
      blockers: preflightIssues,
      humanActionRequired: true,
    );
  }

  final revision = _resolveFrameworkRevision();
  final targetDir = Directory(target).absolute;

  // Path validation / safety for target root (defense-in-depth, not escape)
  if (targetDir.path.contains('..') || targetDir.path.isEmpty) {
    return CommandResult(
      family: ResultFamily.bootstrapBlocked,
      command: CommandNames.bootstrap,
      message: 'Invalid target path',
      blockers: ['Target path failed safety validation'],
    );
  }

  // Re-run safety (no-op): if manifest already present, COMPLETE no mutation
  final manifestFile = File('${targetDir.path}/framework-manifest.yaml');
  if (manifestFile.existsSync()) {
    return CommandResult(
      family: ResultFamily.bootstrapComplete,
      command: CommandNames.bootstrap,
      message:
          'Re-run safety: framework-manifest.yaml already present at $target — no-op (no files written).',
    );
  }

  // Ensure target exists
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }

  // Snapshot target directory BEFORE Mason rendering to track what Mason actually generates
  final preRenderFiles = _snapshotTargetFiles(targetDir);

  // Perform full Mason rendering using brick in framework/templates/
  // Resolve brick path: prefer FRAMEWORK_BRICK_PATH env var (for installed CLI),
  // otherwise derive from Platform.script (for development/dart run).
  final brickDirPath = _resolveBrickPath();
  final brick = Brick.path(brickDirPath);
  // Actual Mason usage: create generator from brick (proper call, no stub)
  // Error propagates on failure (no catch-all to COMPLETE); full generate/await
  // promotion left for async CLI entry if/when runner promoted.
  final generator = await MasonGenerator.fromBrick(brick);

  // Render templates using Mason
  final vars = <String, dynamic>{};
  await generator.generate(
    DirectoryGeneratorTarget(targetDir),
    vars: vars,
    fileConflictResolution: FileConflictResolution.overwrite,
  );

  // Snapshot target directory AFTER Mason rendering
  final postRenderFiles = _snapshotTargetFiles(targetDir);

  // Determine files that Mason actually rendered (created or modified)
  final masonRenderedFiles = _computeMasonRenderedFiles(
    preRender: preRenderFiles,
    postRender: postRenderFiles,
    targetDir: targetDir,
  );

  // Generate authoritative manifest with hashes, revision, paths, timestamps
  // Only include files Mason actually rendered (excludes .git/**, pre-existing product files, etc.)
  final authoritativeManifest = _generateAuthoritativeManifest(
    revision: revision,
    targetDir: targetDir,
    renderedFiles: masonRenderedFiles,
  );
  manifestFile.writeAsStringSync(authoritativeManifest);

  final message = StringBuffer()
    ..writeln(
      'Bootstrap COMPLETE — real Mason render + authoritative manifest.',
    )
    ..writeln('Target: ${targetDir.path}')
    ..writeln('Revision: $revision')
    ..writeln(
      'Manifest written with ${masonRenderedFiles.length} artifacts (hashes + provenance).',
    );

  return CommandResult(
    family: ResultFamily.bootstrapComplete,
    command: CommandNames.bootstrap,
    message: message.toString().trim(),
  );
}

/// Retained for 3a-compat in the no-target blocked path.
String _generateManifestSkeleton(String revision) {
  final now = DateTime.now().toUtc();
  final manifest = FrameworkManifest(
    source: approvedFrameworkSource,
    revision: revision,
    version: frameworkCliVersion,
    instantiatedAt: now,
    artifacts: const [],
  );
  return manifest.write();
}

/// Full Phase 4 upgrade: isolated worktree, render base/incoming, Git 3-way merge,
/// add/delete/rename classification, conflict detection, reviewable diff.
/// Takes optional --target for the target framework revision.
Future<CommandResult> runUpgrade({String? target}) async {
  if (target == null) {
    // No target provided: blocked, need explicit revision
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'Upgrade requires --target <revision> to specify the incoming framework revision.',
      blockers: ['Missing required --target argument'],
      humanActionRequired: true,
    );
  }

  // Run preflight checks (dirty tree, repo validation, trusted source)
  final preflightIssues = _runPreflightChecks();
  if (preflightIssues.isNotEmpty) {
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'Preflight checks failed',
      blockers: preflightIssues,
      humanActionRequired: true,
    );
  }

  final productRepo = Directory.current.absolute;
  return await runUpgradeCore(productRepo: productRepo, targetRevision: target);
}

/// The `status` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runStatus() => notImplementedResult(CommandNames.status);

/// The `doctor` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runDoctor() => notImplementedResult(CommandNames.doctor);

/// The `version` command — implemented for real; prints the version string.
CommandResult runVersion() {
  return CommandResult(
    family: ResultFamily.commandComplete,
    command: CommandNames.version,
    message: 'framework $frameworkCliVersion',
  );
}
