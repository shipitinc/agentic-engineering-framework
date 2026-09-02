import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('ModificationDetector', () {
    late Directory repoRoot;

    setUp(() {
      repoRoot = Directory.systemTemp.createTempSync('modif_test_');
    });

    tearDown(() {
      if (repoRoot.existsSync()) {
        repoRoot.deleteSync(recursive: true);
      }
    });

    ManagedArtifact writeArtifact(String path, String content) {
      final file = File('${repoRoot.path}/$path');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
      final hash = hashText(content);
      return ManagedArtifact(path: path, sourceHash: hash, installHash: hash);
    }

    FrameworkManifest manifestOf(List<ManagedArtifact> artifacts) {
      return FrameworkManifest(
        source: 's',
        revision: 'r',
        version: 'v',
        instantiatedAt: DateTime.utc(2026, 1, 1),
        artifacts: artifacts,
      );
    }

    test('inventory returns sorted normalized paths', () {
      final manifest = manifestOf([
        writeArtifact('b/z.txt', 'b'),
        writeArtifact('a/y.txt', 'a'),
      ]);
      expect(
        const ModificationDetector().inventory(manifest),
        equals(['a/y.txt', 'b/z.txt']),
      );
    });

    test('classifies unchanged when content matches baseline', () {
      final artifact = writeArtifact('a.txt', 'stable content');
      final inspection = const ModificationDetector().inspect(
        artifact,
        repoRoot,
      );
      expect(inspection.state, equals(ArtifactState.unchanged));
      expect(inspection.currentHash, equals(artifact.installHash));
    });

    test('classifies locally-modified when content changed', () {
      final artifact = writeArtifact('a.txt', 'original');
      File('${repoRoot.path}/a.txt').writeAsStringSync('tampered');
      final inspection = const ModificationDetector().inspect(
        artifact,
        repoRoot,
      );
      expect(inspection.state, equals(ArtifactState.locallyModified));
      expect(inspection.currentHash, isNot(equals(artifact.installHash)));
    });

    test('classifies missing when file absent', () {
      final artifact = writeArtifact('a.txt', 'x');
      File('${repoRoot.path}/a.txt').deleteSync();
      final inspection = const ModificationDetector().inspect(
        artifact,
        repoRoot,
      );
      expect(inspection.state, equals(ArtifactState.missing));
      expect(inspection.currentHash, isNull);
    });

    test('line-ending-only changes are treated as unchanged', () {
      final artifact = writeArtifact('a.txt', 'l1\nl2\n');
      File('${repoRoot.path}/a.txt').writeAsStringSync('l1\r\nl2\r\n');
      final inspection = const ModificationDetector().inspect(
        artifact,
        repoRoot,
      );
      expect(inspection.state, equals(ArtifactState.unchanged));
    });

    test('inspectAll covers a mixed working tree', () {
      final unchanged = writeArtifact('keep.txt', 'keep');
      final modified = writeArtifact('mod.txt', 'before');
      final gone = writeArtifact('gone.txt', 'gone');
      File('${repoRoot.path}/mod.txt').writeAsStringSync('after');
      File('${repoRoot.path}/gone.txt').deleteSync();

      final manifest = manifestOf([unchanged, modified, gone]);
      final states = {
        for (final i in const ModificationDetector().inspectAll(
          manifest,
          repoRoot,
        ))
          i.path: i.state,
      };
      expect(states['keep.txt'], equals(ArtifactState.unchanged));
      expect(states['mod.txt'], equals(ArtifactState.locallyModified));
      expect(states['gone.txt'], equals(ArtifactState.missing));
    });
  });
}
