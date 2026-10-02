import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../tool/generate_platform_adapters.dart' as gen;

/// Drift test for the generated platform adapters.
///
/// Two kinds of generated tree are asserted here, and both are **generated
/// output** that must never be hand-edited:
///
/// - `framework/templates/__brick__/.claude/`, `.../.junie/`, `.../.opencode/` —
///   the adapters shipped in the Mason brick;
/// - the framework repository's own root `.agents/`, `.claude/`, `.junie/`,
///   `.opencode/` — the dogfooding copies that let this repository consume what
///   it ships.
///
/// Both are rendered from the **one** canonical, tool-neutral tree,
/// `framework/templates/__brick__/.agents/`, by
/// `cli/tool/generate_platform_adapters.dart`. The root `.agents/` is a
/// *generated mirror* of that tree, not a second source of truth: fix the brick.
/// This test runs the generator in `--check` mode and fails when any committed
/// adapter at **any** root is missing, differs from the canonical source, or is
/// unexpected.
///
/// The platform matrix and the target roots are imported from the generator
/// itself (`kPlatforms`, `kTargetRoots`), so a platform or a root cannot be
/// added to the generator and forgotten here, nor added here without a generator
/// entry. The documented per-directory counts are still asserted separately, so
/// the expectations cannot silently follow a shrinking canonical tree.
void main() {
  group('platform adapters are in sync with the canonical artifacts', () {
    late String repoRoot;
    late String cliDir;

    /// Target root id → absolute path. Declared by the generator, not here.
    late Map<String, String> roots;

    /// The canonical source of truth lives in the brick at this relative path.
    const canonicalRelative = 'framework/templates/__brick__/.agents';
    const canonicalAgents = '.agents/agents';
    const canonicalSkills = '.agents/skills';

    /// The platform directory names, as declared by `kPlatforms`.
    List<String> platformDirs() =>
        gen.kPlatforms.map((platform) => platform.dir).toList();

    /// Every root id, as declared by `kTargetRoots`.
    List<String> rootIds() =>
        gen.kTargetRoots.map((target) => target.id).toList();

    setUpAll(() async {
      repoRoot = await _resolveRepoRoot();
      cliDir = '$repoRoot/cli';
      roots = {
        for (final target in gen.kTargetRoots)
          target.id: target.absolutePath(repoRoot),
      };
    });

    test(
      'generator --check reports no drift at any root',
      () {
        final result = Process.runSync('dart', [
          'run',
          'tool/generate_platform_adapters.dart',
          '--check',
        ], workingDirectory: cliDir);
        expect(
          result.exitCode,
          0,
          reason:
              'Generated adapters drifted from the canonical artifacts. '
              'Regenerate with: dart run tool/generate_platform_adapters.dart\n'
              'stdout=${result.stdout}\nstderr=${result.stderr}',
        );
        expect(result.stdout.toString(), contains('PLATFORM_ADAPTERS_IN_SYNC'));
      },
      timeout: Timeout(Duration(minutes: 3)),
    );

    test('the matrix and the roots are the ones the generator and docs describe', () {
      // 10 canonical agent profiles and 12 canonical skills. `.opencode` gets no
      // skill adapter: it resolves `.agents/skills/` natively, so a copy under
      // `.opencode/skills/` would be a duplicate with no benefit.
      const agents = [
        'correction-implementer',
        'deployment-authority',
        'design-agent',
        'design-reviewer',
        'engineering-reviewer',
        'focused-reviewer',
        'implementer',
        'integrator',
        'qa-architect',
        'qa-executor',
      ];
      const skills = [
        'aef-correction-loop',
        'aef-deployment-execution',
        'aef-design-review',
        'aef-design-workflow',
        'aef-human-decision',
        'aef-implementation-workflow',
        'aef-independent-review',
        'aef-orchestrator',
        'aef-qa-contract',
        'aef-qa-execution',
        'aef-repository-learning',
        'aef-run-feature',
      ];

      // The canonical inventory itself, so the documented numbers below cannot
      // silently follow a shrinking canonical tree.
      final canonical = Directory('$repoRoot/$canonicalRelative');
      expect(canonical.existsSync(), isTrue, reason: canonicalRelative);
      final agentProfiles =
          Directory('${canonical.path}/agents')
              .listSync()
              .whereType<File>()
              .map((f) => f.uri.pathSegments.last)
              .toList()
            ..sort();
      expect(agentProfiles, equals([for (final a in agents) '$a.md']));

      final skillDirs =
          Directory('${canonical.path}/skills')
              .listSync()
              .whereType<Directory>()
              .map((d) {
                final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
                return File('${d.path}/SKILL.md').existsSync() ? name : null;
              })
              .whereType<String>()
              .toList()
            ..sort();
      expect(skillDirs, equals(skills));

      // 12 skills + the 2 `aef-orchestrator` dispatch templates.
      expect(_filesUnder(canonical), 24);

      // Both roots are generated: the brick, and this repository's own root.
      expect(rootIds(), equals(['brick', 'root']));

      for (final id in rootIds()) {
        final root = roots[id]!;
        for (final dir in platformDirs()) {
          expect(
            Directory('$root/$dir').existsSync(),
            isTrue,
            reason: '$id: missing platform directory: $dir',
          );
          // `.opencode/skills/` must NOT exist: opencode reads `.agents/skills/`.
          // Every other platform's skills directory must.
          final generatesSkills = gen.kPlatforms
              .firstWhere((p) => p.dir == dir)
              .generatesSkills;
          expect(
            Directory('$root/$dir/skills').existsSync(),
            generatesSkills,
            reason: generatesSkills
                ? '$id/$dir must generate a skills adapter'
                : '$id/$dir/skills/ must not exist — opencode discovers '
                      '.agents/skills/ natively, so a copy would be a duplicate',
          );
        }

        for (final dir in platformDirs()) {
          for (final agent in agents) {
            final file = File('$root/$dir/agents/$agent.md');
            expect(
              file.existsSync(),
              isTrue,
              reason: '$id: missing $dir agent adapter: $agent',
            );
          }
        }

        for (final dir in platformDirs().where((d) => d != '.opencode')) {
          for (final skill in skills) {
            final file = File('$root/$dir/skills/$skill/SKILL.md');
            expect(
              file.existsSync(),
              isTrue,
              reason: '$id: missing $dir skill adapter: $skill',
            );
          }
        }

        // Command adapters: opencode uses the singular `command`, the other two
        // use the plural `commands`. The directory name is declared by the
        // matrix, so a rename there is asserted, not duplicated here.
        for (final platform in gen.kPlatforms) {
          final file = File(
            '$root/${platform.dir}/${platform.commandDir}/run-feature.md',
          );
          expect(
            file.existsSync(),
            isTrue,
            reason: '$id: missing ${file.path}',
          );
        }
      }

      // Only the brick holds the source of truth; the root holds a generated
      // mirror of it.
      expect(
        Directory('${roots['root']}/.agents').existsSync(),
        isTrue,
        reason: 'root .agents/ mirror is missing',
      );
      expect(
        Directory(
          '${roots['brick']}/.agents/skills/aef-orchestrator/templates',
        ).existsSync(),
        isTrue,
      );
    });

    test('every adapter the matrix implies exists at every root', () {
      // The count assertion is driven off the *same* `kPlatforms` × `kTargetRoots`
      // declarations the generator uses, so an adapter that the matrix implies
      // but that is absent on disk fails loudly instead of passing silently.
      final built = gen.buildAll(repoRoot);
      expect(built.byTarget.keys.toList(), rootIds());

      for (final target in gen.kTargetRoots) {
        final adapters = built.byTarget[target.id]!;
        final root = target.absolutePath(repoRoot);

        // A generated scope must contain exactly the generated files and
        // nothing else. The scopes are the generated `<root>/<subdir>`
        // prefixes, so a tool-authored runtime file next to them (opencode's
        // `.opencode/node_modules/`, `package.json`, `package-lock.json`,
        // `.gitignore`) is excluded — but `.opencode/agents/**` and
        // `.opencode/command/**` are still verified against the disk here, so
        // the 11-adapter opencode guarantee survives.
        for (final scope in adapters.ownedScopes) {
          final onDisk = _filesUnder(Directory('$root/$scope'));
          expect(
            onDisk,
            adapters.scopeCounts[scope],
            reason: '$target.id/$scope: unexpected file count',
          );
          expect(
            onDisk,
            adapters.files.keys.where((p) => p.startsWith('$scope/')).length,
            reason:
                '$target.id/$scope: disk contents disagree with the generator',
          );
        }

        // The opencode directory is *partly* tool-owned, so its disk guarantee
        // is asserted explicitly: exactly 10 agents + 1 command, and no other
        // generated file anywhere under `.opencode/`.
        expect(
          _filesUnder(Directory('$root/.opencode/agents')),
          10,
          reason: '$target.id: .opencode/agents must hold exactly 10 adapters',
        );
        expect(
          _filesUnder(Directory('$root/.opencode/command')),
          1,
          reason: '$target.id: .opencode/command must hold exactly 1 adapter',
        );
        expect(
          adapters.files.keys.where((p) => p.startsWith('.opencode/')).length,
          11,
          reason: '$target.id: expected 11 generated opencode adapters',
        );
      }

      // The per-root numbers the docs quote, so they cannot drift silently.
      final expected = {'brick': 57, 'root': 81};
      for (final entry in expected.entries) {
        expect(
          built.byTarget[entry.key]!.total,
          entry.value,
          reason: entry.key,
        );
      }
      // root = 57 platform adapters + the 24-file canonical mirror.
      expect(built.byTarget['root']!.counts['.agents'], 24);
      expect(built.byTarget['brick']!.counts.containsKey('.agents'), isFalse);

      // The documented per-directory numbers, quoted per root so a change in
      // one root's inventory cannot be absorbed by the other.
      const documented = {'.claude': 23, '.junie': 23, '.opencode': 11};
      for (final entry in documented.entries) {
        for (final id in rootIds()) {
          expect(
            built.byTarget[id]!.counts[entry.key],
            entry.value,
            reason: '$id/${entry.key}',
          );
        }
      }

      final result = Process.runSync('dart', [
        'run',
        'tool/generate_platform_adapters.dart',
        '--check',
      ], workingDirectory: cliDir);
      final out = result.stdout.toString();
      expect(result.exitCode, 0, reason: out + result.stderr.toString());
      expect(out, contains('PLATFORM_ADAPTERS_IN_SYNC: 138'), reason: out);
      expect(out, contains('brick: 57'), reason: out);
      expect(out, contains('root: 81'), reason: out);
      expect(out, contains('  .agents: 24'), reason: out);
      expect(out, contains('  .claude: 23'), reason: out);
      expect(out, contains('  .junie: 23'), reason: out);
      expect(out, contains('  .opencode: 11'), reason: out);
    });

    test(
      'the root .agents mirror is byte-identical to the canonical brick tree',
      () {
        // The root `.agents/` is generated output. If it were a second source of
        // truth, a hand edit there would silently diverge from what is shipped.
        final canonical = Directory('$repoRoot/$canonicalRelative');
        final mirror = Directory('${roots['root']}/.agents');

        final canonicalFiles = _relativeFiles(canonical, canonical.path);
        final mirrorFiles = _relativeFiles(mirror, mirror.path);
        expect(mirrorFiles, canonicalFiles, reason: 'mirror file set differs');

        for (final relative in canonicalFiles) {
          expect(
            File('${mirror.path}/$relative').readAsBytesSync(),
            File('${canonical.path}/$relative').readAsBytesSync(),
            reason: 'root .agents/$relative is not byte-identical to canonical',
          );
        }
      },
    );

    test(
      'every canonical agent has exactly one adapter per platform at every root',
      () {
        for (final id in rootIds()) {
          final root = roots[id]!;
          final canonical = Directory('$root/$canonicalAgents');
          expect(
            canonical.existsSync(),
            isTrue,
            reason: '$id: $canonicalAgents',
          );

          final canonicalNames =
              canonical
                  .listSync()
                  .whereType<File>()
                  .map((file) => file.uri.pathSegments.last)
                  .toList()
                ..sort();
          expect(canonicalNames, hasLength(10), reason: id);

          for (final dir in platformDirs()) {
            final generated = Directory('$root/$dir/agents');
            final generatedNames =
                generated
                    .listSync()
                    .whereType<File>()
                    .map((file) => file.uri.pathSegments.last)
                    .toList()
                  ..sort();
            expect(generatedNames, canonicalNames, reason: '$id/$dir');
          }
        }
      },
    );

    test(
      'read-only agents deny the native edit path on every platform at every root',
      () {
        // Scope of this assertion, stated precisely: the **native edit path** is
        // denied everywhere. opencode allows editing by default, so a read-only
        // profile must carry an explicit `edit: deny` or the invariant would be
        // silently broken; Claude and Junie simply omit the write tools.
        //
        // It does **not** assert filesystem-level read-only-ness: a read-only
        // profile still holds `exec` (`bash: allow` / `Bash`), so the shell
        // reaches the filesystem on every platform and `exec` is not sandboxed.
        // The governing invariant is behavioural (`AGENTS.md`: independent
        // reviewers never modify production code) plus this native-path denial;
        // a deny-by-default, argv-only `read_only_exec` allowlist runner for the
        // project's declared required gates is a tracked follow-up (ADR 0003),
        // not something these adapters assert today.
        const readOnly = [
          'design-reviewer.md',
          'engineering-reviewer.md',
          'focused-reviewer.md',
          'integrator.md',
        ];

        for (final id in rootIds()) {
          final root = roots[id]!;
          for (final name in readOnly) {
            final opencode = File('$root/.opencode/agents/$name');
            expect(opencode.existsSync(), isTrue, reason: '$id: missing $name');
            final text = opencode.readAsStringSync();
            expect(text, contains('mode: subagent'), reason: '$id/$name');
            expect(text, contains('  edit: deny'), reason: '$id/$name');
            expect(text, isNot(contains('  edit: allow')), reason: '$id/$name');

            for (final dir in ['.claude', '.junie']) {
              final file = File('$root/$dir/agents/$name');
              expect(
                file.existsSync(),
                isTrue,
                reason: '$id: missing $dir/$name',
              );
              final tools = _grantedTools(file.readAsStringSync());
              expect(
                tools,
                isNot(contains('Write')),
                reason: '$id/$dir/$name must not be granted Write',
              );
              expect(
                tools,
                isNot(contains('Edit')),
                reason: '$id/$dir/$name must not be granted Edit',
              );
            }
          }
        }
      },
    );

    test(
      'write-capable agents are granted write on every platform at every root',
      () {
        // The complement of the read-only check: a writer must not silently lose
        // its write tools on one platform only.
        const writers = [
          'correction-implementer.md',
          'deployment-authority.md',
          'design-agent.md',
          'implementer.md',
          'qa-architect.md',
          'qa-executor.md',
        ];

        for (final id in rootIds()) {
          final root = roots[id]!;
          for (final name in writers) {
            final opencode = File('$root/.opencode/agents/$name');
            expect(
              opencode.readAsStringSync(),
              contains('  edit: allow'),
              reason: '$id/$name',
            );
            for (final dir in ['.claude', '.junie']) {
              final tools = _grantedTools(
                File('$root/$dir/agents/$name').readAsStringSync(),
              );
              expect(tools, contains('Write'), reason: '$id/$dir/$name');
              expect(tools, contains('Edit'), reason: '$id/$dir/$name');
            }
          }
        }
      },
    );

    test('the same tool set is granted on every platform at every root', () {
      // The governance invariant: an agent is read-only or it is not, and that
      // must not depend on which platform — or which root — is running it. A
      // mismatch here is a governance bug, not a formatting difference.
      const expected = {
        'correction-implementer': {
          'Read',
          'Grep',
          'Glob',
          'Write',
          'Edit',
          'Bash',
        },
        'deployment-authority': {
          'Read',
          'Grep',
          'Glob',
          'Write',
          'Edit',
          'Bash',
        },
        'design-agent': {'Read', 'Grep', 'Glob', 'Write', 'Edit', 'Bash'},
        'design-reviewer': {'Read', 'Grep', 'Glob', 'Bash'},
        'engineering-reviewer': {'Read', 'Grep', 'Glob', 'Bash'},
        'focused-reviewer': {'Read', 'Grep', 'Glob', 'Bash'},
        'implementer': {'Read', 'Grep', 'Glob', 'Write', 'Edit', 'Bash'},
        'integrator': {'Read', 'Grep', 'Glob', 'Bash'},
        'qa-architect': {'Read', 'Grep', 'Glob', 'Write', 'Edit', 'Bash'},
        'qa-executor': {'Read', 'Grep', 'Glob', 'Write', 'Edit', 'Bash'},
      };

      for (final id in rootIds()) {
        final root = roots[id]!;
        for (final entry in expected.entries) {
          final canonical = File(
            '$root/$canonicalAgents/${entry.key}.md',
          ).readAsStringSync();
          expect(
            _grantedTools(canonical),
            containsAll(entry.value),
            reason: '$id canonical ${entry.key}',
          );

          for (final dir in ['.claude', '.junie']) {
            expect(
              _grantedTools(
                File('$root/$dir/agents/${entry.key}.md').readAsStringSync(),
              ),
              entry.value,
              reason:
                  '$id/$dir/${entry.key}: the granted tool set must match '
                  'canonical',
            );
          }
        }
      }
    });

    test('Junie skills bindings match the expected per-agent table', () {
      // The generator derives the Junie `skills:` binding by scraping the
      // canonical body's `**Required skills: ...**` prose sentence
      // (`_requiredSkills`) and silently omitting the key when it does not
      // match. Rewording that one sentence would therefore drop `skills:` from
      // the Junie adapters while `--check` and this drift test both stayed
      // green — the generator and the checker agreeing with each other.
      //
      // This table is an **independent** copy of the expected binding, keyed by
      // canonical agent profile name. It deliberately does not import the
      // generator's parsing, so a generator bug cannot agree with itself.
      const expectedSkills = <String, List<String>>{
        'correction-implementer': [
          'aef-correction-loop',
          'aef-implementation-workflow',
          'aef-repository-learning',
        ],
        'deployment-authority': [
          'aef-deployment-execution',
          'aef-repository-learning',
        ],
        'design-agent': ['aef-design-workflow', 'aef-repository-learning'],
        'design-reviewer': ['aef-design-review'],
        'engineering-reviewer': ['aef-independent-review'],
        'focused-reviewer': ['aef-independent-review', 'aef-correction-loop'],
        'implementer': [
          'aef-implementation-workflow',
          'aef-repository-learning',
        ],
        'integrator': [],
        'qa-architect': ['aef-qa-contract', 'aef-repository-learning'],
        'qa-executor': ['aef-qa-execution', 'aef-repository-learning'],
      };

      // Exactly one agent declares no required skills.
      final withoutSkills = expectedSkills.entries
          .where((entry) => entry.value.isEmpty)
          .map((entry) => entry.key)
          .toList();
      expect(
        withoutSkills,
        equals(['integrator']),
        reason: 'only `integrator` is expected to declare no required skills',
      );

      for (final id in rootIds()) {
        final root = roots[id]!;
        for (final entry in expectedSkills.entries) {
          final agent = entry.key;
          final file = File('$root/.junie/agents/$agent.md');
          expect(file.existsSync(), isTrue, reason: '$id: missing $agent');

          final actual = _frontmatterValue(file.readAsStringSync(), 'skills');
          if (entry.value.isEmpty) {
            expect(
              actual,
              isNull,
              reason:
                  '$id/.junie/agents/$agent.md must omit `skills:` entirely — '
                  'an empty binding is not the same as none',
            );
            continue;
          }
          expect(
            actual,
            equals(entry.value),
            reason: '$id/.junie/agents/$agent.md skills binding',
          );
        }
      }
    });

    test('adapters emit no foreign frontmatter keys at any root', () {
      // Any unrecognised key is silently routed into opencode's `options`, so a
      // leftover Junie or Claude key would be absorbed without any error — and
      // opencode then falls back to allow-everything. Only the keys each
      // adapter format defines may appear above the closing fence.
      const allowedByDir = {
        '.opencode/agents': {'description', 'mode', 'permission'},
        '.claude/agents': {'name', 'description', 'tools'},
        '.junie/agents': {
          'name',
          'description',
          'tools',
          'allowPromptArgument',
          'skills',
        },
      };
      const allowedCommands = {
        '.opencode/command': {'description'},
        '.claude/commands': {
          'description',
          'argument-hint',
          'disable-model-invocation',
        },
        '.junie/commands': {
          'name',
          'description',
          'argument-hint',
          'allowPromptArgument',
        },
      };

      for (final id in rootIds()) {
        final root = roots[id]!;
        for (final entry in {...allowedByDir, ...allowedCommands}.entries) {
          final dir = Directory('$root/${entry.key}');
          expect(dir.existsSync(), isTrue, reason: '$id/${entry.key}');
          for (final file in dir.listSync().whereType<File>()) {
            final lines = file.readAsLinesSync();
            final end = lines.indexOf('---', 1);
            expect(end, greaterThan(0), reason: file.path);
            for (final line in lines.sublist(1, end)) {
              if (line.trim().isEmpty || line.startsWith('  ')) continue;
              final key = line.split(':').first;
              expect(
                entry.value,
                contains(key),
                reason:
                    '$id: unexpected frontmatter key `$key` in '
                    '${file.path}',
              );
            }
          }
        }
      }
    });

    test('skill adapters differ from canonical only in the mapped field', () {
      // Claude Code: canonical `triggers: ["user"]` becomes exactly
      // `disable-model-invocation: true`, and nothing else changes. Junie has no
      // counterpart, so its copy is byte-identical to the canonical file. At
      // the root, "canonical" is the generated `.agents/` mirror, which the
      // mirror-identity test proves equals the brick's source of truth.
      for (final id in rootIds()) {
        final root = roots[id]!;
        final canonical = Directory('$root/$canonicalSkills');
        for (final dir in Directory(
          canonical.path,
        ).listSync().whereType<Directory>()) {
          final name = dir.uri.pathSegments
              .where((segment) => segment.isNotEmpty)
              .last;
          final source = File('${dir.path}/SKILL.md').readAsStringSync();

          final junie = File('$root/.junie/skills/$name/SKILL.md');
          expect(junie.existsSync(), isTrue, reason: '$id: $name');
          expect(
            junie.readAsStringSync(),
            source,
            reason:
                '$id: .junie/skills/$name must be byte-identical to '
                'canonical',
          );

          final claude = File('$root/.claude/skills/$name/SKILL.md');
          expect(claude.existsSync(), isTrue, reason: '$id: $name');
          final expected = source.contains('triggers: ["user"]')
              ? source.replaceFirst(
                  'triggers: ["user"]',
                  'disable-model-invocation: true',
                )
              : source;
          expect(
            claude.readAsStringSync(),
            expected,
            reason:
                '$id: .claude/skills/$name must differ only in the mapped field',
          );
        }
      }
    });
  });
}

