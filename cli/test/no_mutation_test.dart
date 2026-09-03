import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

/// Recursively lists paths under [dir] relative to it, sorted for stability.
List<String> _snapshot(Directory dir) {
  return dir
      .listSync(recursive: true, followLinks: false)
      .map((e) => e.path)
      .toList()
    ..sort();
}

void main() {
  group('stub commands mutate no filesystem/repo state', () {
    late Directory sandbox;
    late Directory previousCwd;

    setUp(() {
      previousCwd = Directory.current;
      sandbox = Directory.systemTemp.createTempSync('framework_cli_test_');
      Directory.current = sandbox;
    });

    tearDown(() {
      Directory.current = previousCwd;
      if (sandbox.existsSync()) {
        sandbox.deleteSync(recursive: true);
      }
    });

    test('running every stub leaves the working tree unchanged', () async {
      final before = _snapshot(sandbox);
      final runner = FrameworkCliRunner();

      for (final name in ['bootstrap', 'upgrade', 'status', 'doctor']) {
        for (final args in [
          [name],
          [name, '--json'],
        ]) {
          final invocation = await runner.run(args);
          // Sanity: stubs never report success.
          expect(invocation.result.success, isFalse);
        }
      }

      final after = _snapshot(sandbox);
      expect(after, before);
      expect(after, isEmpty);
    });

    test('direct stub builders create no files', () async {
      await runBootstrap();
      await runUpgrade();
      runStatus();
      runDoctor();
      expect(_snapshot(sandbox), isEmpty);
    });
  });
}
