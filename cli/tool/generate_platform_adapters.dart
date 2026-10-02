// Generates the platform-specific agent, skill, and command adapters shipped in
// the Mason brick **and** the dogfooding copies at this repository's own root.
//
// The canonical, tool-neutral orchestration artifacts live under
// `framework/templates/__brick__/.agents/` (the Agent Skills standard):
// `.agents/agents/<name>.md` are subagent profiles in the canonical Devin CLI
// format, and `.agents/skills/aef-<name>/SKILL.md` are the portable skills,
// including the `aef-run-feature` human entry point. **That brick `.agents/` tree
// is the single source of truth.** Every other directory this tool writes is
// **generated output** and must never be hand-maintained — including the root
// `.agents/`, which is a generated *mirror* of the canonical tree so this
// repository can consume the skills natively. The mirror is not a second source
// of truth: an edit made to it is overwritten on the next run and reported as
// drift by `--check`. Fix the brick, never the copy.
//
// Adding a platform is a single edit: add an entry to [kPlatforms] and, if its
// schema is not one of the built-in renderers, a renderer for its schema.
// Adding a root the adapters are emitted into is likewise a single edit: add an
// entry to [kTargetRoots]. "Which platforms × which roots" is therefore two
// declarative lists and no imperative code, and the drift test asserts against
// both, so a matrix or root change cannot be made in one place and forgotten in
// the other.
//
// Usage:
//   dart run tool/generate_platform_adapters.dart          # write adapters
//   dart run tool/generate_platform_adapters.dart --check  # verify, no write
//
// Generation is deterministic: the same repository always produces byte-identical
// adapters at every root. There are no timestamps, no random ordering, and no
// environment input. `--check` regenerates in memory for **every root** and exits
// non-zero listing each mismatch — missing, differing, or unexpected — with the
// root it belongs to.

import 'dart:convert';
import 'dart:io';

const _brickRelativePath = 'framework/templates/__brick__';
const _canonicalRoot = '.agents';
const _canonicalAgentsDir = '.agents/agents';
const _canonicalSkillsDir = '.agents/skills';
const _runFeatureSkill = 'aef-run-feature';
const _runFeatureSkillPath = '.agents/skills/$_runFeatureSkill/SKILL.md';
const _commandName = 'run-feature';

/// The frontmatter schema a platform adapter is rendered in.
enum PlatformSchema {
  /// Claude Code. `tools` is a comma-separated string, not a YAML list.
  claude,

  /// opencode. Agents carry a `permission` block; there is no skill adapter
  /// because opencode discovers the canonical `.agents/skills/` natively.
  opencode,

  /// JetBrains Junie. `tools` is a YAML list, plus `allowPromptArgument` and
  /// `skills`.
  junie,
}

/// The support matrix: one declarative entry per platform.
class PlatformAdapter {
  const PlatformAdapter({
    required this.id,
    required this.dir,
    required this.schema,
    required this.generatesSkills,
    required this.commandDir,
  });

  /// Stable identifier used in reports and test assertions.
  final String id;

  /// Platform root, e.g. `.claude`, relative to each [AdapterTarget].
  final String dir;

  final PlatformSchema schema;

  /// Whether this platform needs a generated copy of the canonical skills.
  ///
  /// opencode resolves `.agents/skills/` natively, so a copy under
  /// `.opencode/skills/` would be a duplicate with no benefit.
  final bool generatesSkills;

  /// The command directory name. opencode uses the singular `command`; Claude
  /// Code and Junie use the plural `commands`.
  final String commandDir;
}

/// The support matrix. This constant is the single source of truth: the
/// generator iterates it and the drift test asserts against it.
const kPlatforms = <PlatformAdapter>[
  PlatformAdapter(
    id: 'claude',
    dir: '.claude',
    schema: PlatformSchema.claude,
    generatesSkills: true,
    commandDir: 'commands',
  ),
  PlatformAdapter(
    id: 'junie',
    dir: '.junie',
    schema: PlatformSchema.junie,
    generatesSkills: true,
    commandDir: 'commands',
  ),
  PlatformAdapter(
    id: 'opencode',
    dir: '.opencode',
    schema: PlatformSchema.opencode,
    generatesSkills: false,
    commandDir: 'command',
  ),
];

/// One root the adapters are emitted into.
class AdapterTarget {
  const AdapterTarget({
    required this.id,
    required this.path,
    required this.mirrorsCanonical,
  });

  /// Stable identifier used in reports, drift messages, and test assertions.
  final String id;

  /// The root's directory, relative to the framework repository root. `.` is
  /// the repository root itself.
  final String path;

