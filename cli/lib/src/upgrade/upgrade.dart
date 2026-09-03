import 'dart:io';

import 'package:mason/mason.dart';

import '../command_result.dart';
import '../commands.dart';
import '../manifest/content_hash.dart';
import '../manifest/framework_manifest.dart';
import '../manifest/modification_detection.dart';
import '../result_family.dart';

/// Result of the upgrade operation classification.
class UpgradeClassification {
  const UpgradeClassification({
    required this.added,
    required this.deleted,
    required this.renamed,
    required this.modified,
    required this.conflicts,
    required this.unmodified,
  });

  final List<String> added;
  final List<String> deleted;
  final List<MapEntry<String, String>> renamed; // from -> to
  final List<String> modified;
  final List<String> conflicts;
  final List<String> unmodified;

  bool get hasChanges =>
      added.isNotEmpty ||
      deleted.isNotEmpty ||
      renamed.isNotEmpty ||
      modified.isNotEmpty ||
      conflicts.isNotEmpty;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Performs the core upgrade logic in an isolated worktree.
///
/// Steps:
/// 1. Read current manifest (revision A) from product repo
/// 2. Create isolated worktree on branch `framework/upgrade-<revisionA>-<revisionB>`
/// 3. Render base (revision A) into worktree/base/
/// 4. Render incoming (revision B) into worktree/incoming/
/// 5. Set up Git 3-way merge: base=revisionA, local=product, incoming=revisionB
/// 6. Run native `git merge`
/// 7. Classify add/delete/rename/modified/conflict
/// 8. Generate reviewable diff
/// 9. Return structured result
Future<CommandResult> runUpgradeCore({
  required Directory productRepo,
  required String targetRevision,
}) async {
  // 1. Read current manifest (revision A)
  final manifestFile = File('${productRepo.path}/framework-manifest.yaml');
  if (!manifestFile.existsSync()) {
    return CommandResult(
      family: ResultFamily.upgradeBlocked,
      command: CommandNames.upgrade,
      message: 'No framework-manifest.yaml found — product not bootstrapped.',
      blockers: ['Product repository has no framework manifest. Run bootstrap first.'],
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

  // 2. Create isolated worktree
  final worktreeBranch = 'framework/upgrade-$revisionA-$revisionB';
  final worktreeDir = _createWorktree(productRepo, worktreeBranch);
  if (worktreeDir == null) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Failed to create isolated worktree',
      blockers: ['Could not create Git worktree for upgrade'],
    );
  }

  try {
    // 3. Render base (revision A) into worktree/base/
    final baseDir = Directory('${worktreeDir.path}/base');
    final baseRenderResult = await _renderFrameworkRevision(
      revision: revisionA,
      targetDir: baseDir,
    );
    if (!baseRenderResult.success) {
      return baseRenderResult;
    }

    // 4. Render incoming (revision B) into worktree/incoming/
    final incomingDir = Directory('${worktreeDir.path}/incoming');
    final incomingRenderResult = await _renderFrameworkRevision(
      revision: revisionB,
      targetDir: incomingDir,
    );
    if (!incomingRenderResult.success) {
      return incomingRenderResult;
    }

    // 5. Set up Git 3-way merge in worktree
    final mergeResult = _performThreeWayMerge(
      worktreeDir: worktreeDir,
      baseDir: baseDir,
      incomingDir: incomingDir,
      productRepo: productRepo,
      revisionA: revisionA,
      revisionB: revisionB,
    );
    if (!mergeResult.success) {
      return mergeResult;
    }

    // 6. Classify changes in the merged worktree
    final classification = _classifyChanges(
      worktreeDir: worktreeDir,
      baseDir: baseDir,
      incomingDir: incomingDir,
      currentManifest: currentManifest,
    );

    // 7. Generate reviewable diff
    _generateReviewableDiff(worktreeDir, productRepo, revisionA, revisionB);

    // 8. Determine result family based on classification
    ResultFamily family;
    List<String> blockers = [];
    bool humanActionRequired = false;

    if (classification.hasConflicts) {
      family = ResultFamily.upgradeConflict;
      blockers.add('Git merge produced ${classification.conflicts.length} conflict(s)');
      humanActionRequired = true;
    } else if (classification.hasChanges) {
      family = ResultFamily.upgradeReadyForReview;
    } else {
      family = ResultFamily.upgradeNoop;
    }

    // 9. Clean up worktree (but keep it for review if there are conflicts or changes)
    final shouldKeepWorktree = family != ResultFamily.upgradeNoop;
    if (!shouldKeepWorktree) {
      _cleanupWorktree(productRepo, worktreeBranch, worktreeDir);
    }

    final message = StringBuffer()
      ..writeln('Upgrade from $revisionA to $revisionB')
      ..writeln('Worktree: ${worktreeDir.path} (branch: $worktreeBranch)')
      ..writeln('Added: ${classification.added.length}')
      ..writeln('Deleted: ${classification.deleted.length}')
      ..writeln('Renamed: ${classification.renamed.length}')
      ..writeln('Modified: ${classification.modified.length}')
      ..writeln('Conflicts: ${classification.conflicts.length}')
      ..writeln('Unmodified: ${classification.unmodified.length}')
      ..writeln('Reviewable diff generated.');

    return CommandResult(
      family: family,
      command: CommandNames.upgrade,
      message: message.toString().trim(),
      blockers: blockers,
      humanActionRequired: humanActionRequired,
    );
  } catch (e, stackTrace) {
    // Failure containment: leave worktree for inspection, return error
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Upgrade failed with exception: $e',
      blockers: ['Internal error during upgrade: $e\n$stackTrace'],
    );
  }
}

