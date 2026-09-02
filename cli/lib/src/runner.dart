import 'package:args/args.dart';

import 'command_result.dart';
import 'commands.dart';
import 'output_renderer.dart';
import 'result_family.dart';
import 'version.dart';

/// The outcome of a CLI invocation: the domain [result] plus the exact text
/// that should be written to stdout.
class CliInvocation {
  const CliInvocation({required this.result, required this.output});

  /// The domain result produced by the invocation.
  final CommandResult result;

  /// The rendered output text (JSON or human), derived from [result].
  final String output;

  /// Deterministic process exit code derived from [result].
  int get exitCode => result.exitCode;
}

/// Parses and dispatches framework CLI commands to their domain handlers.
///
/// The runner performs no filesystem or repository mutation itself, and the
/// Phase 1 command handlers it dispatches to are all pure. Output is always
/// derived from the same [CommandResult] domain object, so JSON and
/// human-readable renderings can never diverge.
class FrameworkCliRunner {
  FrameworkCliRunner({OutputRenderer? renderer})
    : _renderer = renderer ?? const OutputRenderer();

  final OutputRenderer _renderer;

  /// Builds the top-level argument parser with one subcommand per command.
  ArgParser buildParser() {
    final parser = ArgParser();
    for (final name in CommandNames.all) {
      final sub = ArgParser()
        ..addFlag(
          'json',
          negatable: false,
          help: 'Emit deterministic machine-readable JSON output.',
        );
      parser.addCommand(name, sub);
    }
    return parser;
  }

  /// Runs the CLI for [args] and returns the invocation outcome.
  ///
  /// Never throws for user-facing errors: parse failures and unknown commands
  /// are converted into an [ResultFamily.internalError] domain result so the
  /// caller can render and exit deterministically.
  CliInvocation run(List<String> args) {
    final parser = buildParser();
    final ArgResults parsed;
    try {
      parsed = parser.parse(args);
    } on FormatException catch (e) {
      return _render(_usageError(e.message));
    }

    final command = parsed.command;
    if (command == null) {
      final name = args.isEmpty ? '' : args.first;
      if (name.isEmpty) {
        return _render(_usageError('No command provided.'));
      }
      return _render(_usageError("Unknown command '$name'."));
    }

    final useJson = command['json'] as bool;
    final result = _dispatch(command.name!);
    return _render(result, useJson: useJson);
  }

  CommandResult _dispatch(String name) {
    switch (name) {
      case CommandNames.bootstrap:
        return runBootstrap();
      case CommandNames.upgrade:
        return runUpgrade();
      case CommandNames.status:
        return runStatus();
      case CommandNames.doctor:
        return runDoctor();
      case CommandNames.version:
        return runVersion();
      default:
        // Unreachable: the parser only accepts registered commands.
        return _usageError("Unknown command '$name'.");
    }
  }

  CommandResult _usageError(String message) {
    return CommandResult(
      family: ResultFamily.internalError,
      command: 'framework',
      message:
          '$message Supported commands: ${CommandNames.all.join(', ')}. '
          '(framework_cli $frameworkCliVersion)',
      blockers: [message],
    );
  }

  CliInvocation _render(CommandResult result, {bool useJson = false}) {
    final output = useJson
        ? _renderer.renderJson(result)
        : _renderer.renderHuman(result);
    return CliInvocation(result: result, output: output);
  }
}