  /// Whether the canonical `.agents/` tree is mirrored into this root.
  ///
  /// **Only** a root that is not the canonical root may mirror it. The brick is
  /// the source of truth, so mirroring there would be circular; the repository
  /// root mirrors so this repository can consume `.agents/skills/` natively
  /// (which is also how opencode discovers skills). The mirror is generated
  /// output: hand-editing it is overwritten and reported as drift.
  final bool mirrorsCanonical;

  /// The absolute path of this root for a given repository root.
  String absolutePath(String repoRoot) =>
      path == '.' ? repoRoot : '$repoRoot/$path';
}

/// The roots the generator emits into. This constant is the single source of
/// truth for *where* adapters are written, exactly as [kPlatforms] is for *what*
/// is written.
const kTargetRoots = <AdapterTarget>[
  // The Mason brick: the shipped product-repo layout. Its `.agents/` tree is the
  // canonical source of truth, so it is never mirrored into itself.
  AdapterTarget(id: 'brick', path: _brickRelativePath, mirrorsCanonical: false),
  // This framework repository's own root, so the framework consumes exactly
  // what it ships ("dogfooding"). Generated, never hand-maintained.
  AdapterTarget(id: 'root', path: '.', mirrorsCanonical: true),
];

/// The final path segment of a file or directory, without any trailing slash.
///
/// `Directory.uri` is normalised with a trailing separator, so
/// `uri.pathSegments.last` is the empty string for a directory. Dropping empty
/// segments is the dependency-free equivalent of `package:path`'s `basename`.
String _basename(FileSystemEntity entity) {
  final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
  if (segments.isEmpty) {
    throw StateError('cannot derive a name from ${entity.path}');
  }
  return segments.last;
}

/// Resolves the framework repository root (the directory holding `__brick__`).
///
/// Prefers the current working directory, so the tool behaves like
/// `tool/compute_brick_hash.dart`, and falls back to the script location.
String resolveRepoRoot() {
  var candidate = Directory.current.absolute.path;
  for (var i = 0; i < 8; i++) {
    final probe = Directory('$candidate/$_brickRelativePath');
    if (probe.existsSync()) return candidate;
    final parent = candidate.substring(
      0,
      candidate.lastIndexOf(Platform.pathSeparator),
    );
    if (parent == candidate) break;
    candidate = parent;
  }

  final scriptUri = Platform.script;
  if (scriptUri.isScheme('file')) {
    final cliDir = File.fromUri(scriptUri).parent.parent;
    final root = cliDir.parent.path;
    final probe = Directory('$root/$_brickRelativePath');
    if (probe.existsSync()) return root;
  }

  throw StateError(
    'Cannot locate the framework repository. Run this tool from the `cli/` '
    'directory of the framework repository, or from a directory inside it.',
  );
}

/// The complete canonical `allowed-tools` token → per-platform tool mapping.
///
/// `edit` is a single canonical token that expands to **two** platform tool
/// names (`Write` + `Edit`), because write and edit are distinct capabilities
/// everywhere except the canonical vocabulary.
const kToolMapping = <String, ({String opencode, List<String> others})>{
  'read': (opencode: 'read', others: ['Read']),
  'grep': (opencode: 'grep', others: ['Grep']),
  'glob': (opencode: 'glob', others: ['Glob']),
  'edit': (opencode: 'edit', others: ['Write', 'Edit']),
  'exec': (opencode: 'bash', others: ['Bash']),
};

/// The canonical token whose presence grants write access.
const _editToken = 'edit';

/// The canonical token whose presence grants shell access.
const _execToken = 'exec';

/// A parsed canonical agent profile: `.agents/agents/<name>.md`.
class CanonicalAgent {
  const CanonicalAgent({
    required this.name,
    required this.description,
    required this.allowedTools,
    required this.requiredSkills,
    required this.body,
  });

  final String name;
  final String description;
  final List<String> allowedTools;
  final List<String> requiredSkills;
  final String body;

  /// The opencode `permission` block for this profile.
  ///
  /// `edit` gates `write`/`edit`/`apply_patch` in opencode and defaults to
  /// allow, so a read-only profile must deny it explicitly. `read`, `grep`, and
  /// `glob` are always allowed; `bash` mirrors the presence of the canonical
  /// `exec` tool.
  Map<String, String> permission() => {
    'read': 'allow',
    'grep': 'allow',
    'glob': 'allow',
    'edit': allowedTools.contains(_editToken) ? 'allow' : 'deny',
    'bash': allowedTools.contains(_execToken) ? 'allow' : 'deny',
  };

