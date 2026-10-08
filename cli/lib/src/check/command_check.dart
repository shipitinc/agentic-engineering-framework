import '../manifest/path_safety.dart';
import 'citation.dart';
import 'markdown.dart';

/// Fence info strings whose blocks are asserted to be runnable shell commands.
///
/// A block is only ever treated as a command when the artifact explicitly says
/// so. Everything else — unlabelled fences, `text`, `console`, prose, code in
/// other languages — is classified and reported as *not* a command, so a
/// shell-session transcript can never be misreported as an executable check.
const Set<String> kCommandLanguages = <String>{'bash', 'sh', 'shell', 'zsh'};

/// How a fenced block relates to command execution.
enum BlockClassification {
  /// A fence tagged as a runnable shell command.
  command('COMMAND'),

  /// A fence tagged with a language that is not a shell command language.
  nonCommand('NON_COMMAND'),

  /// A fence with no language tag: not asserted to be a command.
  unlabelled('UNLABELLED'),

  /// A shell-tagged fence whose body carries shell prompts, i.e. a captured
  /// terminal session rather than a script to run.
  transcript('TRANSCRIPT');

  const BlockClassification(this.wireName);

  /// Stable identifier emitted in machine-readable output.
  final String wireName;
}

/// Classes of command drift reported without ever executing anything.
enum CommandDriftClass {
  /// The command's scope includes the directory holding the artifact that
  /// contains it, so the command counts its own reporting row. Such a command
  /// is not idempotent under editing that row.
  selfReferencingScope('SELF_REFERENCING_SCOPE'),

  /// The command names a repository path that does not exist in the scanned
  /// working tree.
  missingScopePath('MISSING_SCOPE_PATH');

  const CommandDriftClass(this.wireName);

  /// Stable identifier emitted in machine-readable output.
  final String wireName;
}

/// One extracted (never executed) shell command from a fenced block.
class ExtractedCommand {
  const ExtractedCommand({
    required this.artifactPath,
    required this.classification,
    required this.block,
    required this.claimedValue,
    required this.claimedRevision,
    required this.drift,
  });

  /// POSIX path of the artifact, relative to the scan root.
  final String artifactPath;

  /// How the block relates to command execution.
  final BlockClassification classification;

  /// The fenced block the command was extracted from.
  final FencedBlock block;

  /// The value the artifact claims, when it states one explicitly; else null.
  final String? claimedValue;

  /// The revision/SHA the artifact claims, when it states one; else null.
  final String? claimedRevision;

  /// Drift found for this command; empty when clean.
  final List<CommandDrift> drift;

  /// The command text, whitespace-normalized onto one line.
  String get text => block.flatText;

  /// Deterministic, machine-parseable single-line rendering.
  ///
  /// Format:
  /// `COMMAND <artifactPath>:<line> lang=<tag|-> claimed=<value|-> claimed_revision=<sha|-> drift=<n> text=<one-line body>`
  String toWireLine() {
    return 'COMMAND $artifactPath:${block.reportLine} '
        'lang=${block.language.isEmpty ? '-' : block.language} '
        'claimed=${claimedValue ?? '-'} '
        'claimed_revision=${claimedRevision ?? '-'} '
        'drift=${drift.length} '
        'text=$text';
  }
}

/// A single finding about one extracted command.
class CommandDrift {
  const CommandDrift({
    required this.driftClass,
    required this.artifactPath,
    required this.line,
    required this.scope,
    required this.detail,
  });

  /// The class of drift detected.
  final CommandDriftClass driftClass;

  /// POSIX path of the artifact, relative to the scan root.
  final String artifactPath;

  /// 1-based line in the artifact the command starts on.
  final int line;

  /// The scope token the finding is about, or `-` when not applicable.
  final String scope;

  /// A human-readable explanation, free of spaces.
  final String detail;

