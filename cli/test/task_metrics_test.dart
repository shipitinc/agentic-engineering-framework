import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  // Package resolution remains stable when another integration test changes
  // the process-wide Directory.current.
  final repoRoot = _resolveFrameworkRepoPath();
  test(
    'distributed metrics work from an unrelated working directory',
    () async {
      final root = await repoRoot;
      final unrelated = Directory.systemTemp.createTempSync('aef_metrics_cwd_');
      try {
        final result = Process.runSync(
          Platform.isWindows ? 'python' : 'python3',
          ['-B', '$root/cli/test/fixtures/task_metrics/test_task_metrics.py'],
          workingDirectory: unrelated.path,
        );
        expect(
          result.exitCode,
          0,
          reason: 'stdout=${result.stdout}\nstderr=${result.stderr}',
        );
      } finally {
        unrelated.deleteSync(recursive: true);
      }
    },
  );
  test('fresh CLI bootstrap ships usable metrics and guidance', () async {
    final target = Directory.systemTemp.createTempSync('aef_metrics_');
    final root = await repoRoot;
    try {
      final bootstrap = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '$root/cli/bin/framework.dart',
          'bootstrap',
          '--target',
          target.path,
        ],
        workingDirectory: '$root/cli',
        environment: {
          'FRAMEWORK_CLI_TEST_MODE': 'true',
          'FRAMEWORK_REPO_PATH': root,
        },
      );
      expect(
        bootstrap.exitCode,
        0,
        reason: '${bootstrap.stdout}\n${bootstrap.stderr}',
      );
      final script = '${target.path}/scripts/aef/task-metrics.py';
      expect(File(script).existsSync(), isTrue);
      expect(
        File('${target.path}/docs/engineering/TASK_METRICS.md').existsSync(),
        isTrue,
      );
      final help = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [script, '--help'],
        workingDirectory: target.path,
      );
      expect(help.exitCode, 0, reason: '${help.stderr}');
      expect(help.stdout, contains('summary'));
    } finally {
      target.deleteSync(recursive: true);
    }
  }, timeout: Timeout(Duration(minutes: 3)));
}

Future<String> _resolveFrameworkRepoPath() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:framework_cli/framework_cli.dart'),
  );
  if (libraryUri == null || !libraryUri.isScheme('file')) {
    throw StateError(
      'framework_cli package did not resolve to a local checkout',
    );
  }
  return File.fromUri(libraryUri).parent.parent.parent.path;
}