  /// The platform tool names for this profile, in canonical order.
  ///
  /// Identical for Claude Code and Junie: the only difference between those two
  /// schemas is how the list is serialized (comma-separated string vs YAML
  /// list), never which tools are granted.
  List<String> toolNames() => [
    for (final token in allowedTools)
      ...kToolMapping[token]?.others ?? const <String>[],
  ];

  /// Whether this profile is read-only with respect to production artifacts.
  ///
  /// Derived from the canonical `allowed-tools` list, never from prose, so the
  /// read-only invariant is identical on every platform.
  bool get isReadOnly => !allowedTools.contains(_editToken);
}

/// A parsed canonical `SKILL.md`.
class CanonicalSkill {
  const CanonicalSkill({
    required this.name,
    required this.description,
    required this.raw,
    required this.frontmatterLines,
    required this.body,
  });

  final String name;
  final String description;

  /// The file content exactly as committed, used for verbatim copies.
  final String raw;

  /// The top-level frontmatter lines, without the fences.
  final List<String> frontmatterLines;

  final String body;

  /// The raw value of a top-level frontmatter key, or null.
  String? frontmatter(String key) {
    for (final line in frontmatterLines) {
      final separator = line.indexOf(':');
      if (separator == -1) continue;
      if (line.substring(0, separator).trim() == key) {
        return line.substring(separator + 1).trim();
      }
    }
    return null;
  }
}

/// Strips a YAML scalar down to its text value.
///
/// Double-quoted values are decoded as JSON (a strict subset of the YAML
/// double-quoted style); single-quoted values only need `''` unescaped.
String _scalar(String raw) {
  final value = raw.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return jsonDecode(value) as String;
  }
  if (value.length >= 2 && value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1).replaceAll("''", "'");
  }
  return value;
}

/// Splits a file into its frontmatter map and its body.
///
/// The canonical artifacts only use top-level `key: value` frontmatter, so a
/// line scan is sufficient and keeps the generator dependency-free.
({Map<String, String> frontmatter, String body}) _splitFrontmatter(
  String content,
) {
  if (!content.startsWith('---\n')) {
    throw const FormatException('missing opening `---` frontmatter fence');
  }
  final end = content.indexOf('\n---\n', 3);
  if (end == -1) {
    throw const FormatException('missing closing `---` frontmatter fence');
  }

  final frontmatter = <String, String>{};
  for (final line in content.substring(4, end).split('\n')) {
    if (line.isEmpty || line.startsWith(' ')) continue;
    final separator = line.indexOf(':');
    if (separator == -1) continue;
    frontmatter[line.substring(0, separator).trim()] = line.substring(
      separator + 1,
    );
  }

  return (frontmatter: frontmatter, body: content.substring(end + 5));
}

/// The top-level frontmatter lines of a canonical artifact, without the fences.
List<String> _frontmatterLines(String content) {
  if (!content.startsWith('---\n')) {
    throw const FormatException('missing opening `---` frontmatter fence');
  }
  final end = content.indexOf('\n---\n', 3);
  if (end == -1) {
    throw const FormatException('missing closing `---` frontmatter fence');
  }
  return content.substring(4, end).split('\n');
}

List<String> _stringList(String raw) {
  final value = raw.trim();
  if (value.startsWith('[') && value.endsWith(']')) {
    return (jsonDecode(value) as List<dynamic>).cast<String>();
  }
  return value
      .replaceAll('[', '')
      .replaceAll(']', '')
      .split(',')
      .map((element) => element.trim().replaceAll('"', '').replaceAll("'", ''))
      .where((element) => element.isNotEmpty)
      .toList();
}

/// Extracts the required-skill list from the canonical agent body.
///
/// The canonical body carries the binding in prose form:
/// `**Required skills: `aef-x`, `aef-y` — load them before starting.**`, so the
/// Junie `skills:` frontmatter is derived from the canonical body rather than
/// maintained by hand.
List<String> _requiredSkills(String body) {
  final match = RegExp(
    r'^\*\*Required skills: (.+?) — load them before starting\.\*\*$',
    multiLine: true,
  ).firstMatch(body);
  if (match == null) return const [];
  return RegExp(
    r'`([^`]+)`',
  ).allMatches(match.group(1)!).map((m) => m.group(1)!).toList();
}

