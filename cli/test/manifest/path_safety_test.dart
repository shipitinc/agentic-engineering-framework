import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeManagedPath', () {
    test('normalizes repo-relative paths to POSIX form', () {
      expect(
        normalizeManagedPath('.junie/agents/x.md'),
        equals('.junie/agents/x.md'),
      );
      expect(normalizeManagedPath('a/./b//c'), equals('a/b/c'));
      expect(normalizeManagedPath('a\\b\\c'), equals('a/b/c'));
      expect(
        normalizeManagedPath('  docs/readme.md  '),
        equals('docs/readme.md'),
      );
    });

    test('rejects absolute POSIX paths', () {
      expect(
        () => normalizeManagedPath('/etc/passwd'),
        throwsA(isA<PathSafetyException>()),
      );
    });

    test('rejects Windows drive-letter absolute paths', () {
      expect(
        () => normalizeManagedPath('C:\\Windows'),
        throwsA(isA<PathSafetyException>()),
      );
      expect(
        () => normalizeManagedPath('c:/x'),
        throwsA(isA<PathSafetyException>()),
      );
    });

    test('rejects parent-directory traversal', () {
      expect(
        () => normalizeManagedPath('../secret'),
        throwsA(isA<PathSafetyException>()),
      );
      expect(
        () => normalizeManagedPath('a/../../b'),
        throwsA(isA<PathSafetyException>()),
      );
    });

    test('rejects empty and dot-only paths', () {
      expect(
        () => normalizeManagedPath('   '),
        throwsA(isA<PathSafetyException>()),
      );
      expect(
        () => normalizeManagedPath('.'),
        throwsA(isA<PathSafetyException>()),
      );
    });
  });

  group('resolveManagedFile', () {
    test('resolves inside the repo root', () {
      final root = Directory.systemTemp.createTempSync('path_test_');
      try {
        final file = resolveManagedFile(root, 'a/b.txt');
        expect(file.path, startsWith(root.absolute.path));
        expect(file.path.replaceAll('\\', '/'), endsWith('a/b.txt'));
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('rejects traversal at resolution time', () {
      final root = Directory.systemTemp.createTempSync('path_test_');
      try {
        expect(
          () => resolveManagedFile(root, '../escape'),
          throwsA(isA<PathSafetyException>()),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}
