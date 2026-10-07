import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

/// Read-only citation and command drift checker.
///
/// Every fixture is built in a fresh temporary directory and every assertion is
/// pinned to that directory. Nothing here reads the developer's home directory
/// or the repository checkout: this repo has already recorded one test defect of
/// exactly that shape (`bootstrap_integration_test.dart` hardcodes an absolute
/// home path and therefore runs on one machine only), and that is not repeated.
///
/// The negative cases matter as much as the positive ones. Each behaviour below
/// was verified to *fail* when its logic is neutered; see the report for the
/// mutation matrix. The checker's own safety properties are pinned here too —
/// the "never spawns a subprocess" claim is asserted against the source of the
/// whole `check/` library, not against a comment.
void main() {
  late Directory root;
  late String appPath;
  late String targetPath;
  late String briefPath;

  /// Writes [content] at [artifactPath], relative to the fixture root.
  void writeArtifact(String artifactPath, String content) {
    final file = File('${root.path}/$artifactPath')
      ..parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('aef_check_citations_');
    writeArtifact('cli/app.dart', 'one\ntwo\nthree\n');
    writeArtifact('docs/target.md', 'alpha\nbravo\ncharlie\n');
    appPath = 'cli/app.dart';
    targetPath = 'docs/target.md';
    briefPath = 'docs/brief.md';
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The arguments every fixture check needs: an artifact dir and its tree.
  List<String> check(String dir, {bool json = false}) => [
    CommandNames.checkCitations,
    '--dir',
    '${root.path}/$dir',
    '--root',
    root.path,
    if (json) '--json',
  ];

  /// Runs the check and returns the invocation.
  Future<CliInvocation> run(List<String> args) =>
      FrameworkCliRunner().run(args);

  /// The `blockers` of a check invocation, i.e. the machine-readable findings.
  List<String> findings(CliInvocation invocation) => invocation.result.blockers;

  /// The *verdicts* of a run: the class, artifact and scope of every finding,
  /// with the echoed command text and the line numbers dropped.
  ///
  /// This is the projection the idempotency claims are about. Editing the row
  /// that publishes a count legitimately changes the echoed bytes and shifts
  /// line numbers; it must never change a verdict.
  List<String> verdicts(CliInvocation invocation) => invocation.result.blockers
      .map(
        (line) => line
            .split(' command=')
            .first
            .split(RegExp(r'\s+at=\d+'))
            .join(' at=<line>'),
      )
      .toList();

  /// The citation findings of a given class, in report order.
  List<String> citationDriftOf(CliInvocation i, CitationDriftClass c) => i
      .result
      .blockers
      .where((line) => line.startsWith('CITATION_DRIFT ${c.wireName} '))
      .toList();

  /// The command findings of a given class, in report order.
  List<String> commandDriftOf(CliInvocation i, CommandDriftClass c) => i
      .result
      .blockers
      .where((line) => line.startsWith('COMMAND_DRIFT ${c.wireName} '))
      .toList();

  group('citation drift', () {
    test('a resolving citation produces no drift and exits 0', () async {
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        'The invariant lives in `$appPath:2`.\n'
        'And a range in `$targetPath:1-3`.\n',
      );

      final invocation = await run(check('docs'));

      expect(findings(invocation), isEmpty);
      expect(invocation.result.message, contains('drift_found: no'));
      expect(invocation.result.family, ResultFamily.commandComplete);
      expect(invocation.result.success, isTrue);
      expect(invocation.exitCode, 0);
      expect(invocation.result.message, contains('citation_drift: 0'));
    });

    test('a citation to a missing path is reported', () async {
      writeArtifact(briefPath, '# Brief\n\nSee `cli/removed.dart:1`.\n');

      final invocation = await run(check('docs'));

      final unresolved = citationDriftOf(
        invocation,
        CitationDriftClass.unresolvedPath,
      );
      expect(unresolved, hasLength(1));
      expect(
        unresolved.single,
        'CITATION_DRIFT UNRESOLVED_PATH artifact=$briefPath at=3 '
        'path=cli/removed.dart claimed_line=1 claimed_end=- '
        'detail=path-does-not-exist-under-root',
      );
      expect(invocation.result.family, ResultFamily.validationFailed);
      expect(invocation.exitCode, 20);
    });

    test('a citation past end-of-file is reported', () async {
      // `cli/app.dart` holds exactly 3 lines; line 9 does not exist.
      writeArtifact(briefPath, '# Brief\n\nSee `$appPath:9`.\n');

      final invocation = await run(check('docs'));

      final beyond = citationDriftOf(
        invocation,
        CitationDriftClass.lineBeyondEof,
      );
      expect(beyond, hasLength(1));
      expect(beyond.single, contains('path=$appPath'));
      expect(beyond.single, contains('claimed_line=9'));
      expect(beyond.single, contains('detail=file-has-3-line(s)'));
      expect(invocation.exitCode, 20);
    });

    test('an inverted range is reported', () async {
      writeArtifact(briefPath, '# Brief\n\nRange `$targetPath:3-1`.\n');

      final invocation = await run(check('docs'));

      final inverted = citationDriftOf(
        invocation,
        CitationDriftClass.invertedRange,
      );
      expect(inverted, hasLength(1));
      expect(inverted.single, contains('claimed_line=3 claimed_end=1'));
      expect(inverted.single, contains('detail=start-3-is-after-end-1'));
    });

    test('a range endpoint past end-of-file is reported', () async {
      writeArtifact(briefPath, '# Brief\n\nRange `$targetPath:2-99`.\n');

      final invocation = await run(check('docs'));

      final beyond = citationDriftOf(
        invocation,
        CitationDriftClass.rangeBeyondEof,
      );
      expect(beyond, hasLength(1));
      expect(beyond.single, contains('claimed_line=2 claimed_end=99'));
    });

    test('line zero is reported as not a line', () async {
      writeArtifact(briefPath, '# Brief\n\nZero `$appPath:0`.\n');

      final invocation = await run(check('docs'));

      expect(
        citationDriftOf(invocation, CitationDriftClass.lineNotPositive),
        hasLength(1),
      );
    });

    test(
      'absolute and parent-escaping citations are reported, not followed',
      () async {
        writeArtifact(
          briefPath,
          '# Brief\n\n'
          'Absolute `/tmp/nowhere.md:1`.\n'
          'Escaping `/tmp/../elsewhere.md:1`.\n'
          // A leading `./` is deliberately not a citation (see --help), so a
          // relative escape is spelled with a leading slash to be matchable.
          'Not a citation `./relative.md:1`.\n',
        );

        final invocation = await run(check('docs'));

        final outside = citationDriftOf(
          invocation,
          CitationDriftClass.outsideRoot,
        );
        expect(outside, hasLength(2));
        expect(
          outside.map((line) => line.split(' path=').last.split(' ').first),
          ['/tmp/nowhere.md', '/tmp/../elsewhere.md'],
        );
        expect(findings(invocation), hasLength(2));
      },
    );

    test('a URL and a quoted regex are not citations', () async {
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        'See https://example.com/thing.md:3 for the rule.\n'
        "```bash\ngrep -rnoE '[A-Za-z0-9_/.-]+\\.(dart|yaml|md):[0-9]+' .\n```\n",
      );

      final invocation = await run(check('docs'));

      expect(
        findings(invocation).where((l) => l.startsWith('CITATION_DRIFT ')),
        isEmpty,
      );
      expect(invocation.result.message, contains('citations_checked: 0'));
    });

    test(
      'a citation resolves against the artifact directory as a fallback',
      () async {
        // `target.md` is written relative to the artifact, not to the root.
        writeArtifact(briefPath, '# Brief\n\n`target.md:2` is the row.\n');

        final invocation = await run(check('docs'));

        expect(findings(invocation), isEmpty);
        expect(invocation.result.message, contains('citations_checked: 1'));
      },
    );

    test(
      'line counting treats a trailing newline as terminating the last line',
      () async {
        // `cli/app.dart` is `one\ntwo\nthree\n` — 3 lines, not 4.
        writeArtifact(briefPath, '`$appPath:3` is the last line.\n');

        final invocation = await run(check('docs'));
        expect(findings(invocation), isEmpty);
      },
    );

    test(
      'only Markdown is scanned, and nested dot-directories are skipped',
      () async {
        writeArtifact(briefPath, '`$appPath:1`\n');
        writeArtifact('docs/notes.txt', '`$appPath:99`\n');
        writeArtifact('docs/.hidden/secret.md', '`$appPath:99`\n');

        final invocation = await run(check('docs'));

        // `brief.md` and the setUp fixture `target.md`; neither `notes.txt`
        // nor the nested dot-directory is scanned, and neither `cli/app.dart:99`
        // citation therefore produced a finding.
        expect(invocation.result.message, contains('artifacts_scanned: 2'));
        expect(invocation.result.message, contains('citations_checked: 1'));
        expect(findings(invocation), isEmpty);
      },
    );
  });

  group('command extraction and reporting (never execution)', () {
    test('a fenced command is extracted with its claimed value', () async {
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        '```bash\n'
        "grep -c 'TODO' $appPath # => 7\n"
        '```\n',
      );

      final invocation = await run(check('docs'));

      expect(invocation.result.message, contains('commands_extracted: 1'));
      expect(
        invocation.result.message,
        contains(
          'COMMAND $briefPath:4 lang=bash claimed=7 claimed_revision=- drift=0',
        ),
      );
      expect(invocation.result.message, contains('commands_executed: 0'));
      expect(findings(invocation), isEmpty);
      expect(invocation.exitCode, 0);
    });

    test('a claimed revision is reported verbatim', () async {
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        '```bash\n'
        '# at 0123456789abcdef0123456789abcdef01234567\n'
        "wc -l $targetPath\n"
        '```\n',
      );

      final invocation = await run(check('docs'));

      expect(
        invocation.result.message,
        contains('claimed_revision=0123456789abcdef0123456789abcdef01234567'),
      );
    });

    test(
      'a shell-session transcript is not misreported as a command',
      () async {
        writeArtifact(
          briefPath,
          '# Brief\n\n'
          '```bash\n'
          "\$ grep -c TODO $appPath\n"
          '7\n'
          '\$ echo done\n'
          'done\n'
          '```\n',
        );

        final invocation = await run(check('docs'));

        expect(invocation.result.message, contains('transcript_blocks: 1'));
        expect(invocation.result.message, contains('commands_extracted: 0'));
        expect(invocation.result.message, isNot(contains('\nCOMMAND ')));
        expect(findings(invocation), isEmpty);
        expect(invocation.exitCode, 0);
      },
    );

    test(
      'a non-shell language block and an unlabelled block are not commands',
      () async {
        writeArtifact(
          briefPath,
          '# Brief\n\n'
          '```text\n'
          "grep -c TODO $appPath\n"
          '```\n'
          '\n'
          '```\n'
          "ls -la $appPath\n"
          '```\n',
        );

        final invocation = await run(check('docs'));

        expect(invocation.result.message, contains('non_command_blocks: 1'));
        expect(invocation.result.message, contains('unlabelled_blocks: 1'));
        expect(invocation.result.message, contains('commands_extracted: 0'));
        expect(findings(invocation), isEmpty);
      },
    );

    test(
      'a command naming a repository path that does not exist is reported',
      () async {
        writeArtifact(
          briefPath,
          '# Brief\n\n'
          '```bash\n'
          'wc -l cli/gone/directory.md\n'
          '```\n',
        );

        final invocation = await run(check('docs'));

        final missing = commandDriftOf(
          invocation,
          CommandDriftClass.missingScopePath,
        );
        expect(missing, hasLength(1));
        expect(missing.single, contains('scope=cli/gone/directory.md'));
      },
    );
  });

  group('idempotency: a published count is not stable under editing itself', () {
    /// The reporter's own grep, scoped to the directory the row lives in.
    const selfReferencingBlock =
        "grep -rnoE '[A-Za-z0-9_/.-]+\\.(dart|yaml|md):[0-9]+(-[0-9]+)?' "
        'docs/adr | sort -u';

    String artifactWith({
      required String claimedValue,
      bool includeBreakdownRow = true,
    }) {
      return '# GAP-6\n\n'
          '```bash\n'
          '$selfReferencingBlock # => $claimedValue\n'
          '```\n'
          '\n'
          'GAP-6 has $claimedValue hits.\n'
          '${includeBreakdownRow ? '\nPer-file:\n\n- brief.md: 12\n- target.md: 4\n' : ''}';
    }

    test(
      'a count published inside the directory it counts is detected',
      () async {
        writeArtifact('docs/adr/brief.md', artifactWith(claimedValue: '37'));

        final invocation = await run(check('docs'));

        final selfReferencing = commandDriftOf(
          invocation,
          CommandDriftClass.selfReferencingScope,
        );
        expect(
          selfReferencing,
          hasLength(1),
          reason:
              'a grep-count row published inside the directory it counts counts '
              'its own command line; that is the drift class to report',
        );
        expect(selfReferencing.single, contains('scope=docs/adr'));
        expect(invocation.exitCode, 20);
      },
    );

    test(
      'a command scoped outside the artifact directory is not flagged',
      () async {
        writeArtifact(
          briefPath,
          '# Brief\n\n'
          '```bash\n'
          'grep -c TODO $appPath # => 3\n'
          '```\n',
        );

        final invocation = await run(check('docs'));
        expect(
          commandDriftOf(invocation, CommandDriftClass.selfReferencingScope),
          isEmpty,
        );
      },
    );

    test(
      'editing the claimed value and the breakdown row changes nothing',
      () async {
        writeArtifact(
          'docs/adr/brief.md',
          artifactWith(claimedValue: '37', includeBreakdownRow: true),
        );
        final before = await run(check('docs'));

        // The measured lesson: deleting the per-file breakdown moved the count.
        writeArtifact(
          'docs/adr/brief.md',
          artifactWith(claimedValue: '99999', includeBreakdownRow: false),
        );
        final after = await run(check('docs'));

        // The verdict set is unchanged even though the row's own bytes, its
        // claimed value, its line numbers and its per-file breakdown changed.
        expect(verdicts(after), equals(verdicts(before)));
        expect(
          commandDriftOf(after, CommandDriftClass.selfReferencingScope),
          hasLength(1),
        );
      },
    );

    test('publishing the check\'s own report creates no new finding', () async {
      writeArtifact('docs/adr/brief.md', artifactWith(claimedValue: '37'));
      writeArtifact('docs/adr/target.md', 'alpha\nbravo\n');

      final first = await run(check('docs'));
      expect(findings(first), isNotEmpty);

      // Paste the checker's own human output into the artifact set — exactly
      // what happens when a reviewer publishes the report next to the row.
      writeArtifact(
        'docs/adr/brief.md',
        '${artifactWith(claimedValue: '37')}\n\n'
            '<!-- checker output -->\n'
            '```\n'
            '${first.output}\n'
            '```\n',
      );
      final second = await run(check('docs'));

      expect(verdicts(second), equals(verdicts(first)));
      expect(findings(second), equals(findings(first)));
      expect(second.result.message, contains('drift_found: yes'));
      // `docs/brief.md`, the setUp fixture `docs/target.md`, and
      // `docs/adr/target.md`: the pasted report added no artifact.
      expect(second.result.message, contains('artifacts_scanned: 3'));
    });

    test('no rendered citation finding is itself a citation', () {
      // The wire format is the idempotency guarantee: a `path:line` label in the
      // report would re-enter the checker as a fresh citation.
      for (final line in const [
        'CITATION_DRIFT UNRESOLVED_PATH artifact=docs/brief.md at=3 '
            'path=cli/removed.dart claimed_line=1 claimed_end=- detail=x',
        'CITATION_DRIFT LINE_BEYOND_EOF artifact=docs/brief.md at=9 '
            'path=cli/app.dart claimed_line=9 claimed_end=- detail=x',
        'CITATION_DRIFT INVERTED_RANGE artifact=docs/brief.md at=4 '
            'path=docs/target.md claimed_line=3 claimed_end=1 detail=x',
        'CITATION_DRIFT OUTSIDE_ROOT artifact=docs/brief.md at=5 '
            'path=/etc/hosts claimed_line=1 claimed_end=- detail=x',
      ]) {
        expect(
          citationsIn(line),
          isEmpty,
          reason:
              'a rendered finding must not be readable as a citation: $line',
        );
      }
    });

    test('the check is deterministic: two runs agree byte for byte', () async {
      writeArtifact('docs/adr/brief.md', artifactWith(claimedValue: '37'));

      final first = await run(check('docs'));
      final second = await run(check('docs'));

      expect(second.output, first.output);
    });
  });

  group('exit-code contract', () {
    test(
      'clean => SUCCESS / 0, drift => PREFLIGHT_POLICY_FAILURE / 20',
      () async {
        writeArtifact(briefPath, 'All good: `$appPath:1`.\n');
        final clean = await run(check('docs'));
        expect(clean.result.exitCategory, ExitCategory.success);
        expect(clean.exitCode, 0);

        writeArtifact(briefPath, 'Broken: `cli/removed.dart:1`.\n');
        final drifted = await run(check('docs'));
        expect(
          drifted.result.exitCategory,
          ExitCategory.preflightPolicyFailure,
        );
        expect(drifted.exitCode, 20);
        expect(drifted.result.exitCode, drifted.exitCode);
      },
    );

    test(
      'no ADR 0002 code is reused and no stub code is used for a real outcome',
      () async {
        writeArtifact(briefPath, 'Broken: `cli/removed.dart:1`.\n');
        final drifted = await run(check('docs'));

        // Drift is a real outcome, so it must not be reported through the
        // not-implemented (50) category, and must not be reported as success.
        expect(drifted.result.family, isNot(ResultFamily.notImplemented));
        expect(drifted.exitCode, isNot(50));
        expect(
          drifted.result.exitCategory.categoryName,
          isNot('NOT_IMPLEMENTED'),
        );
        // ...and it must not collide with a code ADR 0002 assigns elsewhere.
        expect(drifted.exitCode, isNot(10));
        expect(drifted.exitCode, isNot(30));
        expect(drifted.exitCode, isNot(40));
      },
    );

    test(
      'bad arguments are reported as a validation failure, not success',
      () async {
        final missingDir = await run([CommandNames.checkCitations]);
        expect(missingDir.result.family, ResultFamily.validationFailed);
        expect(missingDir.exitCode, 20);
        expect(
          missingDir.result.blockers.single,
          contains('Missing required --dir'),
        );

        final absent = await run([
          CommandNames.checkCitations,
          '--dir',
          '${root.path}/nope',
          '--root',
          root.path,
        ]);
        expect(absent.result.family, ResultFamily.validationFailed);
        expect(absent.exitCode, 20);
        expect(absent.result.blockers.single, contains('--dir does not exist'));

        final notADirectory = await run([
          CommandNames.checkCitations,
          '--dir',
          '${root.path}/$appPath',
          '--root',
          root.path,
        ]);
        expect(notADirectory.exitCode, 20);
        expect(
          notADirectory.result.blockers.single,
          contains('--dir is not a directory'),
        );

        final outside = await run([
          CommandNames.checkCitations,
          '--dir',
          Directory.systemTemp.path,
          '--root',
          root.path,
        ]);
        expect(outside.exitCode, 20);
        expect(
          outside.result.blockers.single,
          contains('is not inside --root'),
        );
      },
    );
  });

  group('machine output', () {
    test('--json parses and agrees with the human rendering', () async {
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        'Broken `cli/removed.dart:1` and past EOF `$appPath:99`.\n'
        '\n'
        '```bash\n'
        'grep -c TODO $appPath # => 4\n'
        '```\n',
      );

      final human = await run(check('docs'));
      final json = await run(check('docs', json: true));

      final decoded = jsonDecode(json.output) as Map<String, Object?>;
      expect(
        decoded.keys.toList(),
        human.result.toJson().keys.toList(),
        reason: 'the envelope shape must be the standard one, unchanged',
      );
      expect(decoded['command'], CommandNames.checkCitations);
      expect(decoded['exit_code'], human.exitCode);
      expect(decoded['exit_category'], human.result.exitCategory.categoryName);
      expect(decoded['success'], human.result.success);
      expect(decoded['message'], human.result.message);
      expect(decoded['message'], contains('drift_found: yes'));

      final jsonFindings = (decoded['blockers'] as List).cast<String>();
      expect(jsonFindings, equals(human.result.blockers));
      expect(
        jsonFindings.where((line) => line.startsWith('CITATION_DRIFT ')),
        hasLength(2),
      );
      expect(
        jsonFindings.where((line) => line.startsWith('COMMAND_DRIFT ')),
        isEmpty,
      );

      // The human rendering must carry the very same findings.
      for (final finding in human.result.blockers) {
        expect(human.output, contains(finding));
      }
    });

    test('--json on a clean tree parses and reports success', () async {
      writeArtifact(briefPath, 'Fine: `$appPath:1`.\n');

      final json = await run(check('docs', json: true));
      final decoded = jsonDecode(json.output) as Map<String, Object?>;

      expect(decoded['success'], isTrue);
      expect(decoded['exit_code'], 0);
      expect(decoded['blockers'], isEmpty);
    });

    test(
      '--help prints the threat model and is itself machine-readable',
      () async {
        final human = await run([CommandNames.checkCitations, '--help']);
        // The policy prose is word-wrapped to a terminal width, so fold
        // whitespace before matching a phrase.
        final folded = human.output.replaceAll(RegExp(r'\s+'), ' ');
        expect(human.result.success, isTrue);
        expect(human.output, contains('THREAT MODEL'));
        expect(folded, contains('Design artifacts are untrusted input'));
        expect(folded, contains('never runs them'));
        expect(
          folded,
          contains('spawns no subprocess'),
          reason:
              'the read-only guarantee belongs in --help, not only in a commit',
        );
        expect(
          folded,
          contains('IDEMPOTENCY'),
          reason: 'the idempotency contract must be visible to a caller too',
        );
        expect(
          folded,
          contains('--execute-commands is accepted and always refused'),
        );

        final json = await run([
          CommandNames.checkCitations,
          '--help',
          '--json',
        ]);
        final decoded = jsonDecode(json.output) as Map<String, Object?>;
        expect(decoded['message'], human.output);
        expect(decoded['command'], CommandNames.checkCitations);
        expect(decoded['success'], isTrue);
      },
    );
  });

  group('the safety requirement: no command is ever executed', () {
    test(
      '--execute-commands is refused, whatever the other arguments',
      () async {
        writeArtifact(briefPath, '`cli/removed.dart:1`\n');
        writeArtifact('side-effect-canary.txt', 'untouched\n');

        final variants = <List<String>>[
          [CommandNames.checkCitations, '--execute-commands'],
          [
            CommandNames.checkCitations,
            '--execute-commands',
            '--dir',
            '${root.path}/docs',
            '--root',
            root.path,
          ],
          // Flag ordering must not matter.
          [
            CommandNames.checkCitations,
            '--dir',
            '${root.path}/docs',
            '--execute-commands',
            '--root',
            root.path,
          ],
          [
            CommandNames.checkCitations,
            '--json',
            '--execute-commands',
            '--dir',
            '${root.path}/docs',
            '--root',
            root.path,
          ],
        ];

        for (final args in variants) {
          final invocation = await run(args);
          expect(
            invocation.result.family,
            ResultFamily.validationFailed,
            reason: '$args',
          );
          expect(invocation.exitCode, 20, reason: '$args');
          expect(
            invocation.result.message,
            contains(kExecutionRefusalReason),
            reason: 'the refusal must name itself: $args',
          );
          expect(invocation.result.blockers, contains(kThreatModel));
          // The check must not have run at all, so it cannot have executed
          // anything: a refusal carries no scan summary whatsoever.
          expect(
            invocation.result.message,
            isNot(contains('commands_executed')),
            reason: 'a refusal must short-circuit before the scan: $args',
          );
        }
      },
    );

    test(
      '--no-execute-commands is rejected rather than silently accepted',
      () async {
        final invocation = await run([
          CommandNames.checkCitations,
          '--no-execute-commands',
        ]);
        expect(invocation.result.family, ResultFamily.internalError);
        expect(invocation.exitCode, 40);
        expect(
          invocation.output,
          contains('Cannot negate option "--no-execute-commands"'),
          reason:
              'a negated execution flag must be a parse error, never a silently '
              'accepted run',
        );
      },
    );

    test('the direct library entry point cannot execute anything', () async {
      // `runCheckCitations` has no execution parameter at all, so the safety
      // property does not depend on the flag being threaded through: the
      // primitive simply does not exist.
      writeArtifact(briefPath, 'Clean: `$appPath:1`.\n');
      writeArtifact('side-effect-canary.txt', 'untouched\n');
      final result = await runCheckCitations(
        dir: '${root.path}/docs',
        root: root.path,
      );
      expect(result.family, ResultFamily.commandComplete);
      expect(result.exitCode, 0);
      expect(result.message, contains('commands_executed: 0'));

      expect(
        File('${root.path}/side-effect-canary.txt').readAsStringSync(),
        'untouched\n',
      );
    });

    test('the checker library contains no subprocess primitive', () async {
      // A source-level pin, because "it does not spawn a process" is otherwise
      // only a promise in a doc comment. Any future edit that reaches for
      // Process, a shell, or an exec-style API fails here.
      final libraryDir = await _checkLibraryDirectory();
      expect(libraryDir.existsSync(), isTrue, reason: libraryDir.path);

      final sources = libraryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      expect(sources, isNotEmpty, reason: 'the check library must exist');

      // Matched as patterns, not substrings, so a word such as
      // `ExtractedCommand(` cannot be mistaken for a process spawn.
      final forbidden = <RegExp>[
        RegExp(r'\bProcess\b'),
        RegExp(r'\bProcessResult\b'),
        RegExp(r'\bProcessException\b'),
        RegExp(r'\bIsolate\.spawn\b'),
        RegExp(r'/bin/(?:ba)?sh'),
        // A real shell spawn, spelled as an argv list. The threat-model prose
        // in the same file legitimately *mentions* `sh -c`, so a bare substring
        // would match the policy text rather than any call site.
        RegExp(r'''['"](?:ba)?sh['"]\s*,\s*\[\s*['"]-c['"]'''),
        RegExp(r'\bsystem\s*\('),
        RegExp(r'\bexec\s*\('),
      ];
      for (final file in sources) {
        final text = file.readAsStringSync();
        for (final pattern in forbidden) {
          expect(
            pattern.hasMatch(text),
            isFalse,
            reason:
                '${file.path} matches ${pattern.pattern}; the checker must '
                'never be able to execute an artifact-embedded command',
          );
        }
      }
    });

    test('a malicious command body is echoed, never run', () async {
      final canary = '${root.path}/canary-pwned';
      writeArtifact(
        briefPath,
        '# Brief\n\n'
        '```bash\n'
        'rm -rf $root # => 1\n'
        "touch '$canary' ; echo pwned # => 1\n"
        '```\n',
      );
      final before = root.listSync(recursive: true).length;

      final invocation = await run(check('docs'));

      expect(invocation.result.message, contains('commands_executed: 0'));
      // The command text is reported verbatim so a human can inspect it...
      expect(invocation.result.message, contains('rm -rf'));
      expect(invocation.result.message, contains('touch'));
      // ...and nothing it named exists as a side effect.
      expect(File(canary).existsSync(), isFalse);
      expect(root.existsSync(), isTrue);
      expect(root.listSync(recursive: true).length, before);
    });

    test('the check mutates nothing it read', () async {
      writeArtifact(briefPath, '`cli/removed.dart:1` and `$appPath:1`\n');
      // The canary lives inside the fixture root, never at a path relative to
      // the process working directory. A test that proves the check mutates
      // nothing must not itself leave an artifact in the package directory, or
      // a full `dart test` run would stop leaving a clean `git status`.
      writeArtifact('side-effect-canary.txt', 'untouched\n');
      final canary = File('${root.path}/side-effect-canary.txt');

      final before = _treeSnapshot(root);
      final invocation = await run(check('docs'));
      final after = _treeSnapshot(root);

      expect(invocation.exitCode, 20);
      expect(after, equals(before));
      expect(canary.readAsStringSync(), 'untouched\n');
    });
  });
}

