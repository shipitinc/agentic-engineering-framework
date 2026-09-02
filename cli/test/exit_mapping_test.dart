import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('result-family -> exit-category mapping', () {
    const expected = <ResultFamily, ExitCategory>{
      ResultFamily.bootstrapComplete: ExitCategory.success,
      ResultFamily.upgradeNoop: ExitCategory.success,
      ResultFamily.commandComplete: ExitCategory.success,
      ResultFamily.upgradeReadyForReview: ExitCategory.mergeActionRequired,
      ResultFamily.upgradeConflict: ExitCategory.mergeActionRequired,
      ResultFamily.bootstrapBlocked: ExitCategory.preflightPolicyFailure,
      ResultFamily.upgradeBlocked: ExitCategory.preflightPolicyFailure,
      ResultFamily.validationFailed: ExitCategory.preflightPolicyFailure,
      ResultFamily.humanDecisionRequired: ExitCategory.humanDecisionRequired,
      ResultFamily.internalError: ExitCategory.internalToolFailure,
      ResultFamily.notImplemented: ExitCategory.notImplemented,
    };

    test('every family maps to the expected category', () {
      for (final entry in expected.entries) {
        expect(
          exitCategoryFor(entry.key),
          entry.value,
          reason: 'family ${entry.key.familyName}',
        );
      }
    });

    test('mapping is exhaustive (all families covered)', () {
      for (final family in ResultFamily.values) {
        expect(
          expected.containsKey(family),
          isTrue,
          reason: 'missing expectation for ${family.familyName}',
        );
      }
    });

    test('ADR 0002 exit codes are stable', () {
      expect(ExitCategory.success.exitCode, 0);
      expect(ExitCategory.mergeActionRequired.exitCode, 10);
      expect(ExitCategory.preflightPolicyFailure.exitCode, 20);
      expect(ExitCategory.humanDecisionRequired.exitCode, 30);
      expect(ExitCategory.internalToolFailure.exitCode, 40);
    });

    test('NOT_IMPLEMENTED maps to a distinct non-success code', () {
      final category = exitCategoryFor(ResultFamily.notImplemented);
      expect(category, ExitCategory.notImplemented);
      expect(category.exitCode, 50);
      expect(category.isSuccess, isFalse);
      // Must not collide with any ADR-defined category code.
      final adrCodes = {0, 10, 20, 30, 40};
      expect(adrCodes.contains(category.exitCode), isFalse);
    });

    test('exit codes are unique across all categories', () {
      final codes = ExitCategory.values.map((c) => c.exitCode).toList();
      expect(codes.toSet().length, codes.length);
    });
  });
}
