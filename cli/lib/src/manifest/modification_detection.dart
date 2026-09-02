import 'dart:io';

import 'content_hash.dart';
import 'framework_manifest.dart';
import 'managed_artifact.dart';
import 'path_safety.dart';

/// Derived local-modification state of a single managed artifact.
///
/// This state is never persisted; it is always *derived* by comparing an
/// artifact's current on-disk content hash against its stored baseline
/// ([ManagedArtifact.installHash]) at inspection time (ADR 0002, mitigations
/// 15 and lines 117-118/182-183).
enum ArtifactState {
  /// Current content hash equals the stored baseline install hash.
  unchanged('UNCHANGED'),

  /// The file exists but its current content hash differs from the baseline.
  locallyModified('LOCALLY_MODIFIED'),

  /// The managed file does not exist on disk.
  missing('MISSING');

  const ArtifactState(this.stateName);

  /// Stable identifier suitable for machine-readable output.
  final String stateName;
}

/// Immutable result of inspecting one managed artifact against the working tree.
class ArtifactInspection {
  const ArtifactInspection({
    required this.path,
    required this.state,
    required this.baselineHash,
    required this.currentHash,
  });

  /// The normalized, repo-relative artifact path.
  final String path;

  /// The derived modification state.
  final ArtifactState state;

  /// The stored baseline install hash from the manifest.
  final ContentHash baselineHash;

  /// The freshly computed current content hash, or `null` if the file is
  /// [ArtifactState.missing].
  final ContentHash? currentHash;
}

/// Pure/derivable modification detection over a manifest's managed artifacts.
///
/// Given a [FrameworkManifest] and the product [repoRoot], this enumerates the
/// managed artifact inventory (with path-safety validation) and classifies each
/// artifact as [ArtifactState.unchanged], [ArtifactState.locallyModified], or
/// [ArtifactState.missing] by hashing current on-disk content and comparing it
/// to the stored baseline. It does not mutate anything.
class ModificationDetector {
  const ModificationDetector();

  /// The normalized, sorted managed-artifact inventory for [manifest].
  ///
  /// Paths are re-validated for safety (defense in depth); a
  /// [PathSafetyException] from a malformed manifest propagates to the caller.
  List<String> inventory(FrameworkManifest manifest) {
    return [
      for (final path in manifest.managedPaths) normalizeManagedPath(path),
    ];
  }

  /// Inspects every managed artifact in [manifest] relative to [repoRoot],
  /// returning inspections ordered by path (matching manifest ordering).
  List<ArtifactInspection> inspectAll(
    FrameworkManifest manifest,
    Directory repoRoot,
  ) {
    return [
      for (final artifact in manifest.artifacts) inspect(artifact, repoRoot),
    ];
  }

  /// Inspects a single [artifact] relative to [repoRoot].
  ArtifactInspection inspect(ManagedArtifact artifact, Directory repoRoot) {
    final file = resolveManagedFile(repoRoot, artifact.path);
    if (!file.existsSync()) {
      return ArtifactInspection(
        path: artifact.path,
        state: ArtifactState.missing,
        baselineHash: artifact.installHash,
        currentHash: null,
      );
    }
    final currentHash = ContentHash.ofFile(file);
    final state = currentHash == artifact.installHash
        ? ArtifactState.unchanged
        : ArtifactState.locallyModified;
    return ArtifactInspection(
      path: artifact.path,
      state: state,
      baselineHash: artifact.installHash,
      currentHash: currentHash,
    );
  }
}