  /// Deterministic, machine-parseable single-line rendering.
  ///
  /// Format:
  /// `COMMAND_DRIFT <CLASS> artifact=<relPath> at=<line> scope=<token|-> detail=<text> command=<one-line body>`
  ///
  /// The `command=` pair is last and may contain spaces; every earlier pair is
  /// space-free so the line tokenizes up to it.
  String toWireLine(String commandText) {
    return 'COMMAND_DRIFT ${driftClass.wireName} '
        'artifact=$artifactPath at=$line scope=$scope '
        'detail=$detail command=$commandText';
  }
}

/// A fenced block with its classification and any extracted claim.
class BlockExtraction {
  const BlockExtraction({
    required this.artifactPath,
    required this.classification,
    required this.block,
    required this.claimedValue,
    required this.claimedRevision,
  });

  /// POSIX path of the artifact, relative to the scan root.
  final String artifactPath;

  /// How the block relates to command execution.
  final BlockClassification classification;

  /// The block itself.
  final FencedBlock block;

  /// The explicitly claimed value, or null.
  final String? claimedValue;

  /// The explicitly claimed revision, or null.
  final String? claimedRevision;

  /// Whether this extraction is a runnable command candidate.
  bool get isCommand => classification == BlockClassification.command;
}

/// Explicit claim syntax, inline after a command line.
///
/// `# => 37`, `# -> 37`, `# expected: 37`, `# claims 37`. Requiring an explicit
/// marker keeps ordinary shell comments (`# 37 files were deleted`) from being
/// read as claims.
final RegExp _inlineClaim = RegExp(
  r'#\s*(?:=>|->|expected\s*[:=]?|claims?)\s*(-?\d+(?:\.\d+)?)\s*$',
  caseSensitive: false,
);

/// A whole body line that states the claimed value.
final RegExp _standaloneClaim = RegExp(
  r'^\s*#\s*(?:=>|->|expected\s*[:=]?|claims?)\s*(-?\d+(?:\.\d+)?)\s*$',
  caseSensitive: false,
);

/// Explicit revision claim, e.g. `sha:abc1234`, `revision abc1234`, `at 0123456`.
final RegExp _revisionClaim = RegExp(
  r'\b(?:sha|revision|commit|at)\s*[:=]?\s*`?([0-9a-f]{7,40})\b',
  caseSensitive: false,
);

/// A shell prompt line, i.e. evidence the block is a terminal transcript.
///
/// `$ cmd`, `> cmd`, `% cmd`, `user@host:~$ cmd`. A bare `#` is deliberately
/// **not** a prompt here, because `# comment` is ordinary shell syntax.
final RegExp _promptLine = RegExp(
  r'^\s*(?:[\w.\-]+@[\w.\-]+(?::[^\s]*)?[#$%]\s*|[$%>]\s)',
);

/// Characters that disqualify a whitespace token from being a path.
///
/// The quote characters are written as `\x22`/`\x27` rather than literally so
/// this raw single-quoted literal can contain both kinds of shell quote.
final RegExp _nonPathCharacters = RegExp(
  r'[\\:*?\x22<>|;&()\[\]{}$`\x27!#^=+,\t]',
);

/// A `name.ext` token whose extension starts with a letter — i.e. a path, not a
/// version (`python3.11`, `1.5`).
final RegExp _dottedName = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z][A-Za-z0-9]*$');

/// A whitespace-delimited token of a shell command line.
///
/// Stops at every character that can start a different shell construct (`:`
/// for URLs and `key:value`, `=` for `key=value`, `*`/`?`/`[` for globs), so a
/// quoted `grep` pattern is never harvested as a path.
final RegExp _shellToken = RegExp(
  r'[\x22\x27`]?([A-Za-z0-9_~][A-Za-z0-9_./~+-]*)',
);

/// Classifies [block] and extracts its explicit claim, if any.
///
/// Pure: no filesystem access, no subprocess.
BlockExtraction classifyBlock(String artifactPath, FencedBlock block) {
  final BlockClassification classification;
  if (!kCommandLanguages.contains(block.language)) {
    classification = block.language.isEmpty
        ? BlockClassification.unlabelled
        : BlockClassification.nonCommand;
  } else if (block.body.any((line) => _promptLine.hasMatch(line))) {
    classification = BlockClassification.transcript;
  } else {
    classification = BlockClassification.command;
  }

  return BlockExtraction(
    artifactPath: artifactPath,
    classification: classification,
    block: block,
    claimedValue: _claimedValue(block),
    claimedRevision: _claimedRevision(block),
  );
}