CanonicalAgent parseAgent(String fileName, String content) {
  final parts = _splitFrontmatter(content);
  final frontmatter = parts.frontmatter;
  final rawName = frontmatter['name']?.trim();
  final description = frontmatter['description'];
  final allowedTools = frontmatter['allowed-tools'];
  if (rawName == null || description == null || allowedTools == null) {
    throw FormatException(
      'canonical agent `$fileName` must declare `name`, `description`, and '
      '`allowed-tools`',
    );
  }

  final tools = _stringList(allowedTools);
  for (final token in tools) {
    if (!kToolMapping.containsKey(token)) {
      throw FormatException(
        'canonical agent `$fileName` declares allowed-tools entry `$token`, '
        'which has no entry in kToolMapping. Add the mapping rather than '
        'guessing a platform tool name.',
      );
    }
  }

  return CanonicalAgent(
    name: _scalar(rawName),
    description: _scalar(description),
    allowedTools: tools,
    requiredSkills: _requiredSkills(parts.body),
    body: parts.body,
  );
}

/// The only `triggers` value the canonical vocabulary defines.
///
/// Claude Code's `disable-model-invocation: true` is derived from the *presence*
/// of the `triggers` key, so an unrecognised value would be mapped as if it
/// meant "human-invoked only" — a silent permission widening. Fail loudly
/// instead of mapping an unknown contract.
const _knownTriggers = <List<String>>[
  ['user'],
];

CanonicalSkill parseSkill(String fileName, String content) {
  final parts = _splitFrontmatter(content);
  final frontmatter = parts.frontmatter;
  final name = frontmatter['name']?.trim();
  final description = frontmatter['description'];
  if (name == null || description == null) {
    throw FormatException(
      'canonical skill `$fileName` must declare `name` and `description`',
    );
  }
  final triggers = frontmatter['triggers'];
  if (triggers != null) {
    final parsed = _stringList(triggers);
    final known = _knownTriggers.any(
      (value) =>
          value.length == parsed.length &&
          value.asMap().entries.every((e) => parsed[e.key] == e.value),
    );
    if (!known) {
      throw FormatException(
        'canonical skill `$fileName` declares triggers `$triggers`, which is '
        'not in the canonical vocabulary. Add the mapping explicitly rather '
        'than letting an unknown value be rendered as "human-invoked only".',
      );
    }
  }
  return CanonicalSkill(
    name: _scalar(name),
    description: _scalar(description),
    raw: content,
    frontmatterLines: _frontmatterLines(content),
    body: parts.body,
  );
}

/// Renders a YAML flow sequence, e.g. `["Read", "Grep"]`.
///
/// The spacing matches the format the Junie adapter files have always used, so
/// the generated frontmatter is indistinguishable from a hand-written one.
String _jsonList(List<String> values) =>
    '[${values.map(jsonEncode).join(', ')}]';

/// Renders the opencode adapter for a canonical agent profile.
String renderOpencodeAgent(CanonicalAgent agent) {
  final buffer = StringBuffer()
    ..writeln('---')
    // `name` is intentionally omitted: opencode derives the agent name from
    // the file name, and only the fields below are emitted so that no foreign
    // key can be silently absorbed into `options`.
    ..writeln('description: ${jsonEncode(agent.description)}')
    ..writeln('mode: subagent')
    ..writeln('permission:');
  agent.permission().forEach((key, value) {
    buffer.writeln('  $key: $value');
  });
  buffer
    ..writeln('---')
    ..write(agent.body);
  return buffer.toString();
}

/// Renders the Claude Code adapter for a canonical agent profile.
///
/// `tools` is emitted as Claude Code's documented comma-separated string, not a
/// YAML list. `model` is omitted so the subagent inherits the session model.
String renderClaudeAgent(CanonicalAgent agent) {
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('name: ${jsonEncode(agent.name)}')
    // The description is the delegation trigger, so it is copied verbatim from
    // the canonical profile.
    ..writeln('description: ${jsonEncode(agent.description)}')
    ..writeln('tools: ${agent.toolNames().join(', ')}')
    ..writeln('---')
    ..write(agent.body);
  return buffer.toString();
}

/// Renders the Junie adapter for a canonical agent profile.
///
/// `tools` is a YAML list and `skills:` carries the `aef-`-prefixed required
/// skills. `skills` is omitted entirely when the canonical body declares none,
/// which is the case for `integrator`.
String renderJunieAgent(CanonicalAgent agent) {
  final buffer = StringBuffer()
    ..writeln('---')
    ..writeln('name: ${jsonEncode(agent.name)}')
    ..writeln('description: ${jsonEncode(agent.description)}')
    ..writeln('tools: ${_jsonList(agent.toolNames())}')
    ..writeln('allowPromptArgument: true');
  if (agent.requiredSkills.isNotEmpty) {
    buffer.writeln('skills: ${_jsonList(agent.requiredSkills)}');
  }
  buffer
    ..writeln('---')
    ..write(agent.body);
  return buffer.toString();
}

