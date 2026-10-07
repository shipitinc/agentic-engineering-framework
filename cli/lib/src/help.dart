import 'check/check_citations.dart';
import 'commands.dart';
import 'version.dart';

/// Help text for [command], printed verbatim by `--help`.
///
/// Every command's help states what it reads, what it writes (nothing), and the
/// exit categories it can produce, so a caller never has to scrape prose or
/// guess a semantic.
String helpTextFor(String command) {
  final buffer = StringBuffer()
    ..writeln('framework $frameworkCliVersion — $command')
    ..writeln()
    ..writeln('USAGE')
    ..writeln(
      '  framework $command ${_usageSuffix(command)} [--json] [--help]',
    );
  if (command != CommandNames.checkCitations) {
    buffer
      ..writeln()
      ..writeln('All framework commands: ${CommandNames.all.join(', ')}.');
    return buffer.toString().trimRight();
  }

  buffer
    ..writeln()
    ..writeln(
      'Checks a directory of design artifacts and reports two classes of drift.',
    )
    ..writeln()
    ..writeln('OPTIONS')
    ..writeln(
      '  --dir <path>          Directory of design artifacts to check (required).',
    )
    ..writeln(
      '  --root <path>         Tree citations resolve against (default: current directory).',
    )
    ..writeln(
      '  --json                Emit deterministic machine-readable JSON.',
    )
    ..writeln('  --help                Print this help.')
    ..writeln()
    ..writeln('CITATION DRIFT (class 1) — pure, no subprocess is ever spawned')
    ..writeln(
      '  Every `path:line` and `path:start-end` citation in every Markdown file',
    )
    ..writeln(
      '  under --dir is resolved against --root (falling back to the artifact\'s own',
    )
    ..writeln('  directory and its ancestors). Reported classes:')
    ..writeln(
      '    UNRESOLVED_PATH    the cited path does not exist under the root',
    )
    ..writeln(
      '    OUTSIDE_ROOT       absolute path or ".." segment; not verifiable here',
    )
    ..writeln(
      '    LINE_BEYOND_EOF    a single cited line is past the end of the file',
    )
    ..writeln('    LINE_NOT_POSITIVE  a cited line or endpoint is below line 1')
    ..writeln('    INVERTED_RANGE     a range\'s start is after its end')
    ..writeln('    RANGE_BEYOND_EOF   a range endpoint lies outside the file')
    ..writeln(
      '  Known limitations, stated rather than hidden: a citation whose path starts',
    )
    ..writeln(
      '  with "." (e.g. ./a.md:3) is not matched, a URL is not a citation, and a',
    )
    ..writeln(
      '  literal regex such as \\.dart:3 inside a command is not a citation.',
    )
    ..writeln()
    ..writeln(
      '  One residual non-idempotency, stated rather than hidden: the echoed',
    )
    ..writeln(
      '  COMMAND `text=` is the artifact\'s own bytes, so a command whose body',
    )
    ..writeln(
      '  contains a literal `foo.md:3` would re-enter as a citation if that',
    )
    ..writeln('  report were pasted into the artifact set.')
    ..writeln()
    ..writeln(
      'COMMAND DRIFT (class 2) — extraction and reporting only, NEVER execution',
    )
    ..writeln(
      '  A fenced block is a command candidate only when its language tag is one of',
    )
    ..writeln('  bash, sh, shell, zsh. Unlabelled fences, other languages, and')
    ..writeln(
      '  shell-tagged fences carrying prompts (a terminal transcript) are counted and',
    )
    ..writeln('  reported as NOT commands, so they are never misreported.')
    ..writeln(
      '  Each extracted command is reported with its artifact, line, language,',
    )
    ..writeln('  claimed value and claimed revision. Reported drift classes:')
    ..writeln(
      '    SELF_REFERENCING_SCOPE  the command\'s scope includes the directory that',
    )
    ..writeln(
      '                             holds the command itself, so the command counts its',
    )
    ..writeln(
      '                             own reporting row. Detected structurally, never by',
    )
    ..writeln(
      '                             re-reading a count, so the verdict is stable when the',
    )
    ..writeln(
      '                             row publishing the count is edited.',
    )
    ..writeln(
      '    MISSING_SCOPE_PATH     a repository path the command names is absent.',
    )
    ..writeln()
    ..writeln(
      '  A claimed value must be explicit: "# => 37", "# -> 37", "# expected: 37"',
    )
    ..writeln(
      '  or "# claims 37", inline or on its own line in the block. A claimed',
    )
    ..writeln(
      '  revision is "sha:<hex>", "revision <hex>", "commit <hex>" or "at <hex>".',
    )
    ..writeln()
    ..writeln(
      '  A claimed REVISION is reported but never verified: checking it',
    )
    ..writeln(
      '  would require reading a Git object, and this command spawns no',
    )
    ..writeln(
      '  subprocess. Verify it yourself with git before trusting a row.',
    )
    ..writeln()
    ..writeln('IDEMPOTENCY — STABLE UNDER ITS OWN REPORTING')
    ..writeln(
      '  A count published inside the directory it counts is not idempotent:',
    )
    ..writeln(
      '  the command line is one of its own hits, so editing the row moves the',
    )
    ..writeln('  count. This command is built so that cannot happen:')
    ..writeln(
      '    SELF_REFERENCING_SCOPE is decided structurally, by comparing the',
    )
    ..writeln(
      '    scope token against the artifact directory. No count is ever read,',
    )
    ..writeln(
      '    so the verdict cannot change when the claimed value or a per-file',
    )
    ..writeln('    breakdown row is edited.')
    ..writeln(
      '    Findings are rendered so that publishing them inside the artifact set',
    )
    ..writeln(
      '    creates no new finding: a citation is reported as the separate',
    )
    ..writeln(
      '    claimed_line/claimed_end fields, never as a re-assembled `path:line`',
    )
    ..writeln('    label, so the report is not itself a citation.')
    ..writeln('    Re-running the check after pasting its own output into the')
    ..writeln('    artifact set therefore returns byte-identical findings.')
    ..writeln()
    ..writeln('THREAT MODEL — READ BEFORE TRUSTING A RESULT');
  for (final line in _wrap(kThreatModel, 72)) {
    buffer.writeln('  $line');
  }
  buffer
    ..writeln()
    ..writeln(
      '  --execute-commands is accepted and always refused with exit code 20',
    )
    ..writeln(
      "  ($kExecutionRefusalReason). It exists so that a caller which asks",
    )
    ..writeln(
      '  for execution gets an actionable blocker instead of a parse error.',
    )
    ..writeln()
    ..writeln('READ-ONLY GUARANTEE')
    ..writeln(
      '  This command writes nothing, mutates nothing, and spawns no subprocess.',
    )
    ..writeln()
    ..writeln('EXIT CODES (ADR 0002)')
    ..writeln('  0  SUCCESS                  no drift found')
    ..writeln(
      '  20 PREFLIGHT_POLICY_FAILURE drift found, bad arguments, or execution refused',
    )
    ..writeln()
    ..writeln('OUTPUT')
    ..writeln(
      '  Human and --json output are both derived from one domain result, so',
    )
    ..writeln(
      '  they cannot disagree. Findings are one line each, in this format:',
    )
    ..writeln(
      '    CITATION_DRIFT <CLASS> artifact=<path> at=<line> path=<citedPath> claimed_line=<n> claimed_end=<n|-> detail=<text>',
    )
    ..writeln(
      '    COMMAND <path>:<line> lang=<tag|-> claimed=<value|-> claimed_revision=<sha|-> drift=<n> text=<body>',
    )
    ..writeln(
      '    COMMAND_DRIFT <CLASS> artifact=<path> at=<line> scope=<token|-> detail=<text> command=<body>',
    )
    ..writeln(
      '  Every key=value pair is space-free except the last, so the line',
    )
    ..writeln('  tokenizes deterministically.');
  return buffer.toString().trimRight();
}

String _usageSuffix(String command) {
  switch (command) {
    case CommandNames.bootstrap:
    case CommandNames.upgrade:
      return '--target <revision|path>';
    case CommandNames.checkCitations:
      return '--dir <path> [--root <path>] [--execute-commands]';
    default:
      return '';
  }
}

/// Greedy word wrap to [width], so a long policy sentence stays readable in a
/// terminal without any line exceeding the declared width.
List<String> _wrap(String text, int width) {
  final lines = <String>[];
  var current = StringBuffer();
  for (final word in text.split(' ')) {
    if (current.isNotEmpty && current.length + 1 + word.length > width) {
      lines.add(current.toString());
      current = StringBuffer();
    }
    if (current.isNotEmpty) current.write(' ');
    current.write(word);
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}
