import 'dart:convert';

import 'command_result.dart';

/// Renders a [CommandResult] into output strings.
///
/// Both renderings are derived exclusively from the same [CommandResult]
/// domain object, guaranteeing a single source of truth.
class OutputRenderer {
  const OutputRenderer();

  /// Deterministic pretty-printed JSON rendering (used with `--json`).
  ///
  /// Uses a fixed key order and two-space indentation so output is stable and
  /// diff-friendly across runs.
  String renderJson(CommandResult result) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(result.toJson());
  }

  /// Human-readable rendering derived from the same [CommandResult].
  String renderHuman(CommandResult result) {
    final buffer = StringBuffer();
    final status = result.success ? 'OK' : 'BLOCKED';
    buffer.writeln('[$status] ${result.command}: ${result.family.familyName}');
    buffer.writeln(result.message);
    buffer.writeln(
      'exit_category=${result.exitCategory.categoryName} '
      'exit_code=${result.exitCode}',
    );
    if (result.blockers.isNotEmpty) {
      buffer.writeln('blockers:');
      for (final blocker in result.blockers) {
        buffer.writeln('  - $blocker');
      }
    }
    if (result.humanActionRequired) {
      buffer.writeln('human_action_required: yes');
    }
    return buffer.toString().trimRight();
  }
}