/// Every path under [dir], sorted, with each file's byte length — a cheap
/// fingerprint that a read-only run must not change.
List<String> _treeSnapshot(Directory dir) =>
    dir
        .listSync(recursive: true, followLinks: false)
        .map(
          (entity) =>
              '${entity.path.replaceAll('\\', '/')}:'
              '${entity is File ? entity.lengthSync() : 'dir'}',
        )
        .toList()
      ..sort();

/// The `lib/src/check` directory of this package, resolved from the package URI
/// rather than from `Directory.current` (which a sibling test may reassign).
Future<Directory> _checkLibraryDirectory() async {
  const marker = 'lib/src/check';
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:framework_cli/framework_cli.dart'),
  );
  if (packageUri != null) {
    // <repo>/cli/lib/framework_cli.dart -> <repo>/cli/lib -> <repo>/cli
    final lib = File.fromUri(packageUri).parent;
    final directory = Directory('${lib.path}/src/check');
    if (directory.existsSync()) return directory;
  }

  var candidate = Directory.current.absolute.path;
  for (var depth = 0; depth < 8; depth++) {
    final directory = Directory('$candidate/$marker');
    if (directory.existsSync()) return directory;
    final separator = candidate.lastIndexOf(Platform.pathSeparator);
    if (separator <= 0) break;
    candidate = candidate.substring(0, separator);
  }
  throw StateError('Cannot locate $marker');
}
