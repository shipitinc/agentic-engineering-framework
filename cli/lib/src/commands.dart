import 'command_result.dart';
import 'result_family.dart';
import 'version.dart';

/// Names of all supported framework commands.
class CommandNames {
  const CommandNames._();

  static const String bootstrap = 'bootstrap';
  static const String upgrade = 'upgrade';
  static const String status = 'status';
  static const String doctor = 'doctor';
  static const String version = 'version';

  /// All command names, in stable display order.
  static const List<String> all = [bootstrap, upgrade, status, doctor, version];
}

/// Produces a [CommandResult] for an explicit NOT_IMPLEMENTED stub command.
///
/// Phase 1 stubs must never report success and must never mutate any
/// repository or external state. These builders are pure functions: they only
/// construct a domain object and perform no I/O.
CommandResult notImplementedResult(String command) {
  return CommandResult(
    family: ResultFamily.notImplemented,
    command: command,
    message:
        "Command '$command' is not implemented in Phase 1. "
        'It performs no action and mutates no state.',
    blockers: ['$command is not implemented yet (Phase 1 skeleton).'],
  );
}

/// The `bootstrap` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runBootstrap() => notImplementedResult(CommandNames.bootstrap);

/// The `upgrade` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runUpgrade() => notImplementedResult(CommandNames.upgrade);

/// The `status` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runStatus() => notImplementedResult(CommandNames.status);

/// The `doctor` stub (Phase 1: NOT_IMPLEMENTED, no side effects).
CommandResult runDoctor() => notImplementedResult(CommandNames.doctor);

/// The `version` command — implemented for real; prints the version string.
CommandResult runVersion() {
  return CommandResult(
    family: ResultFamily.commandComplete,
    command: CommandNames.version,
    message: 'framework $frameworkCliVersion',
  );
}
