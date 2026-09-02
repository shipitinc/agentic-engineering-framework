import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

FrameworkManifest _sample() {
  return FrameworkManifest(
    source: 'github.com/example/agentic-engineering-framework',
    revision: '052f9930c0ffee00',
    version: '0.1.0',
    instantiatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    upgradedAt: DateTime.utc(2026, 6, 7, 8, 9, 10),
    artifacts: [
      ManagedArtifact(
        path: 'docs/readme.md',
        sourceHash: hashText('src-b'),
        installHash: hashText('inst-b'),
      ),
      ManagedArtifact(
        path: '.junie/agents/impl.md',
        sourceHash: hashText('src-a'),
        installHash: hashText('inst-a'),
      ),
    ],
    templateInputs: {'product_name': 'demo', 'app_id': 'x'},
  );
}

void main() {
  group('FrameworkManifest serialization', () {
    test('write is deterministic and byte-stable', () {
      final manifest = _sample();
      expect(manifest.write(), equals(manifest.write()));
    });

    test('write sorts artifacts by path and template_inputs by key', () {
      final text = _sample().write();
      final firstArtifact = text.indexOf('.junie/agents/impl.md');
      final secondArtifact = text.indexOf('docs/readme.md');
      expect(firstArtifact, lessThan(secondArtifact));
      final appId = text.indexOf('app_id');
      final productName = text.indexOf('product_name');
      expect(appId, lessThan(productName));
    });

    test('parse(write(m)) round-trips all fields', () {
      final original = _sample();
      final restored = FrameworkManifest.parse(original.write());
      expect(restored.source, equals(original.source));
      expect(restored.revision, equals(original.revision));
      expect(restored.version, equals(original.version));
      expect(restored.instantiatedAt, equals(original.instantiatedAt));
      expect(restored.upgradedAt, equals(original.upgradedAt));
      expect(restored.templateInputs, equals(original.templateInputs));
      expect(restored.managedPaths, equals(original.managedPaths));
      expect(restored.artifacts, equals(original.artifacts));
    });

    test('write then parse then write is identical (idempotent bytes)', () {
      final first = _sample().write();
      final second = FrameworkManifest.parse(first).write();
      expect(second, equals(first));
    });

    test('revision is preserved as authoritative over version', () {
      final m = FrameworkManifest.parse(_sample().write());
      expect(m.revision, equals('052f9930c0ffee00'));
      expect(m.revision, isNot(equals(m.version)));
    });

    test('handles empty artifacts and template_inputs', () {
      final m = FrameworkManifest(
        source: 's',
        revision: 'r',
        version: 'v',
        instantiatedAt: DateTime.utc(2026, 1, 1),
      );
      final text = m.write();
      expect(text, contains('artifacts: []'));
      expect(text, contains('template_inputs: {}'));
      final restored = FrameworkManifest.parse(text);
      expect(restored.artifacts, isEmpty);
      expect(restored.templateInputs, isEmpty);
      expect(restored.upgradedAt, isNull);
    });

    test('null upgraded_at round-trips', () {
      final m = FrameworkManifest(
        source: 's',
        revision: 'r',
        version: 'v',
        instantiatedAt: DateTime.utc(2026, 1, 1),
      );
      expect(m.write(), contains('upgraded_at: null'));
      expect(FrameworkManifest.parse(m.write()).upgradedAt, isNull);
    });

    test('quoted scalars survive special characters', () {
      final m = FrameworkManifest(
        source: 'a "quoted" \\ value',
        revision: 'r',
        version: 'v',
        instantiatedAt: DateTime.utc(2026, 1, 1),
        templateInputs: {'k': 'line1\nline2\ttab'},
      );
      final restored = FrameworkManifest.parse(m.write());
      expect(restored.source, equals('a "quoted" \\ value'));
      expect(restored.templateInputs['k'], equals('line1\nline2\ttab'));
    });
  });

  group('FrameworkManifest parse rejection', () {
    test('rejects non-mapping root', () {
      expect(
        () => FrameworkManifest.parse('- a\n- b'),
        throwsA(isA<ManifestFormatException>()),
      );
    });

    test('rejects wrong schema_version', () {
      const text =
          'schema_version: 99\n'
          'framework:\n  source: "s"\n  revision: "r"\n  version: "v"\n'
          'product:\n  instantiated_at: "2026-01-01T00:00:00Z"\n';
      expect(
        () => FrameworkManifest.parse(text),
        throwsA(isA<ManifestFormatException>()),
      );
    });

    test('rejects missing framework.revision', () {
      const text =
          'schema_version: 1\n'
          'framework:\n  source: "s"\n  version: "v"\n'
          'product:\n  instantiated_at: "2026-01-01T00:00:00Z"\n';
      expect(
        () => FrameworkManifest.parse(text),
        throwsA(isA<ManifestFormatException>()),
      );
    });

    test('rejects an artifact with an unsafe path', () {
      final text =
          'schema_version: 1\n'
          'framework:\n  source: "s"\n  revision: "r"\n  version: "v"\n'
          'product:\n  instantiated_at: "2026-01-01T00:00:00Z"\n'
          'artifacts:\n'
          '  - path: "../escape"\n'
          '    source_hash: "sha256:${'a' * 64}"\n'
          '    install_hash: "sha256:${'b' * 64}"\n';
      expect(
        () => FrameworkManifest.parse(text),
        throwsA(isA<PathSafetyException>()),
      );
    });
  });
}
