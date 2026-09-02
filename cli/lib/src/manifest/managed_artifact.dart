import 'content_hash.dart';
import 'path_safety.dart';

/// An immutable record of a single framework-managed artifact.
///
/// Each managed artifact records its repo-relative [path] plus two baseline
/// hashes captured at install/upgrade time:
///
/// - [sourceHash] — the hash of the framework *source* content the artifact was
///   rendered from (provenance of what the framework shipped);
/// - [installHash] — the hash of the content actually *installed* into the
///   product repository at that time (the baseline for modification detection).
///
/// Local-modification state is **not** stored here; it is derived by comparing
/// the artifact's *current* on-disk hash against [installHash]
/// (ADR 0002, mitigation 15). Keeping this class a small, immutable value with
/// deterministic ordering mirrors the existing Phase 1 domain model.
class ManagedArtifact implements Comparable<ManagedArtifact> {
  /// Creates a managed artifact, normalizing and safety-checking [path].
  ///
  /// Throws [PathSafetyException] if [path] is not a safe repo-relative path.
  ManagedArtifact({
    required String path,
    required this.sourceHash,
    required this.installHash,
  }) : path = normalizeManagedPath(path);

  /// The normalized, safety-validated, repo-relative POSIX path.
  final String path;

  /// Baseline hash of the framework source the artifact was rendered from.
  final ContentHash sourceHash;

  /// Baseline hash of the content installed into the product repository.
  final ContentHash installHash;

  /// Parses a managed artifact from a decoded YAML mapping [map].
  ///
  /// Throws [FormatException] if a required key is missing or malformed.
  factory ManagedArtifact.fromMap(Map<Object?, Object?> map) {
    final path = _requireString(map, 'path');
    final sourceHash = _requireString(map, 'source_hash');
    final installHash = _requireString(map, 'install_hash');
    return ManagedArtifact(
      path: path,
      sourceHash: ContentHash.parse(sourceHash),
      installHash: ContentHash.parse(installHash),
    );
  }

  /// Deterministic key/value pairs for serialization, in fixed emission order.
  ///
  /// Order is fixed (`path`, `source_hash`, `install_hash`) so the written
  /// manifest is byte-stable across runs.
  List<MapEntry<String, String>> toOrderedEntries() {
    return [
      MapEntry('path', path),
      MapEntry('source_hash', sourceHash.toString()),
      MapEntry('install_hash', installHash.toString()),
    ];
  }

  /// Artifacts are ordered by their normalized [path] for deterministic output.
  @override
  int compareTo(ManagedArtifact other) => path.compareTo(other.path);

  @override
  bool operator ==(Object other) =>
      other is ManagedArtifact &&
      other.path == path &&
      other.sourceHash == sourceHash &&
      other.installHash == installHash;

  @override
  int get hashCode => Object.hash(path, sourceHash, installHash);

  static String _requireString(Map<Object?, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing or invalid artifact field "$key"', map);
    }
    return value;
  }
}
