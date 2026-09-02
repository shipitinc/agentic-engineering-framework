/// Semantic exit categories for the framework CLI.
///
/// All six categories are defined by ADR 0002
/// (`docs/engineering/adr/0002-dart-mason-git-framework-driver.md`):
///
/// | Code | Category                   | Meaning                                    |
/// |------|----------------------------|--------------------------------------------|
/// | 0    | SUCCESS                    | success / no blocking issue                |
/// | 10   | MERGE_ACTION_REQUIRED      | merge / conflict / correction required     |
/// | 20   | PREFLIGHT_POLICY_FAILURE   | preflight / policy failure (dirty tree)    |
/// | 30   | HUMAN_DECISION_REQUIRED    | human decision required                    |
/// | 40   | INTERNAL_TOOL_FAILURE      | internal / tool failure                    |
/// | 50   | NOT_IMPLEMENTED            | command recognized but not yet implemented |
///
/// [notImplemented] (code 50) was surfaced in Phase 1 as an
/// `ARCHITECTURE_DISCOVERY` and has been **human-ratified** into the ADR 0002
/// exit-code contract. Reusing SUCCESS would let stubs falsely report success,
/// and reusing any failure category would be semantically misleading; a distinct
/// non-success category keeps stubs unambiguous and machine-detectable.
enum ExitCategory {
  success('SUCCESS', 0),
  mergeActionRequired('MERGE_ACTION_REQUIRED', 10),
  preflightPolicyFailure('PREFLIGHT_POLICY_FAILURE', 20),
  humanDecisionRequired('HUMAN_DECISION_REQUIRED', 30),
  internalToolFailure('INTERNAL_TOOL_FAILURE', 40),

  /// ADR 0002 category (ratified from a Phase 1 discovery). See class doc above.
  notImplemented('NOT_IMPLEMENTED', 50);

  const ExitCategory(this.categoryName, this.exitCode);

  /// Stable, ADR-aligned category identifier used in machine output.
  final String categoryName;

  /// Deterministic process exit code for this category.
  final int exitCode;

  /// Whether this category represents a successful, non-blocking outcome.
  bool get isSuccess => this == ExitCategory.success;
}
