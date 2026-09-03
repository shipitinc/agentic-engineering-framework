import 'dart:convert';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('human output derived from same domain result', () {
    const renderer = OutputRenderer();

    test('human rendering reflects the same domain values as JSON', () {
      final result = CommandResult(
        family: ResultFamily.upgradeConflict,
        command: 'upgrade',
        message: 'merge conflict detected',
        blockers: ['file X conflicts'],
        humanActionRequired: true,
      );

      final human = renderer.renderHuman(result);
      final json =
          jsonDecode(renderer.renderJson(result)) as Map<String, Object?>;

      expect(human, contains(result.command));
      expect(human, contains(result.family.familyName));
      expect(human, contains(result.message));
      expect(human, contains(result.exitCategory.categoryName));
      expect(human, contains('exit_code=${result.exitCode}'));
      expect(human, contains('file X conflicts'));
      expect(human, contains('human_action_required'));

      // Same underlying values as the JSON rendering.
      expect(json['exit_code'], result.exitCode);
      expect(json['exit_category'], result.exitCategory.categoryName);
    });

    test('success result renders OK, blocking renders BLOCKED', () async {
      final ok = renderer.renderHuman(await runVersion());
      final blocked = renderer.renderHuman(await runBootstrap());
      expect(ok, startsWith('[OK]'));
      expect(blocked, startsWith('[BLOCKED]'));
    });

    test('no blockers => no blockers section', () {
      final human = renderer.renderHuman(runVersion());
      expect(human, isNot(contains('blockers:')));
    });
  });
}
