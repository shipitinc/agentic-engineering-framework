import 'package:yaml/yaml.dart';

import 'managed_artifact.dart';

/// Raised when a `framework-manifest.yaml` document is structurally invalid.
class ManifestFormatException implements Exception {
  ManifestFormatException(this.message);

  /// Human-readable description of the structural problem.
  final String message;

  @override
  String toString() => 'ManifestFormatException: $message';
}

/// The authoritative, Mason-independent framework manifest for a product repo.
///
/// This is the single source of truth for framework provenance in an
/// instantiated product repository. It is intentionally a small, well-defined
/// YAML schema that is understandable **without** Mason (ADR 0002, mitigation
/// 11): no brick caches, lockfiles, or tool state are required to read it.
///
/// Per the ADR 0002 provenance rule, [revision] is the authoritative, immutable
/// exact framework revision and takes precedence over the human-readable
/// [version]. Optional [templateInputs] are kept **separate** from provenance
/// so template-input data can never be confused with the authoritative source
/// identity/revision.
///
/// Instances are immutable; [write] emits deterministic, byte-stable YAML with
/// sorted keys and sorted artifacts so repeated writes of equal manifests are
/// identical.
class FrameworkManifest {
  FrameworkManifest({
    required this.source,
    required this.revision,
    required this.version,
    required this.instantiatedAt,
    this.upgradedAt,
    List<ManagedArtifact> artifacts = const [],
    Map<String, String> templateInputs = const {},
  }) : artifacts = List.unmodifiable([...artifacts]..sort()),
       templateInputs = Map.unmodifiable(_sortedStringMap(templateInputs));

  /// The current manifest schema version. Bumped only on breaking changes.
  static const int schemaVersion = 1;

  /// Framework source identity (e.g. canonical repository identifier/URL).
  final String source;

  /// Authoritative, immutable exact framework revision (ADR 0002 provenance).
  final String revision;

  /// Human-readable framework version (subordinate to [revision]).
  final String version;

  /// Timestamp the product was first instantiated from the framework (UTC).
  final DateTime instantiatedAt;

  /// Timestamp of the most recent framework upgrade, or `null` if never
  /// upgraded since instantiation (UTC).
  final DateTime? upgradedAt;

  /// Managed artifacts, sorted by path for deterministic output.
  final List<ManagedArtifact> artifacts;

  /// Optional template input provenance, kept SEPARATE from framework
  /// provenance (ADR 0002 / ADR 0001). Sorted by key for determinism.
  final Map<String, String> templateInputs;

  /// Parses a manifest from its YAML [yamlText] representation.
  ///
  /// Throws [ManifestFormatException] if the document is not a mapping or a
  /// required field is missing/malformed.
  factory FrameworkManifest.parse(String yamlText) {
    final Object? doc;
    try {
      doc = loadYaml(yamlText);
    } on YamlException catch (e) {
      throw ManifestFormatException('invalid YAML: $e');
    }
    if (doc is! YamlMap) {
      throw ManifestFormatException('root document must be a mapping');
    }

    final schema = doc['schema_version'];
    if (schema is! int) {
      throw ManifestFormatException('missing or invalid "schema_version"');
    }
    if (schema != schemaVersion) {
      throw ManifestFormatException(
        'unsupported schema_version $schema (expected $schemaVersion)',
      );
    }

    final framework = _requireMap(doc, 'framework');
    final product = _requireMap(doc, 'product');

    final artifactsNode = doc['artifacts'];
    final artifacts = <ManagedArtifact>[];
    if (artifactsNode != null) {
      if (artifactsNode is! YamlList) {
        throw ManifestFormatException('"artifacts" must be a list');
      }
      for (final entry in artifactsNode) {
        if (entry is! YamlMap) {
          throw ManifestFormatException('each artifact must be a mapping');
        }
        try {
          artifacts.add(ManagedArtifact.fromMap(entry));
        } on FormatException catch (e) {
          throw ManifestFormatException('invalid artifact: ${e.message}');
        }
      }
    }

    final templateInputs = <String, String>{};
    final inputsNode = doc['template_inputs'];
    if (inputsNode != null) {
      if (inputsNode is! YamlMap) {
        throw ManifestFormatException('"template_inputs" must be a mapping');
      }
      inputsNode.forEach((key, value) {
        templateInputs['$key'] = '$value';
      });
    }

    return FrameworkManifest(
      source: _requireString(framework, 'source', 'framework'),
      revision: _requireString(framework, 'revision', 'framework'),
      version: _requireString(framework, 'version', 'framework'),
      instantiatedAt: _requireTimestamp(product, 'instantiated_at', 'product'),
      upgradedAt: _optionalTimestamp(product, 'upgraded_at', 'product'),
      artifacts: artifacts,
      templateInputs: templateInputs,
    );
  }

