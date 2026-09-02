/// Phase 1 public API for the agentic engineering framework CLI.
///
/// Exposes the domain result model, centralized exit-category mapping,
/// output rendering, and the command runner. See ADR 0002 for the exit-code
/// contract this package implements.
library;

export 'src/command_result.dart';
export 'src/commands.dart';
export 'src/exit_category.dart';
export 'src/output_renderer.dart';
export 'src/result_family.dart';
export 'src/runner.dart';
export 'src/version.dart';
