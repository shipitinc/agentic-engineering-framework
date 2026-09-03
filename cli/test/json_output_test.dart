import 'dart:convert';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('JSON serialization', () {
    test('includes all required keys', () {
      final result = CommandResult(
        family: ResultFamily.upgradeConflict,
        command: 'upgrade',
        message: 'conflict',
        blockers: ['a', 'b'],
        humanActionRequired: true,
      );
      final json = result.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'result',
          'command',
          'success',
          'blocking',
          'exit_category',
          'exit_code',
          'message',
          'blockers',
          'human_action_required',
        ]),
      );
    });

    test('serializes derived values correctly', () {
      final result = CommandResult(
        family: ResultFamily.notImplemented,
        command: 'bootstrap',
        message: 'stub',
        blockers: ['not implemented'],
      );
      final json = result.toJson();
      expect(json['result'], 'NOT_IMPLEMENTED');
      expect(json['command'], 'bootstrap');
      expect(json['success'], isFalse);
      expect(json['blocking'], isTrue);
      expect(json['exit_category'], 'NOT_IMPLEMENTED');
      expect(json['exit_code'], 50);
      expect(json['message'], 'stub');
      expect(json['blockers'], ['not implemented']);
      expect(json['human_action_required'], isFalse);
    });

    test('is valid, round-trippable JSON via the renderer', () async {
      final runner = FrameworkCliRunner();
      final invocation = await runner.run(['upgrade', '--json']);
      final decoded = jsonDecode(invocation.output) as Map<String, Object?>;
      expect(decoded['result'], 'UPGRADE_BLOCKED');
      expect(decoded['command'], 'upgrade');
    });

    test('--json output is deterministic across runs', () async {
      final runner = FrameworkCliRunner();
      final first = (await runner.run(['status', '--json'])).output;
      final second = (await runner.run(['status', '--json'])).output;
      expect(first, second);
    });

    test('JSON key order is stable', () {
      final result = runVersion();
      final keys = result.toJson().keys.toList();
      expect(keys, [
        'result',
        'command',
        'success',
        'blocking',
        'exit_category',
        'exit_code',
        'message',
        'blockers',
        'human_action_required',
      ]);
    });
  });
}