  /// Serializes the manifest to deterministic, byte-stable YAML.
  ///
  /// Emission order is fixed and every scalar string is double-quoted and
  /// escaped, so equal manifests always produce identical bytes regardless of
  /// insertion order (ADR 0002, mitigation 11 — no Mason metadata is emitted).
  String write() {
    final buffer = StringBuffer();
    buffer.writeln('schema_version: $schemaVersion');
    buffer.writeln('framework:');
    buffer.writeln('  source: ${_scalar(source)}');
    buffer.writeln('  revision: ${_scalar(revision)}');
    buffer.writeln('  version: ${_scalar(version)}');
    buffer.writeln('product:');
    buffer.writeln('  instantiated_at: ${_scalar(_iso(instantiatedAt))}');
    final upgraded = upgradedAt;
    buffer.writeln(
      '  upgraded_at: ${upgraded == null ? 'null' : _scalar(_iso(upgraded))}',
    );

    if (artifacts.isEmpty) {
      buffer.writeln('artifacts: []');
    } else {
      buffer.writeln('artifacts:');
      for (final artifact in artifacts) {
        final entries = artifact.toOrderedEntries();
        var first = true;
        for (final entry in entries) {
          final prefix = first ? '  - ' : '    ';
          buffer.writeln('$prefix${entry.key}: ${_scalar(entry.value)}');
          first = false;
        }
      }
    }

    if (templateInputs.isEmpty) {
      buffer.writeln('template_inputs: {}');
    } else {
      buffer.writeln('template_inputs:');
      for (final entry in templateInputs.entries) {
        buffer.writeln('  ${_scalar(entry.key)}: ${_scalar(entry.value)}');
      }
    }

    return buffer.toString();
  }

  /// The normalized, sorted list of managed artifact paths.
  List<String> get managedPaths => [for (final a in artifacts) a.path];

  static Map<String, String> _sortedStringMap(Map<String, String> input) {
    final keys = input.keys.toList()..sort();
    return {for (final k in keys) k: input[k]!};
  }

  static String _iso(DateTime dt) => dt.toUtc().toIso8601String();

  /// Double-quotes and escapes a scalar string for safe, deterministic YAML.
  static String _scalar(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  static YamlMap _requireMap(YamlMap parent, String key) {
    final value = parent[key];
    if (value is! YamlMap) {
      throw ManifestFormatException('missing or invalid "$key" mapping');
    }
    return value;
  }

  static String _requireString(YamlMap map, String key, String section) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw ManifestFormatException('missing or invalid "$section.$key"');
    }
    return value;
  }

  static DateTime _requireTimestamp(YamlMap map, String key, String section) {
    final value = _optionalTimestamp(map, key, section);
    if (value == null) {
      throw ManifestFormatException('missing "$section.$key"');
    }
    return value;
  }

  static DateTime? _optionalTimestamp(YamlMap map, String key, String section) {
    final value = map[key];
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed == null) {
        throw ManifestFormatException('invalid timestamp "$section.$key"');
      }
      return parsed.toUtc();
    }
    throw ManifestFormatException('invalid timestamp "$section.$key"');
  }
}
