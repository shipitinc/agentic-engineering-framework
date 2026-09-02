import 'exit_category.dart';
import 'result_family.dart';

/// Immutable domain result of running a framework command.
///
/// This is the single source of truth for both machine-readable (`--json`) and
/// human-readable output. Success and exit semantics are derived from
/// [family] via the centralized [exitCategoryFor] mapping — they are never set
/// independently, so the two output renderings can never diverge.
class CommandResult {
  CommandResult({
    required this.family,
    required this.command,
    required this.message,
    List<String> blockers = const [],
    this.humanActionRequired = false,
  }) : blockers = List.unmodifiable(blockers);

  /// The domain result family (authoritative outcome classification).
  final ResultFamily family;

  /// The command this result was produced for (e.g. `bootstrap`).
  final String command;

  /// A short, human-readable summary of the outcome.
  final String message;

  /// Ordered, deterministic list of blocking reasons (may be empty).
  final List<String> blockers;

  /// Whether a human decision/action is required to proceed.
  final bool humanActionRequired;

  /// The semantic exit category derived from [family].
  ExitCategory get exitCategory => exitCategoryFor(family);

  /// The deterministic process exit code derived from [exitCategory].
  int get exitCode => exitCategory.exitCode;

  /// Whether this outcome is a success (no blocking issue).
  bool get success => exitCategory.isSuccess;

  /// Whether this outcome blocks progress (any non-success outcome).
  bool get blocking => !success;

  /// Deterministic, machine-readable representation used for `--json`.
  ///
  /// Key order is fixed so JSON output is byte-stable across runs.
  Map<String, Object?> toJson() {
    return {
      'result': family.familyName,
      'command': command,
      'success': success,
      'blocking': blocking,
      'exit_category': exitCategory.categoryName,
      'exit_code': exitCode,
      'message': message,
      'blockers': blockers,
      'human_action_required': humanActionRequired,
    };
  }
}