/// Creates an isolated Git worktree for the upgrade.
Directory? _createWorktree(Directory productRepo, String branchName) {
  // Ensure we're in a clean state for worktree creation
  final status = Process.runSync('git', ['status', '--porcelain'], workingDirectory: productRepo.path);
  if (status.exitCode != 0) return null;

  // Create worktree
  final worktreePath = '${productRepo.path}/.git/worktrees/upgrade-tmp';
  final worktreeDir = Directory(worktreePath);

  // Clean up any existing stale worktree
  if (worktreeDir.existsSync()) {
    Process.runSync('git', ['worktree', 'remove', '--force', worktreePath], workingDirectory: productRepo.path);
  }

  final result = Process.runSync(
    'git',
    ['worktree', 'add', '-b', branchName, worktreePath, 'HEAD'],
    workingDirectory: productRepo.path,
  );

  if (result.exitCode != 0) return null;

  return Directory(worktreePath);
}

/// Renders a specific framework revision into target directory using Mason.
///
/// This checks out the revision in a temporary clone of the canonical framework,
/// then runs Mason to render the brick.
Future<CommandResult> _renderFrameworkRevision({
  required String revision,
  required Directory targetDir,
}) async {
  // Create a temporary clone of the canonical framework at the specific revision
  final tempDir = Directory.systemTemp.createTempSync('framework_render_$revision');
  try {
    // Clone the canonical framework
    final cloneResult = Process.runSync(
      'git',
      ['clone', '--branch', 'main', '--depth', '1', approvedFrameworkSource, tempDir.path],
    );
    if (cloneResult.exitCode != 0) {
      return CommandResult(
        family: ResultFamily.upgradeBlocked,
        command: CommandNames.upgrade,
        message: 'Failed to clone framework source',
        blockers: ['Could not clone framework at revision $revision'],
        humanActionRequired: true,
      );
    }

    // Checkout the specific revision
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
        blockers: ['Revision $revision not found in framework source'],
        humanActionRequired: true,
      );
    }

    // Find the brick directory
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

    // Ensure target exists
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }

