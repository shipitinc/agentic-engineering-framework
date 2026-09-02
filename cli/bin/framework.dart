import 'dart:io';

import 'package:framework_cli/framework_cli.dart';

/// Entrypoint for the `framework` CLI.
///
/// Delegates parsing/dispatch to [FrameworkCliRunner], prints the rendered
/// output (JSON with `--json`, human-readable otherwise), and exits with the
/// deterministic semantic exit code derived from the domain result.
void main(List<String> args) {
  final runner = FrameworkCliRunner();
  final invocation = runner.run(args);
  final sink = invocation.result.success ? stdout : stderr;
  sink.writeln(invocation.output);
  exit(invocation.exitCode);
}