String? _claimedValue(FencedBlock block) {
  for (final line in block.body) {
    final inline = _inlineClaim.firstMatch(line);
    if (inline != null) return inline.group(1);
  }
  for (final line in block.body) {
    final standalone = _standaloneClaim.firstMatch(line);
    if (standalone != null) return standalone.group(1);
  }
  return null;
}

String? _claimedRevision(FencedBlock block) =>
    _revisionClaim.firstMatch(block.flatText)?.group(1);

/// The scope path tokens a command line operates on.
///
/// A token qualifies only when it is unambiguously a path: `.` / `./`, or a
/// `/`-containing token free of shell metacharacters, or a `name.ext` token
/// whose extension is not numeric. Flags, quoted regexes, URLs (`:`), `key=value`
/// arguments, and command names are all rejected, which is what keeps a quoted
/// `grep` pattern from being mistaken for a path.
List<String> scopeTokens(String line) {
  final tokens = <String>[];
  for (final match in _shellToken.allMatches(line)) {
    final token = _trimToken(match.group(1)!);
    if (_isPathCandidate(token)) tokens.add(token);
  }
  return tokens;
}

String _trimToken(String raw) {
  var token = raw;
  while (token.isNotEmpty &&
      (token.endsWith(':') || token.endsWith(',') || token.endsWith(';'))) {
    token = token.substring(0, token.length - 1);
  }
  return token;
}

bool _isPathCandidate(String token) {
  if (token == '.' || token == './') return true;
  if (token.length < 2) return false;
  if (token.startsWith('-')) return false;
  if (_nonPathCharacters.hasMatch(token)) return false;
  if (token.contains('/')) return true;
  return _dottedName.hasMatch(token);
}

/// Normalizes a scope token to a root-relative POSIX path, or null when it is
/// the current directory or escapes the root.
///
/// Reuses [normalizeManagedPath] so command checking applies exactly the same
/// path-safety policy as citation checking (ADR 0002 mitigation 16).
String? normalizeScopeToken(String token) {
  var unified = token.replaceAll('\\', '/');
  while (unified.length > 1 && unified.endsWith('/')) {
    unified = unified.substring(0, unified.length - 1);
  }
  if (unified == '.' || unified.isEmpty) return '.';
  try {
    return normalizeManagedPath(unified);
  } on PathSafetyException {
    return null;
  }
}

/// Whether [token] names the directory holding the artifact, or an ancestor of
/// it, so the command's counting scope includes its own reporting row.
///
/// Purely structural: it reads no output and no count, which is what makes the
/// verdict stable when the row that publishes the count is edited.
bool selfReferences(String token, String artifactDirRelative) {
  final normalized = normalizeScopeToken(token);
  if (normalized == null) return false;
  if (normalized == '.') return true;
  if (artifactDirRelative == '.') return false;
  if (normalized == artifactDirRelative) return true;
  return artifactDirRelative.startsWith('$normalized/');
}

/// Whether [token] looks like a repository path worth existence-checking.
///
/// Only tokens whose first segment is a real directory under the scan root
/// qualify. This keeps unrelated dotted names and relative names out of the
/// report while still catching `cli/lib/removed.dart` and `docs/gone/`.
bool isRepositoryPath(String token, CitationResolver resolver) {
  final normalized = normalizeScopeToken(token);
  if (normalized == null || normalized == '.') return false;
  if (!normalized.contains('/')) return false;
  final firstSegment = normalized.split('/').first;
  return resolver.pathExists(firstSegment);
}

/// Extracts every fenced block of [content] as a classified extraction.
///
/// Pure: no filesystem access, no subprocess.
List<BlockExtraction> extractBlocks(String artifactPath, String content) =>
    fencedBlocks(
      content.split('\n'),
    ).map((block) => classifyBlock(artifactPath, block)).toList();