// Render using Mason
    final brick = Brick.path(brickDir.path);
    final generator = await MasonGenerator.fromBrick(brick);

    // Use empty vars for now - template inputs would come from manifest
    final vars = <String, dynamic>{};
    await generator.generate(
      DirectoryGeneratorTarget(targetDir),
      vars: vars,
      fileConflictResolution: FileConflictResolution.overwrite,
    );

    return CommandResult(
      family: ResultFamily.commandComplete,
      command: CommandNames.upgrade,
      message: 'Rendered framework revision $revision',
    );
  } finally {
    // Cleanup temp dir
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

/// Performs Git-native 3-way merge in the worktree.
///
/// Strategy:
/// 1. Copy product repo state (local) to worktree root
/// 2. Create commit for base (revision A render)
/// 3. Create commit for incoming (revision B render)
/// 4. Run `git merge` with base as merge-base
CommandResult _performThreeWayMerge({
  required Directory worktreeDir,
  required Directory baseDir,
  required Directory incomingDir,
  required Directory productRepo,
  required String revisionA,
  required String revisionB,
}) {
  // Initialize git in worktree if needed
  final gitInit = Process.runSync('git', ['init'], workingDirectory: worktreeDir.path);
  if (gitInit.exitCode != 0) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Failed to initialize Git in worktree',
      blockers: ['git init failed in worktree'],
    );
  }

  // Copy product repo state (local) to worktree root
  _copyDirectory(productRepo, worktreeDir);

  // Stage and commit product state as "local"
  Process.runSync('git', ['add', '-A'], workingDirectory: worktreeDir.path);
  Process.runSync('git', ['config', 'user.email', 'framework-cli@upgrade'], workingDirectory: worktreeDir.path);
  Process.runSync('git', ['config', 'user.name', 'Framework CLI Upgrade'], workingDirectory: worktreeDir.path);
  final localCommit = Process.runSync(
    'git',
    ['commit', '-m', 'Local product state (pre-upgrade)'],
    workingDirectory: worktreeDir.path,
  );
  if (localCommit.exitCode != 0) {
    // Might be nothing to commit - that's okay
  }

  // Create base branch from product state
  Process.runSync('git', ['branch', 'upgrade-base'], workingDirectory: worktreeDir.path);

  // Replace worktree content with base render (revision A)
  _clearDirectory(worktreeDir);
  _copyDirectory(baseDir, worktreeDir);
  Process.runSync('git', ['add', '-A'], workingDirectory: worktreeDir.path);
  Process.runSync(
    'git',
    ['commit', '-m', 'Base: framework revision $revisionA'],
    workingDirectory: worktreeDir.path,
  );

  // Create incoming branch from base
  Process.runSync('git', ['branch', 'upgrade-incoming', 'upgrade-base'], workingDirectory: worktreeDir.path);

  // Replace worktree content with incoming render (revision B)
  _clearDirectory(worktreeDir);
  _copyDirectory(incomingDir, worktreeDir);
  Process.runSync('git', ['add', '-A'], workingDirectory: worktreeDir.path);
  Process.runSync(
    'git',
    ['commit', '-m', 'Incoming: framework revision $revisionB'],
    workingDirectory: worktreeDir.path,
  );

  // Now merge: we want to merge incoming into local with base as merge-base
  // Switch back to local (main worktree branch)
  Process.runSync('git', ['checkout', '-b', 'upgrade-merge', 'upgrade-base'], workingDirectory: worktreeDir.path);

  // Merge incoming
  final mergeResult = Process.runSync(
    'git',
    ['merge', 'upgrade-incoming', '--no-commit', '--no-ff'],
    workingDirectory: worktreeDir.path,
  );

  // Check for conflicts
  final statusResult = Process.runSync(
    'git',
    ['status', '--porcelain'],
    workingDirectory: worktreeDir.path,
  );
  final hasConflicts = statusResult.stdout.toString().contains('UU') || statusResult.stdout.toString().contains('UD') || statusResult.stdout.toString().contains('DU');

  if (mergeResult.exitCode != 0 && !hasConflicts) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: CommandNames.upgrade,
      message: 'Git merge failed unexpectedly',
      blockers: ['Merge command failed: ${mergeResult.stderr}'],
    );
  }

  // If conflicts exist, leave them in worktree for review
  if (hasConflicts) {
    // Don't commit - leave conflicts for human resolution
    return CommandResult(
      family: ResultFamily.upgradeConflict,
      command: CommandNames.upgrade,
      message: 'Merge produced conflicts requiring resolution',
      blockers: ['Git merge conflicts detected in worktree'],
      humanActionRequired: true,
    );
  }

  // No conflicts - commit the merge
  Process.runSync(
    'git',
    ['commit', '-m', 'Merge framework upgrade $revisionA -> $revisionB'],
    workingDirectory: worktreeDir.path,
  );

  return CommandResult(
    family: ResultFamily.commandComplete,
    command: CommandNames.upgrade,
    message: '3-way merge completed successfully',
  );
}