/// Renders the shared body of the `run-feature` command adapters.
///
/// The body loads and executes the canonical skill; the platform difference is
/// confined to the frontmatter.
String _runFeatureBody(CanonicalSkill skill) =>
    '''

Load the `${skill.name}` skill from `$_runFeatureSkillPath` and execute it end to end
as the Engineering Manager / Orchestrator for this repository. Follow the skill exactly
as written: it defines the phase list, the routing rules, the structured `RESULT:`
tokens, and the terminal Manager report vocabulary. Do not summarise, reorder, or skip
any part of it, and do not ask the human for routine workflow transitions.
''';

/// The alias note appended to the **Claude Code** command adapter only.
///
/// Claude Code treats `commands/` and `skills/` as one feature, so the workflow is
/// reachable as both `/run-feature` and `/aef-run-feature`. Both files are generated
/// from the one canonical skill, so this is an intentional alias, not a second copy,
/// and there is no name collision or startup conflict.
const _claudeAliasNote = '''

This command and `.claude/skills/aef-run-feature/SKILL.md` are an intentional
**alias of the same workflow**, not two copies of it: Claude Code treats `commands/` and
`skills/` as one feature, so the workflow is exposed as both `/run-feature` and
`/aef-run-feature`. Both are generated from the one canonical
`.agents/skills/aef-run-feature/SKILL.md` and both resolve to the same skill body, so
there is no name collision and no startup conflict. Invoke whichever you prefer.
''';

/// Renders the opencode adapter for the human entry point.
///
/// opencode has no equivalent of a skill, so the adapter is a one-line
/// instruction to load and execute the canonical skill, forwarding the text the
/// user typed as `$ARGUMENTS`.
String renderOpencodeCommand(CanonicalSkill skill) =>
    '''
---
description: ${jsonEncode(skill.description)}
---
${_runFeatureBody(skill)}
FEATURE (verbatim from \$ARGUMENTS):

\$ARGUMENTS
''';

/// Renders the Claude Code adapter for the human entry point.
///
/// `disable-model-invocation` is the mechanical counterpart of the canonical
/// `triggers: ["user"]`: the human entry point must never be auto-invoked.
String renderClaudeCommand(CanonicalSkill skill) =>
    '''
---
description: ${jsonEncode(skill.description)}
argument-hint: ${skill.frontmatter('argument-hint') ?? '[feature description]'}
disable-model-invocation: true
---
${_runFeatureBody(skill)}$_claudeAliasNote
FEATURE (verbatim from \$ARGUMENTS):

\$ARGUMENTS
''';

/// Renders the Junie adapter for the human entry point.
///
/// Junie's documented argument mechanism is `allowPromptArgument: true` plus
/// `argument-hint`; the user's text after the command name is the prompt. There
/// is no documented `$ARGUMENTS` substitution for Junie, so none is emitted —
/// the body states that the human supplies the feature description instead.
String renderJunieCommand(CanonicalSkill skill) =>
    '''
---
name: ${jsonEncode(_commandName)}
description: ${jsonEncode(skill.description)}
argument-hint: ${skill.frontmatter('argument-hint') ?? '[feature description]'}
allowPromptArgument: true
---
${_runFeatureBody(skill)}
FEATURE (the human supplies this after the command name; the argument is not
interpolated by a template — it is the prompt the human typed):

The human's feature description is the argument of this command. Use it verbatim.
''';

/// Renders the Claude Code adapter for a canonical skill.
///
/// The copy is the canonical file **verbatim**, with exactly one mechanical
/// difference: the canonical `triggers: [...]` key is replaced by Claude Code's
/// `disable-model-invocation: true`. Skills without `triggers` are byte-identical
/// to the canonical file.
String renderClaudeSkill(CanonicalSkill skill) {
  final lines = <String>[];
  var mapped = false;
  for (final line in skill.frontmatterLines) {
    final key = line.split(':').first.trim();
    if (key == 'triggers') {
      // `triggers: ["user"]` means "the human invokes this, never the model".
      // Claude Code spells exactly that `disable-model-invocation: true`.
      lines.add('disable-model-invocation: true');
      mapped = true;
      continue;
    }
    lines.add(line);
  }
  if (!mapped) return skill.raw;
  return '---\n${lines.join('\n')}\n---\n${skill.body}';
}

