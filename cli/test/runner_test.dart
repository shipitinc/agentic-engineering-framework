import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  final runner = FrameworkCliRunner();

  group('command parsing', () {
    test('parses each known command', () async {
      for (final name in CommandNames.all) {
        final invocation = await runner.run([name]);
        expect(invocation.result.command, name);
      }
    });

    test('parses --json flag per command', () async {
      final human = await runner.run(['status']);
      final json = await runner.run(['status', '--json']);
      expect(human.output, isNot(equals(json.output)));
      expect(json.output.trimLeft(), startsWith('{'));
    });
  });

  group('version command', () {
    test('reports success with exit code 0', () async {
      final invocation = await runner.run(['version']);
      expect(invocation.result.success, isTrue);
      expect(invocation.exitCode, 0);
      expect(invocation.output, contains(frameworkCliVersion));
    });
  });

  group('stub commands do not report success', () {
    for (final name in ['status', 'doctor']) {
      test('$name is NOT_IMPLEMENTED, non-success, non-zero exit', () async {
        final invocation = await runner.run([name]);
        expect(invocation.result.family, ResultFamily.notImplemented);
        expect(invocation.result.success, isFalse);
        expect(invocation.result.blocking, isTrue);
        expect(invocation.exitCode, isNot(0));
        expect(invocation.exitCode, 50);
      });
    }
    test(
      'bootstrap is bootstrapBlocked (Phase 3 preflight), non-success, non-zero exit',
      () async {
        final invocation = await runner.run(['bootstrap']);
        expect(invocation.result.family, ResultFamily.bootstrapBlocked);
        expect(invocation.result.success, isFalse);
        expect(invocation.result.blocking, isTrue);
        expect(invocation.exitCode, isNot(0));
      },
    );
    test(
      'upgrade is UPGRADE_BLOCKED (Phase 4 preflight), non-success, non-zero exit',
      () async {
        final invocation = await runner.run(['upgrade']);
        expect(invocation.result.family, ResultFamily.upgradeBlocked);
        expect(invocation.result.success, isFalse);
        expect(invocation.result.blocking, isTrue);
        expect(invocation.exitCode, isNot(0));
      },
    );
  });

  group('invalid / unknown command handling', () {
    test('unknown command => INTERNAL_ERROR, non-zero exit', () async {
      final invocation = await runner.run(['frobnicate']);
      expect(invocation.result.family, ResultFamily.internalError);
      expect(invocation.result.success, isFalse);
      expect(invocation.exitCode, 40);
    });

    test('no command => INTERNAL_ERROR, non-zero exit', () async {
      final invocation = await runner.run([]);
      expect(invocation.result.family, ResultFamily.internalError);
      expect(invocation.exitCode, 40);
    });

    test('unknown flag => INTERNAL_ERROR', () async {
      final invocation = await runner.run(['status', '--nope']);
      expect(invocation.result.family, ResultFamily.internalError);
      expect(invocation.exitCode, 40);
    });
  });
}