/// Classifies changes between base, incoming, and merged result.
UpgradeClassification _classifyChanges({
  required Directory worktreeDir,
  required Directory baseDir,
  required Directory incomingDir,
  required FrameworkManifest currentManifest,
}) {
  final baseFiles = _collectFiles(baseDir);
  final incomingFiles = _collectFiles(incomingDir);
  final mergedFiles = _collectFiles(worktreeDir);
  final manifestPaths = currentManifest.managedPaths.toSet();

  final added = <String>[];
  final deleted = <String>[];
  final renamed = <MapEntry<String, String>>[];
  final modified = <String>[];
  final conflicts = <String>[];
  final unmodified = <String>[];

  // Get all unique paths across base, incoming, and manifest
  final allPaths = <String>{...baseFiles.keys, ...incomingFiles.keys, ...manifestPaths};

  for (final path in allPaths) {
    final inBase = baseFiles.containsKey(path);
    final inIncoming = incomingFiles.containsKey(path);
    final inManifest = manifestPaths.contains(path);
    final inMerged = mergedFiles.containsKey(path);

    // Check for Git conflicts (unmerged index entries)
    final conflictCheck = Process.runSync(
      'git',
      ['ls-files', '--unmerged', path],
      workingDirectory: worktreeDir.path,
    );
    if (conflictCheck.exitCode == 0 && conflictCheck.stdout.toString().trim().isNotEmpty) {
      conflicts.add(path);
      continue;
    }

    if (!inBase && inIncoming) {
      // Added in incoming (framework B)
      added.add(path);
    } else if (inBase && !inIncoming) {
      // Deleted in incoming (framework B)
      // Check delete policy: if locally modified, must not silently delete
      if (inManifest) {
        final matchingArtifacts = currentManifest.artifacts.where((a) => a.path == path);
        if (matchingArtifacts.isNotEmpty) {
          final artifact = matchingArtifacts.first;
          final detector = ModificationDetector();
          final inspection = detector.inspect(artifact, worktreeDir);
          if (inspection.state == ArtifactState.locallyModified) {
            // Locally modified + framework deleted = conflict
            conflicts.add(path);
            continue;
          }
        }
      }
      deleted.add(path);
    } else if (inBase && inIncoming) {
      // Exists in both - check for rename or modify
      final baseHash = ContentHash.ofFile(baseFiles[path]!);
      final incomingHash = ContentHash.ofFile(incomingFiles[path]!);

      if (baseHash == incomingHash) {
        // Unchanged in framework
        if (inMerged) {
          final mergedHash = ContentHash.ofFile(mergedFiles[path]!);
          if (mergedHash != baseHash) {
            modified.add(path);
          } else {
            unmodified.add(path);
          }
        } else {
          unmodified.add(path);
        }
      } else {
        // Framework modified this file
        // Check if it's a rename (same content, different path)
        bool isRename = false;
        for (final otherPath in baseFiles.keys) {
          if (otherPath != path) {
            final otherBaseHash = ContentHash.ofFile(baseFiles[otherPath]!);
            if (otherBaseHash == incomingHash) {
              // Content moved from otherPath to path
              renamed.add(MapEntry(otherPath, path));
              isRename = true;
              break;
            }
          }
        }
        if (!isRename) {
          modified.add(path);
        }
      }
    } else if (!inBase && !inIncoming && inManifest && !inMerged) {
      // Was in manifest but not in either render and not in merged = deleted by framework
      // Check local modification
      final matchingArtifacts = currentManifest.artifacts.where((a) => a.path == path);
      if (matchingArtifacts.isNotEmpty) {
        final artifact = matchingArtifacts.first;
        final detector = ModificationDetector();
        final inspection = detector.inspect(artifact, worktreeDir);
        if (inspection.state == ArtifactState.locallyModified) {
          conflicts.add(path);
        } else {
          deleted.add(path);
        }
      }
    }
  }

  return UpgradeClassification(
    added: added..sort(),
    deleted: deleted..sort(),
    renamed: renamed..sort((a, b) => a.key.compareTo(b.key)),
    modified: modified..sort(),
    conflicts: conflicts..sort(),
    unmodified: unmodified..sort(),
  );
}

/// Generates a reviewable diff between base and merged result.
String _generateReviewableDiff(
  Directory worktreeDir,
  Directory productRepo,
  String revisionA,
  String revisionB,
) {
  final diffResult = Process.runSync(
    'git',
    ['diff', 'HEAD', 'upgrade-merge', '--', '.'],
    workingDirectory: worktreeDir.path,
  );

  final diffOutput = diffResult.stdout.toString();
  final diffFile = File('${worktreeDir.path}/upgrade-diff-$revisionA-$revisionB.patch');
  diffFile.writeAsStringSync(diffOutput);

  return diffOutput;
}

/// Cleans up the worktree after upgrade.
void _cleanupWorktree(Directory productRepo, String branchName, Directory worktreeDir) {
  Process.runSync('git', ['worktree', 'remove', '--force', worktreeDir.path], workingDirectory: productRepo.path);
  Process.runSync('git', ['branch', '-D', branchName], workingDirectory: productRepo.path);
}

/// Copies directory contents recursively.
void _copyDirectory(Directory source, Directory target) {
  if (!source.existsSync()) return;
  for (final entity in source.listSync()) {
    final targetPath = '${target.path}/${entity.uri.pathSegments.last}';
    if (entity is File) {
      entity.copySync(targetPath);
    } else if (entity is Directory) {
      final targetDir = Directory(targetPath);
      targetDir.createSync(recursive: true);
      _copyDirectory(entity, targetDir);
    }
  }
}

/// Clears directory contents (keeps .git).
void _clearDirectory(Directory dir) {
  for (final entity in dir.listSync()) {
    if (entity is File) {
      entity.deleteSync();
    } else if (entity is Directory && entity.path != '${dir.path}/.git') {
      entity.deleteSync(recursive: true);
    }
  }
}

/// Collects all files in a directory recursively, returning map of relative path -> File.
Map<String, File> _collectFiles(Directory dir) {
  final result = <String, File>{};
  if (!dir.existsSync()) return result;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      final relPath = entity.path
          .replaceFirst(dir.absolute.path, '')
          .replaceAll('\\', '/');
      final normalized = relPath.startsWith('/') ? relPath.substring(1) : relPath;
      if (normalized.isNotEmpty) {
        result[normalized] = entity;
      }
    }
  }
  return result;
}