/// Renders the Junie adapter for a canonical skill.
///
/// Junie has no documented counterpart to the canonical `triggers` key, so the
/// skill copy is byte-identical to the canonical file rather than carrying an
/// invented key.
String renderJunieSkill(CanonicalSkill skill) => skill.raw;

/// The canonical artifacts this tool derives every adapter from.
class CanonicalSource {
  CanonicalSource(this.agents, this.skills, this.runFeature);

  final List<CanonicalAgent> agents;
  final List<CanonicalSkill> skills;
  final CanonicalSkill runFeature;
}

/// Reads and parses every canonical artifact, in stable order.
CanonicalSource readCanonical(String repoRoot) {
  final root = '$repoRoot/$_brickRelativePath';

  final agentsDir = Directory('$root/$_canonicalAgentsDir');
  final agentFiles =
      agentsDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (agentFiles.isEmpty) {
    throw StateError('no canonical agent profiles found in $agentsDir');
  }
  final agents = [
    for (final file in agentFiles)
      parseAgent(_basename(file), file.readAsStringSync()),
  ];

  // Only the `<skill-name>/SKILL.md` files are skills; anything nested deeper
  // (e.g. `aef-orchestrator/templates/`) is a referenced template, not a skill,
  // and is copied by Mason as a canonical artifact in its own right.
  final skillsDir = Directory('$root/$_canonicalSkillsDir');
  final skillFiles =
      skillsDir
          .listSync()
          .whereType<Directory>()
          .map((dir) => File('${dir.path}/SKILL.md'))
          .where((file) => file.existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (skillFiles.isEmpty) {
    throw StateError('no canonical skills found in $skillsDir');
  }
  final skills = [
    for (final file in skillFiles)
      parseSkill(
        '$_canonicalSkillsDir/${_basename(file.parent)}/SKILL.md',
        file.readAsStringSync(),
      ),
  ];

  final runFeatureFile = File('$root/$_runFeatureSkillPath');
  if (!runFeatureFile.existsSync()) {
    throw StateError('canonical run-feature skill not found: $runFeatureFile');
  }
  final runFeature = parseSkill(
    _runFeatureSkillPath,
    runFeatureFile.readAsStringSync(),
  );

  return CanonicalSource(agents, skills, runFeature);
}

/// One generated file: path relative to its target root, plus content.
typedef GeneratedFile = ({String path, String content});

/// Lists every file of the canonical `.agents/` tree, recursively, in stable
/// order, with paths relative to a mirror root.
///
/// The whole tree is listed, not just agents and `SKILL.md` files, because a
/// canonical skill may ship referenced assets (e.g.
/// `.agents/skills/aef-orchestrator/templates/`) that must be mirrored verbatim
/// for the mirror to be a faithful copy.
List<GeneratedFile> readCanonicalMirror(String repoRoot) {
  final canonicalDir = '$repoRoot/$_brickRelativePath/$_canonicalRoot';
  final dir = Directory(canonicalDir);
  if (!dir.existsSync()) {
    throw StateError('canonical source of truth not found: $canonicalDir');
  }

  final files = dir.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('canonical $_canonicalRoot tree is empty: $canonicalDir');
  }

  return [
    for (final file in files)
      (
        path:
            '$_canonicalRoot/'
            '${file.path.replaceFirst('$canonicalDir/', '').replaceAll('\\', '/')}',
        content: file.readAsStringSync(),
      ),
  ];
}

/// Builds every adapter for one platform, in stable order.
List<GeneratedFile> _buildPlatform(
  PlatformAdapter platform,
  CanonicalSource canonical,
) {
  final files = <GeneratedFile>[];

  if (platform.generatesSkills) {
    for (final skill in canonical.skills) {
      files.add((
        path: '${platform.dir}/skills/${skill.name}/SKILL.md',
        content: switch (platform.schema) {
          PlatformSchema.claude => renderClaudeSkill(skill),
          PlatformSchema.junie => renderJunieSkill(skill),
          PlatformSchema.opencode => throw StateError(
            'platform `${platform.id}` must not generate a skills adapter: it '
            'resolves the canonical .agents/skills/ natively',
          ),
        },
      ));
    }
  }

  for (final agent in canonical.agents) {
    files.add((
      path: '${platform.dir}/agents/${agent.name}.md',
      content: switch (platform.schema) {
        PlatformSchema.claude => renderClaudeAgent(agent),
        PlatformSchema.junie => renderJunieAgent(agent),
        PlatformSchema.opencode => renderOpencodeAgent(agent),
      },
    ));
  }

  files.add((
    path: '${platform.dir}/${platform.commandDir}/$_commandName.md',
    content: switch (platform.schema) {
      PlatformSchema.claude => renderClaudeCommand(canonical.runFeature),
      PlatformSchema.junie => renderJunieCommand(canonical.runFeature),
      PlatformSchema.opencode => renderOpencodeCommand(canonical.runFeature),
    },
  ));

  return files;
}

