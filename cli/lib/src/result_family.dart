import 'exit_category.dart';

/// The domain result families produced by framework commands.
///
/// Each family maps to exactly one [ExitCategory] via the centralized mapping
/// in [exitCategoryFor]. This is the single source of truth for translating a
/// domain outcome into a semantic exit category (and therefore an exit code).
enum ResultFamily {
  bootstrapComplete('BOOTSTRAP_COMPLETE'),
  bootstrapBlocked('BOOTSTRAP_BLOCKED'),
  upgradeReadyForReview('UPGRADE_READY_FOR_REVIEW'),
  upgradeNoop('UPGRADE_NOOP'),
  upgradeConflict('UPGRADE_CONFLICT'),
  upgradeBlocked('UPGRADE_BLOCKED'),
  humanDecisionRequired('HUMAN_DECISION_REQUIRED'),
  validationFailed('VALIDATION_FAILED'),
  internalError('INTERNAL_ERROR'),
  notImplemented('NOT_IMPLEMENTED'),

  /// Generic successful, non-blocking outcome (e.g. `version`).
  commandComplete('COMMAND_COMPLETE');

  const ResultFamily(this.familyName);

  /// Stable identifier emitted in machine-readable output.
  final String familyName;
}

/// Centralized, exhaustive mapping from a [ResultFamily] to its semantic
/// [ExitCategory]. This is the ONLY place families are translated to
/// categories, keeping exit semantics consistent across the CLI.
ExitCategory exitCategoryFor(ResultFamily family) {
  switch (family) {
    case ResultFamily.bootstrapComplete:
    case ResultFamily.upgradeNoop:
    case ResultFamily.commandComplete:
      return ExitCategory.success;
    case ResultFamily.upgradeReadyForReview:
    case ResultFamily.upgradeConflict:
      return ExitCategory.mergeActionRequired;
    case ResultFamily.bootstrapBlocked:
    case ResultFamily.upgradeBlocked:
    case ResultFamily.validationFailed:
      return ExitCategory.preflightPolicyFailure;
    case ResultFamily.humanDecisionRequired:
      return ExitCategory.humanDecisionRequired;
    case ResultFamily.internalError:
      return ExitCategory.internalToolFailure;
    case ResultFamily.notImplemented:
      return ExitCategory.notImplemented;
  }
}