/// The number of files under [dir], recursively.
int _filesUnder(Directory dir) => dir.existsSync()
    ? dir.listSync(recursive: true).whereType<File>().length
    : 0;

/// The paths of every file under [dir], relative to [base], sorted.
List<String> _relativeFiles(Directory dir, String base) =>
    dir
        .listSync(recursive: true)
        .whereType<File>()
        .map(
          (file) => file.path.replaceFirst('$base/', '').replaceAll('\\', '/'),
        )
        .toList()
      ..sort();

/// The parsed value of a top-level frontmatter key, or null when absent.
///
/// Deliberately independent of the generator's frontmatter parsing: the drift
/// test must assert the *rendered contract* from the bytes on disk, so a bug in
/// the generator's own parser cannot make the test agree with itself.
List<String>? _frontmatterValue(String content, String key) {
  final lines = content.split('\n');
  final end = lines.indexOf('---', 1);
  if (end < 0) throw StateError('no frontmatter in:\n$content');
  for (final line in lines.sublist(1, end)) {
    if (line.isEmpty || line.startsWith(' ')) continue;
    if (line.split(':').first.trim() != key) continue;
    return line
        .substring(line.indexOf(':') + 1)
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .split(',')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();
  }
  return null;
}

/// The canonical `allowed-tools` token → platform tool names.
///
/// Deliberately duplicated here rather than imported: the drift test must
/// assert the *documented* mapping independently, so a bug in the generator's
/// own table cannot make this test agree with itself.
const _canonicalToolMap = <String, Set<String>>{
  'read': {'Read'},
  'grep': {'Grep'},
  'glob': {'Glob'},
  'edit': {'Write', 'Edit'},
  'exec': {'Bash'},
};