/// Every generated file for one target root.
class TargetAdapters {
  TargetAdapters({
    required this.target,
    required this.files,
    required this.counts,
  });

  /// The root these files are written into.
  final AdapterTarget target;

  /// Generated content keyed by path **relative to the target root**.
  final Map<String, String> files;

  /// Per-directory counts keyed by directory name relative to the target root
  /// (`.claude`, `.junie`, `.opencode`, plus `.agents` when mirrored), in
  /// declaration order.
  final Map<String, int> counts;

  /// The number of generated files at this root.
  int get total => files.length;

  /// The path prefixes at this root that the generator owns, relative to it.
  ///
  /// Derived from [files] rather than declared: each generated path is grouped
  /// under its `<root>/<subdirectory>` prefix, so ownership follows generation
  /// exactly — a platform that starts emitting a new subdirectory owns it
  /// automatically, and there is no hand-maintained list to rot.
  ///
  /// Ownership is deliberately **one level below** each platform directory, so a
  /// tool that writes its own runtime files into the platform directory is not
  /// misreported as drift. opencode writes `node_modules/`, `package.json`,
  /// `package-lock.json`, and `.gitignore` into `.opencode/`; none of those are
  /// generated, so the generator owns `.opencode/agents/**` and
  /// `.opencode/command/**` and nothing else there.
  List<String> get ownedScopes {
    final scopes = <String>{};
    for (final path in files.keys) {
      final segments = path.split('/');
      if (segments.length < 2) {
        throw StateError(
          'target `${target.id}`: generated path `$path` is not inside a '
          'subdirectory of the target root, so its ownership scope is '
          'undefined',
        );
      }
      scopes.add(segments.take(2).join('/'));
    }
    return scopes.toList()..sort();
  }

  /// The number of generated files in each [ownedScopes] entry.
  Map<String, int> get scopeCounts {
    final counts = <String, int>{};
    for (final scope in ownedScopes) {
      counts[scope] = files.keys
          .where((path) => path.startsWith('$scope/'))
          .length;
    }
    return counts;
  }
}

/// Builds every adapter for one target root, in stable order.
TargetAdapters buildTarget(
  AdapterTarget target,
  String repoRoot,
  CanonicalSource canonical,
) {
  final files = <String, String>{};
  final counts = <String, int>{};

  void add(String path, String content) {
    if (files.containsKey(path)) {
      throw StateError(
        'target `${target.id}`: two sources both generate $path; the matrix is '
        'ambiguous',
      );
    }
    files[path] = content;
  }

  if (target.mirrorsCanonical) {
    final mirror = readCanonicalMirror(repoRoot);
    for (final file in mirror) {
      add(file.path, file.content);
    }
    counts[_canonicalRoot] = mirror.length;
  }

  for (final platform in kPlatforms) {
    final platformFiles = _buildPlatform(platform, canonical);
    for (final file in platformFiles) {
      add(file.path, file.content);
    }
    counts[platform.dir] = platformFiles.length;
  }

  return TargetAdapters(target: target, files: files, counts: counts);
}

/// Builds every adapter for every platform in [kPlatforms] at every root in
/// [kTargetRoots].
///
/// The two constants are the only place "which platforms × which roots" is
/// stated, and both the generator's `--check` and the drift test iterate them,
/// so a change to either cannot be made in one place and forgotten in the other.
({Map<String, TargetAdapters> byTarget, CanonicalSource canonical}) buildAll(
  String repoRoot,
) {
  final canonical = readCanonical(repoRoot);
  final byTarget = <String, TargetAdapters>{};

  for (final target in kTargetRoots) {
    if (byTarget.containsKey(target.id)) {
      throw StateError('duplicate target root id `${target.id}`');
    }
    byTarget[target.id] = buildTarget(target, repoRoot, canonical);
  }

  return (byTarget: byTarget, canonical: canonical);
}

