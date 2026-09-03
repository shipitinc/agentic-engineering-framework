/// The framework CLI version string.
///
/// Kept in sync manually with `pubspec.yaml` for Phase 1. A later phase may
/// generate this from package metadata.
const String frameworkCliVersion = '0.1.0';

/// The framework revision embedded in the CLI at compile time.
///
/// This is the exact Git SHA of the framework source that this CLI was built from.
/// For distributed CLI execution (outside framework repo), this provides the
/// authoritative revision for provenance and brick integrity validation.
/// Updated during release process.
const String frameworkEmbeddedRevision = '91c0c445b74726850d8a25283c6dc11c2ced7522';
