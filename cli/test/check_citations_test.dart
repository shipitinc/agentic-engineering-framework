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

  /// The ADR 0002 exit-code set. A run that ends outside it crashed rather than
  /// reported an outcome — the defect this group exists to catch.
  const adrExitCodes = <int>{0, 10, 20, 30, 40, 50};

  /// Asserts a check failure was *reported*, not thrown: inside the ADR 0002 set,
  /// with no stack trace, and not a 255 (the code the Dart VM uses for an
  /// unhandled exception — outside the set by construction).
  void expectControlledFailure(CliInvocation invocation, {required int code}) {
    expect(invocation.exitCode, code, reason: 'result: ${invocation.result}');
    expect(
      adrExitCodes,
      contains(invocation.exitCode),
      reason: 'an exit code outside ADR 0002 means the CLI fell over',
    );
    expect(invocation.exitCode, isNot(255));
    expect(invocation.result.family, ResultFamily.internalError);
    expect(invocation.result.exitCategory, ExitCategory.internalToolFailure);
    // An unhandled exception escapes as a stack trace on stderr, before any
    // envelope exists; here everything comes back as one domain result.
    for (final marker in const [
      'Unhandled exception',
      'FileSystemException',
      'PathAccessException',
      '#0 ',
      '#1 ',
      'package:framework_cli',
    ]) {
      expect(
        invocation.output,
        isNot(contains(marker)),
        reason: 'a controlled failure must not leak a stack trace: $marker',
      );
      expect(invocation.result.message, isNot(contains(marker)));
    }
  }

  /// The `ARTIFACT_SKIPPED` rows of a given class, in report order.
  List<String> artifactSkippedOf(CliInvocation i, ArtifactSkipClass c) => i
      .result
      .blockers
      .where((line) => line.startsWith('ARTIFACT_SKIPPED ${c.wireName} '))
      .toList();

  /// The `CITATION_UNVERIFIED` rows, in report order.
  List<String> citationUnverified(CliInvocation i) => i.result.blockers
      .where((line) => line.startsWith('CITATION_UNVERIFIED '))
      .toList();

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
    test('the usage line of an option-less command has no double space', () {
      // Cosmetic, but `framework version  [--json]` read as if a required
      // option had been elided, which is exactly the kind of thing a caller
      // parses this help to find out.
      for (final command in const [
        CommandNames.status,
        CommandNames.doctor,
        CommandNames.version,
      ]) {
        final usage = helpTextFor(command)
            .split('\n')
            .firstWhere(
              (line) => line.trimLeft().startsWith('framework $command '),
            );
        expect(usage, '  framework $command [--json] [--help]');
        expect(usage, isNot(contains('  [--json]')));
      }
    });

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

    test('no rendered drift finding is itself a citation', () {
      // The wire format is the idempotency guarantee: a `path:line` label in the
      // report would re-enter the checker as a fresh citation. Enumerating every
      // class, so a new class cannot arrive with a `path:line` label in it.
      final lines = <String>[
        for (final driftClass in CitationDriftClass.values)
          CitationDrift(
            driftClass: driftClass,
            citation: Citation(
              rawPath: driftClass == CitationDriftClass.outsideRoot
                  ? '/etc/hosts'
                  : 'cli/app.dart',
              start: 9,
              end: driftClass == CitationDriftClass.invertedRange ? 1 : null,
              line: 3,
              column: 0,
            ),
            detail: 'x',
          ).toWireLine('docs/brief.md'),
      ];
      expect(lines, hasLength(CitationDriftClass.values.length));
      for (final line in lines) {
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

  group('unreadable input is reported, never a crash', () {
    /// The untrusted-input cases a design artifact tree can legitimately contain
    /// and an ordinary repository will not: a binary blob named `*.md`, a UTF-16
    /// file, a file with no read permission, an unreadable directory.
    ///
    /// Every one of these raised an unhandled `FileSystemException` out of the
    /// whole run before this group existed, which surfaced as exit 255 — a code
    /// that is in neither ADR 0002's set nor this command's own documented
    /// `0 / 20` block, so a caller could not tell "your artifacts drifted" from
    /// "the checker fell over", and one bad file suppressed the whole report.

    /// Asserts the shared contract: a reported outcome inside the ADR 0002 set,
    /// the skipped artifact named in its own row, and the scan having continued.
    void expectSkippedAndContinued({
      required CliInvocation invocation,
      required List<String> skippedRows,
    }) {
      expectControlledFailure(invocation, code: 40);
      expect(skippedRows, hasLength(1), reason: 'the skip must be reported');
      // `artifacts_scanned` still counts what was walked, and the skip count is
      // published separately so a caller never mistakes a partial scan for a
      // complete one.
      expect(invocation.result.message, contains('artifacts_skipped: 1'));
    }

    test('a non-UTF-8 .md is skipped and reported, not thrown', () async {
      // 0xC3 0x28 is an invalid UTF-8 sequence: a binary blob named `.md`.
      final File blob = File('${root.path}/docs/blob.md')
        ..writeAsBytesSync(<int>[0x23, 0x20, 0xC3, 0x28, 0xFF, 0xFE, 0x0A]);
      // A sibling artifact with real drift proves the scan continued.
      writeArtifact('docs/later.md', '# Later\n\n`cli/removed.dart:1`\n');

      final invocation = await run(check('docs'));

      expectSkippedAndContinued(
        invocation: invocation,
        skippedRows: artifactSkippedOf(
          invocation,
          ArtifactSkipClass.unreadable,
        ),
      );
      expect(
        artifactSkippedOf(invocation, ArtifactSkipClass.unreadable).single,
        'ARTIFACT_SKIPPED UNREADABLE artifact=docs/blob.md '
        'detail=artifact-could-not-be-read-as-utf8-text',
      );
      // The sibling's drift is still reported: one bad file did not suppress it.
      expect(
        citationDriftOf(invocation, CitationDriftClass.unresolvedPath),
        hasLength(1),
      );
      expect(
        invocation.result.message,
        contains('drift_found: yes'),
        reason: 'real drift is still real drift',
      );
      expect(blob.existsSync(), isTrue, reason: 'the check writes nothing');
    });

    test('a UTF-16 .md is skipped and reported, not thrown', () async {
      // UTF-16LE with a BOM: 0xFF is never a valid UTF-8 byte, so the decode
      // fails exactly as an editor-invisible encoding switch would.
      final List<int> bytes = <int>[
        0xFF,
        0xFE, // UTF-16LE BOM
        ...'# Brief'.codeUnits,
        0, // UTF-16LE: every ASCII character is followed by a zero byte
        ...'\n'.codeUnits,
        0,
      ];
      File('${root.path}/docs/utf16.md').writeAsBytesSync(bytes);

      final invocation = await run(check('docs'));

      expectSkippedAndContinued(
        invocation: invocation,
        skippedRows: artifactSkippedOf(
          invocation,
          ArtifactSkipClass.unreadable,
        ),
      );
      expect(
        artifactSkippedOf(invocation, ArtifactSkipClass.unreadable).single,
        contains('artifact=docs/utf16.md'),
      );
      expect(invocation.result.message, contains('drift_found: indeterminate'));
    });

    test('an unreadable .md is skipped and reported, not thrown', () async {
      final File locked = File('${root.path}/docs/locked.md')
        ..writeAsStringSync('# Locked\n');
      Process.runSync('chmod', <String>['000', locked.path]);

      final invocation = await run(check('docs'));

      expectSkippedAndContinued(
        invocation: invocation,
        skippedRows: artifactSkippedOf(
          invocation,
          ArtifactSkipClass.unreadable,
        ),
      );
      expect(
        artifactSkippedOf(invocation, ArtifactSkipClass.unreadable).single,
        contains('artifact=docs/locked.md'),
      );
      // `chmod` did what was asked, so this really was a permission failure and
      // not a no-op that happened to pass.
      expect(
        locked.readAsStringSync,
        throwsA(isA<FileSystemException>()),
        reason: 'the fixture must actually be unreadable',
      );
    });

    test(
      'an unreadable directory is skipped and the scan continues',
      () async {
        // A sibling of the unreadable directory, holding real drift.
        writeArtifact('docs/ok.md', '# Ok\n\n`$appPath:99`\n');
        final Directory locked = Directory('${root.path}/docs/locked')
          ..createSync(recursive: true);
        File('${locked.path}/inner.md').writeAsStringSync('# Inner\n');
        Process.runSync('chmod', <String>['000', locked.path]);
        // Restore the mode before tearDown deletes the fixture tree: a
        // mode-000 directory cannot be unlinked from inside.
        addTearDown(
          () => Process.runSync('chmod', <String>['755', locked.path]),
        );

        final invocation = await run(check('docs'));

        expectControlledFailure(invocation, code: 40);
        final unlistable = artifactSkippedOf(
          invocation,
          ArtifactSkipClass.unlistable,
        );
        expect(
          unlistable,
          hasLength(1),
          reason: 'the unlistable directory must be reported',
        );
        expect(unlistable.single, contains('artifact=locked'));
        // The whole point: a directory that cannot be listed must not take the
        // rest of the tree's report down with it.
        expect(
          citationDriftOf(invocation, CitationDriftClass.lineBeyondEof),
          hasLength(1),
          reason: 'the sibling directory must still be scanned',
        );
        expect(
          invocation.result.message,
          contains('drift_found: yes'),
          reason: 'the sibling\'s real drift is still reported',
        );
      },
      skip: Platform.isWindows
          ? 'POSIX file modes; Windows cannot express mode 000 this way'
          : null,
    );

    test('a cited file that is not UTF-8 is reported unverified', () async {
      // The other read site: `CitationResolver.lineCountOf`. A citation whose
      // target is binary cannot be line-checked, and inventing a line count for
      // it would manufacture a false LINE_BEYOND_EOF.
      File(
        '${root.path}/$appPath',
      ).writeAsBytesSync(<int>[0x00, 0xC3, 0x28, 0xFF, 0xFE, 0x0A, 0x61]);
      writeArtifact(briefPath, '# Brief\n\nSee `$appPath:99`.\n');

      final invocation = await run(check('docs'));

      expectControlledFailure(invocation, code: 40);
      expect(citationUnverified(invocation), hasLength(1));
      expect(
        citationUnverified(invocation).single,
        'CITATION_UNVERIFIED artifact=$briefPath at=3 '
        'path=$appPath claimed_line=99 claimed_end=- '
        'detail=cited-file-could-not-be-read-as-utf8-text',
      );
      expect(
        citationDriftOf(invocation, CitationDriftClass.lineBeyondEof),
        isEmpty,
        reason: 'an unreadable target must not be reported as past-EOF drift',
      );
      expect(invocation.result.message, contains('citations_unverified: 1'));
      expect(invocation.result.message, contains('drift_found: indeterminate'));
    });

    test('a structural finding survives an unreadable cited file', () async {
      // An inverted range and a line-0 are decidable from the citation alone,
      // so an unreadable target must not hide them — nor hide itself.
      File(
        '${root.path}/$appPath',
      ).writeAsBytesSync(<int>[0x00, 0xC3, 0x28, 0xFF, 0xFE, 0x0A]);
      writeArtifact(briefPath, '# Brief\n\nRange `$appPath:3-1`.\n');

      final invocation = await run(check('docs'));

      expectControlledFailure(invocation, code: 40);
      expect(
        citationDriftOf(invocation, CitationDriftClass.invertedRange),
        hasLength(1),
        reason: 'an inverted range needs no file read, so nothing hid it',
      );
      expect(
        citationUnverified(invocation),
        hasLength(1),
        reason: 'and the unreadable target is still reported',
      );
    });

    test('a partial scan never reports a clean verdict', () async {
      // The anti-false-green property: exit 0 means "no drift", so a partial scan
      // must not be allowed to claim it. This is what distinguishes 40 from 20
      // and from 0.
      File(
        '${root.path}/docs/blob.md',
      ).writeAsBytesSync(<int>[0xC3, 0x28, 0xFF]);

      final invocation = await run(check('docs'));

      expect(invocation.result.family, ResultFamily.internalError);
      expect(invocation.exitCode, 40);
      expect(invocation.result.success, isFalse);
      expect(invocation.result.message, contains('drift_found: indeterminate'));
      expect(invocation.result.message, isNot(contains('drift_found: no')));
      expect(invocation.result.message, isNot(contains('drift_found: yes')));
    });

    test('the skip rows are machine-readable in --json too', () async {
      File('${root.path}/docs/blob.md').writeAsBytesSync(<int>[0xC3, 0x28]);

      final json = await run(check('docs', json: true));

      final decoded = jsonDecode(json.output) as Map<String, Object?>;
      expect(decoded['exit_code'], 40);
      expect(decoded['exit_category'], 'INTERNAL_TOOL_FAILURE');
      expect(decoded['success'], isFalse);
      final blockers = (decoded['blockers'] as List).cast<String>();
      expect(
        blockers.where((l) => l.startsWith('ARTIFACT_SKIPPED ')),
        hasLength(1),
        reason: 'a skipped artifact must never be invisible to a caller',
      );
    });

    test('no rendered row is itself a citation', () async {
      // The same idempotency guarantee the drift rows carry: publishing this
      // report into the artifact set must not manufacture a new finding.
      //
      // Rendered through the *production* renderers rather than against literal
      // strings. Asserting over hand-written literals would pass whatever the
      // renderers emit, so a wire format that reintroduced a `path:line` label
      // would sail through — which is exactly the class of weakness this
      // replaces.
      final citation = Citation(
        rawPath: 'cli/app.dart',
        start: 99,
        end: null,
        line: 3,
        column: 0,
      );
      final rendered = <String>[
        ArtifactSkipped(
          skipClass: ArtifactSkipClass.unreadable,
          relativePath: 'docs/blob.md',
          detail: 'artifact-could-not-be-read-as-utf8-text',
        ).toWireLine(),
        ArtifactSkipped(
          skipClass: ArtifactSkipClass.unlistable,
          relativePath: 'locked',
          detail: 'directory-could-not-be-listed-contents-unchecked',
        ).toWireLine(),
        CitationUnverified(
          citation: citation,
          detail: 'cited-file-could-not-be-read-as-utf8-text',
        ).toWireLine('docs/brief.md'),
        for (final driftClass in CitationDriftClass.values)
          CitationDrift(
            driftClass: driftClass,
            citation: citation,
            detail: 'x',
          ).toWireLine('docs/brief.md'),
      ];
      expect(rendered, hasLength(3 + CitationDriftClass.values.length));

      for (final line in rendered) {
        expect(
          citationsIn(line),
          isEmpty,
          reason: 'a rendered row must not be readable as a citation: $line',
        );
      }
    });
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

    test('the refusal is decided before --help, not after it', () async {
      // `--help` used to short-circuit ahead of the refusal, so this spelling
      // exited 0 with help text. Nothing executed either way — the property that
      // matters still held — but the brief requires the refusal to be
      // "not bypassable by flag ordering or any alternate code path", and
      // `--help` is an alternate path.
      for (final args in <List<String>>[
        [
          CommandNames.checkCitations,
          '--dir',
          '${root.path}/docs',
          '--root',
          root.path,
          '--execute-commands',
          '--help',
        ],
        [CommandNames.checkCitations, '--help', '--execute-commands'],
        [CommandNames.checkCitations, '--help', '--execute-commands', '--json'],
      ]) {
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
          reason: 'a help path must not swallow the refusal: $args',
        );
        expect(
          invocation.result.message,
          isNot(contains('THREAT MODEL — READ BEFORE TRUSTING A RESULT')),
          reason: 'the refusal is returned, not the help text: $args',
        );
      }

      // ...and plain `--help` still prints the help and succeeds.
      final help = await run([CommandNames.checkCitations, '--help']);
      expect(help.result.success, isTrue);
      expect(help.exitCode, 0);
      expect(help.output, contains('THREAT MODEL'));

      // `--help` on other commands is untouched.
      final other = await run([CommandNames.version, '--help']);
      expect(other.result.success, isTrue);
      expect(other.exitCode, 0);
    });

    test(
      'the refusal never invokes the scanner, whatever the arguments',
      () async {
        // The ordering is pinned observably rather than by message text: a
        // scan-then-discard implementation returns a refusal carrying no scan
        // summary, so a message assertion cannot tell it apart from a genuine
        // short-circuit. Counting invocations of an injected scanner can.
        //
        // Verified against the mutation this replaced: moving the refusal to
        // after `runCheckCitations` (returning the scan result otherwise) leaves
        // the message assertions passing and fails this test.
        for (final args in <List<String>>[
          [CommandNames.checkCitations, '--execute-commands'],
          [
            CommandNames.checkCitations,
            '--execute-commands',
            '--dir',
            '${root.path}/docs',
            '--root',
            root.path,
          ],
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
            '--execute-commands',
            '--help',
            '--dir',
            '${root.path}/docs',
          ],
          [CommandNames.checkCitations, '--help', '--execute-commands'],
        ]) {
          final scanner = _RecordingScanner();
          final invocation = await FrameworkCliRunner(
            scanner: scanner.call,
          ).run(args);

          expect(invocation.exitCode, 20, reason: '$args');
          expect(
            invocation.result.message,
            contains(kExecutionRefusalReason),
            reason: '$args',
          );
          expect(
            scanner.invocations,
            0,
            reason:
                'the refusal must short-circuit BEFORE the scan, never scan and '
                'discard: $args',
          );
        }
      },
    );

    test(
      'the scanner seam is used, so the refusal assertion above can bite',
      () async {
        // If the seam were silently ignored, "never invoked" would be vacuously
        // true. Here the same seam must be invoked on the scanning path, so the
        // refusal test is measuring something real.
        writeArtifact(briefPath, '# Brief\n\n`cli/removed.dart:1`\n');

        final scanner = _RecordingScanner();
        final invocation = await FrameworkCliRunner(
          scanner: scanner.call,
        ).run(check('docs'));

        expect(scanner.invocations, 1, reason: 'the seam must be live');
        expect(invocation.exitCode, 20, reason: 'the real scan still ran');
        expect(
          invocation.result.message,
          contains('drift_found: yes'),
          reason: 'the injected scanner really produced the report',
        );
      },
    );

    test('no command-line argument can replace the scanner', () async {
      // The seam is a library parameter, not a flag: the CLI always scans with
      // the real `checkArtifacts`, so no caller-supplied text can turn the scan
      // into a no-op that reports success.
      writeArtifact(briefPath, '# Brief\n\n`cli/removed.dart:1`\n');

      final invocation = await run([
        CommandNames.checkCitations,
        '--dir',
        '${root.path}/docs',
        '--root',
        root.path,
        '--scanner',
        'noop',
        '--scanner=noop',
      ]);

      // An unknown option is a parse error, not a silently accepted no-op scan.
      expect(invocation.result.family, ResultFamily.internalError);
      expect(invocation.exitCode, 40);
      expect(invocation.output, contains('scanner'));
    });

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

    test('the checker reaches commands.dart only for CommandNames', () async {
      // The forbidden-pattern guard above scans `check/**`, but
      // `check_citations.dart` transitively imports `commands.dart`, which
      // does spawn `git` (as does `upgrade/upgrade.dart`). So an edit routing
      // this command through a git-spawning function would pass that guard.
      //
      // This closes the gap from the caller's side instead: the checker may
      // reference exactly one symbol from those modules — `CommandNames`, a
      // constant name holder — and nothing else. Anything that reaches a
      // process primitive from here has to cross this line first.
      final libraryDir = await _checkLibraryDirectory();
      final sources = libraryDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      expect(sources, isNotEmpty, reason: libraryDir.path);

      final srcRoot = libraryDir.parent;
      // Every module reachable from the checker that contains a process
      // primitive. Adding to this list is free; the assertion below is what
      // bites.
      final processBearingModules = <String>[
        'commands.dart',
        'upgrade/upgrade.dart',
      ];
      final declaredElsewhere = <String, String>{};
      for (final relative in processBearingModules) {
        final module = File('${srcRoot.path}/$relative');
        expect(
          module.existsSync(),
          isTrue,
          reason: 'a module this test does not scan must not be added silently',
        );
        for (final symbol in _topLevelDeclarations(
          _stripComments(module.readAsStringSync()),
        )) {
          declaredElsewhere[symbol] = relative;
        }
      }
      expect(
        declaredElsewhere.keys,
        contains('CommandNames'),
        reason: 'the allow-listed symbol must still exist',
      );
      expect(
        declaredElsewhere,
        isNotEmpty,
        reason: 'the declared-symbol scan must find something',
      );

      for (final file in sources) {
        // Comments are stripped first: this file's own prose legitimately
        // mentions type names like `Function`, and the threat-model text names
        // `Process`, so a raw text scan would flag documentation, not code.
        final text = _stripComments(file.readAsStringSync());
        // Any identifier, not just type-shaped ones: the reachable entry points in
        // those modules include lowercase top-level functions and constants
        // (`runStatus`, `approvedFrameworkSource`), which is exactly where a
        // git-spawning call would be pasted in.
        for (final match in RegExp(
          r'\b[A-Za-z_][A-Za-z0-9_]*\b',
        ).allMatches(text)) {
          final owner = declaredElsewhere[match.group(0)];
          if (owner == null) continue;
          expect(
            match.group(0),
            'CommandNames',
            reason:
                '${file.path} references ${match.group(0)} from '
                'src/$owner, which can spawn a subprocess. The checker may '
                'use CommandNames and nothing else from it.',
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

/// Counts how many times a scan was actually performed.
///
/// Substituted for [checkArtifacts] through the [ArtifactScanner] seam so a test
/// can assert that a refusal path reaches the scan *zero* times. A returned
/// message cannot prove this: a scan-then-discard implementation produces the
/// same refusal.
class _RecordingScanner {
  int invocations = 0;

  /// Performs the real scan and records that it happened.
  DriftReport call({
    required Directory artifactRoot,
    required Directory scanRoot,
  }) {
    invocations++;
    return checkArtifacts(artifactRoot: artifactRoot, scanRoot: scanRoot);
  }
}

/// Removes `//` and block comments from [source].
///
/// Line numbers are not preserved; these scans only look at identifier tokens,
/// so blanking the comment body is enough and far safer than a real lexer.
String _stripComments(String source) {
  final out = StringBuffer();
  var inBlock = false;
  for (final line in source.split('\n')) {
    var text = line;
    if (inBlock) {
      final end = text.indexOf('*/');
      if (end < 0) {
        text = '';
      } else {
        text = text.substring(end + 2);
        inBlock = false;
      }
    }
    final blockStart = text.indexOf('/*');
    if (blockStart >= 0) {
      final end = text.indexOf('*/', blockStart + 2);
      if (end < 0) {
        text = text.substring(0, blockStart);
        inBlock = true;
      } else {
        text = text.substring(0, blockStart) + text.substring(end + 2);
      }
    }
    final lineStart = text.indexOf('//');
    if (lineStart >= 0) text = text.substring(0, lineStart);
    out.writeln(text);
  }
  return out.toString();
}

/// Every public, top-level name declared in [source].
///
/// A deliberately coarse scan: the point is to learn which names the checker
/// could plausibly reach for in a module it imports transitively, not to build a
/// Dart parser. Anything declared at column 0 with a type-ish leading token
/// counts, which over-approximates — which is the safe direction for a guard.
Set<String> _topLevelDeclarations(String source) {
  // Language built-ins are shadowed into the scan by declaration lines like
  // `bool Function()? x`; they are reachable without an import, so they can
  // never be the thing this guard is about.
  const coreNames = <String>{
    'Function',
    'Future',
    'List',
    'Map',
    'Set',
    'Iterable',
    'Object',
    'String',
    'bool',
    'int',
    'double',
    'num',
    'Duration',
    'DateTime',
    'Uri',
    'RegExp',
    'Comparable',
    'Error',
    'Exception',
    'Enum',
    'Type',
  };
  final names = <String>{};
  // Private names are dropped: they are not reachable across libraries, so they
  // cannot be what the checker calls into. This also removes the return types
  // that appear on private helpers (`Directory _resolveFrameworkRoot()`).
  bool isPublic(String name) => !name.startsWith('_');
  for (final line in source.split('\n')) {
    final match = RegExp(
      r'^(?:abstract\s+|final\s+|base\s+|sealed\s+|mixin\s+)*'
      r'(?:class|enum|mixin|extension|typedef)\s+([A-Za-z_][A-Za-z0-9_]*)',
    ).firstMatch(line);
    if (match != null) {
      if (isPublic(match.group(1)!)) names.add(match.group(1)!);
      continue;
    }
    // Top-level functions and top-level constants/variables. Anchored at column
    // 0 by requiring the first token to start on the first character: an
    // indented `return Directory(...)` inside a function body is not a
    // declaration, and treating it as one would drag in dart:io type names.
    if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
      continue;
    }
    final value = RegExp(
      // Optional `const`/`final`/`late` modifier, a possibly-generic return
      // type, then the name. Without the modifier branch a declaration such as
      // `const String approvedFrameworkSource = …` would be missed, and the
      // guard would then under-report.
      r'^(?:(?:const|final|late)\s+)?'
      r'(?:Future<[^>]*>|[\w<>,?]+)\s+([a-zA-Z_][A-Za-z0-9_]*)\s*[(=]',
    ).firstMatch(line);
    if (value != null && isPublic(value.group(1)!)) {
      names.add(value.group(1)!);
    }
  }
  return names.difference(coreNames);
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