/// Every platform tool name the matrix is allowed to grant.
const _platformTools = {'Read', 'Grep', 'Glob', 'Write', 'Edit', 'Bash'};

/// The tool names granted by an agent profile's frontmatter, normalised to
/// platform tool names.
///
/// Parsed rather than substring-matched: the agent *bodies* legitimately mention
/// `Write` and `Edit` in prose (e.g. "never edits design artifacts"), so a naive
/// `contains('Write')` would test the prompt, not the granted capability.
///
/// All three serializations normalize to the same set, which is what makes a
/// cross-platform comparison meaningful:
/// - canonical `allowed-tools: ["read", "grep", ...]` — tool *tokens*, expanded;
/// - Claude Code `tools: Read, Grep, ...` — comma-separated platform names;
/// - Junie `tools: ["Read", "Grep", ...]` — YAML flow sequence of platform names.
Set<String> _grantedTools(String content) {
  final lines = content.split('\n');
  final end = lines.indexOf('---', 1);
  if (end < 0) {
    throw StateError('no frontmatter in:\n$content');
  }
  for (final line in lines.sublist(1, end)) {
    final isCanonical = line.startsWith('allowed-tools:');
    if (!isCanonical && !line.startsWith('tools:')) continue;
    final value = line
        .substring(line.indexOf(':') + 1)
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '');
    final tools = <String>{};
    for (final token in value.split(',').map((t) => t.trim())) {
      if (token.isEmpty) continue;
      if (isCanonical) {
        final mapped = _canonicalToolMap[token];
        if (mapped == null) {
          throw StateError(
            'unmapped canonical tool token `$token` in:\n$content',
          );
        }
        tools.addAll(mapped);
      } else {
        if (!_platformTools.contains(token)) {
          throw StateError('unknown platform tool `$token` in:\n$content');
        }
        tools.add(token);
      }
    }
    return tools;
  }
  throw StateError(
    'no `tools:`/`allowed-tools:` frontmatter key in:\n$content',
  );
}

/// Finds the framework repository root.
///
/// Resolved from the package's own URI rather than from `Directory.current`:
/// `Platform.script` under `dart test` is a kernel snapshot in a temp
/// directory, and sibling test files reassign `Directory.current` to a sandbox.
Future<String> _resolveRepoRoot() async {
  const marker = 'framework/templates/__brick__';

  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:framework_cli/framework_cli.dart'),
  );
  if (packageUri != null) {
    // <repo>/cli/lib -> <repo>/cli -> <repo>
    final root = File.fromUri(packageUri).parent.parent.parent.path;
    if (Directory('$root/$marker').existsSync()) return root;
  }

  var candidate = Directory.current.absolute.path;
  for (var i = 0; i < 8; i++) {
    if (Directory('$candidate/$marker').existsSync()) return candidate;
    final separator = candidate.lastIndexOf(Platform.pathSeparator);
    if (separator <= 0) break;
    candidate = candidate.substring(0, separator);
  }

  throw StateError(
    'Cannot locate the framework repository root (no `$marker` found).',
  );
}