/// Reports one target root's generated inventory.
void _reportTarget(TargetAdapters adapters) {
  stdout.writeln('${adapters.target.id}: ${adapters.total}');
  if (adapters.target.mirrorsCanonical) {
    stdout.writeln(
      '  $_canonicalRoot: ${adapters.counts[_canonicalRoot]} '
      '(mirror of $_brickRelativePath/$_canonicalRoot — '
      'GENERATED, never a source of truth)',
    );
  }
  for (final platform in kPlatforms) {
    stdout.writeln(
      '  ${platform.dir}: ${adapters.counts[platform.dir]} '
      '(schema: ${platform.schema.name}, '
      'skills: ${platform.generatesSkills ? "generated" : "native"})',
    );
  }
}

/// The remediation hint printed whenever a generated directory holds a file the
/// generator does not own.
const _unexpectedHint =
    'An unexpected file is hand-maintained content in a generator-owned '
    'directory (usually a superseded skill or agent name). Delete it; '
    'regeneration deliberately will not.';

int _run(String repoRoot, bool check) {
  final built = buildAll(repoRoot);
  final drift = <String>[];
  final unexpected = <String>[];

  for (final target in kTargetRoots) {
    final adapters = built.byTarget[target.id]!;
    final root = target.absolutePath(repoRoot);

    for (final entry in adapters.files.entries) {
      final file = File('$root/${entry.key}');
      if (!file.existsSync()) {
        drift.add('${target.id}: missing: ${entry.key}');
        continue;
      }
      if (file.readAsStringSync() != entry.value) {
        drift.add('${target.id}: differs: ${entry.key}');
      }
    }

    // A file left behind by a renamed or deleted profile is drift too. Every
    // owned scope is generator-owned, so anything unexpected in one is a
    // hand-maintained artifact that must not exist. Regeneration cannot resolve
    // it — deleting a file the generator does not own is a human action — so it
    // is reported in both modes and fails the exit code even when writing.
    //
    // The scopes are the generated `<root>/<subdir>` prefixes, so a platform
    // directory that also holds tool-authored runtime files (opencode's
    // `.opencode/node_modules/`, `package.json`, `package-lock.json`,
    // `.gitignore`) is not swept up by this check.
    for (final dir in adapters.ownedScopes) {
      final dirPath = Directory('$root/$dir');
      if (!dirPath.existsSync()) continue;
      final found =
          dirPath
              .listSync(recursive: true)
              .whereType<File>()
              .map(
                (file) =>
                    file.path.replaceFirst('$root/', '').replaceAll('\\', '/'),
              )
              .toList()
            ..sort();
      for (final relative in found) {
        if (!adapters.files.containsKey(relative)) {
          unexpected.add('${target.id}: unexpected: $relative');
        }
      }
    }
  }

  if (check) {
    if (drift.isEmpty && unexpected.isEmpty) {
      final total = built.byTarget.values.fold<int>(
        0,
        (sum, adapters) => sum + adapters.total,
      );
      stdout.writeln('PLATFORM_ADAPTERS_IN_SYNC: $total');
      stdout.writeln(
        'CANONICAL: $_brickRelativePath/$_canonicalRoot/ '
        '(source of truth — never generated)',
      );
      for (final target in kTargetRoots) {
        _reportTarget(built.byTarget[target.id]!);
      }
      return 0;
    }
    for (final entry in [...drift, ...unexpected]) {
      stderr.writeln('PLATFORM_ADAPTER_DRIFT: $entry');
    }
    if (drift.isNotEmpty) {
      stderr.writeln(
        'Regenerate with: dart run tool/generate_platform_adapters.dart',
      );
    }
    if (unexpected.isNotEmpty) stderr.writeln(_unexpectedHint);
    return 1;
  }

  for (final target in kTargetRoots) {
    final adapters = built.byTarget[target.id]!;
    final root = target.absolutePath(repoRoot);
    for (final entry in adapters.files.entries) {
      final file = File('$root/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  final total = built.byTarget.values.fold<int>(
    0,
    (sum, adapters) => sum + adapters.total,
  );
  stdout.writeln('PLATFORM_ADAPTERS_GENERATED: $total');
  for (final target in kTargetRoots) {
    _reportTarget(built.byTarget[target.id]!);
  }
  if (unexpected.isNotEmpty) {
    for (final entry in unexpected) {
      stderr.writeln('PLATFORM_ADAPTER_UNEXPECTED: $entry');
    }
    stderr.writeln(_unexpectedHint);
    return 1;
  }
  return 0;
}

void main(List<String> args) {
  final check = args.contains('--check');
  final unknown = args.where((arg) => arg != '--check');
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown argument: ${unknown.first}');
    stderr.writeln('Usage: generate_platform_adapters.dart [--check]');
    exit(64);
  }
  exit(_run(resolveRepoRoot(), check));
}
