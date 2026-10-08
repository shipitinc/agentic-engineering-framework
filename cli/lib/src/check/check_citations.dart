import 'dart:io';

import '../command_result.dart';
import '../commands.dart';
import '../manifest/path_safety.dart';
import '../result_family.dart';
import 'citation.dart';
import 'command_check.dart';
import 'markdown.dart';

/// Why this command never executes an artifact-embedded command.
///
/// This text is the machine-readable refusal reason, and the same statement is
/// reproduced in `--help`.
const String kExecutionRefusalReason =
    'executing-commands-is-not-implemented-by-design';

/// The threat model, as it appears in `--help` and in the refusal blocker.
const String kThreatModel =
    'Design artifacts are untrusted input: they are written by agents, they can be '
    'review-injected, and they can arrive from a fork. Therefore anything this '
    'command executes would be arbitrary code execution with this process\'s '
    'privileges. '
    'Citation checking is therefore pure (path and line resolution only; no '
    'subprocess is ever spawned). Command checking extracts and reports fenced '
    'commands with their claimed values and never runs them. '
    'A faithful re-run of a shell command line requires a shell interpreter on the '
    'artifact-controlled text (sh -c "..."), and an explicit working directory, a '
    'timeout and a scrubbed environment do not remove that primitive; nor can a '
    'timeout undo a side effect. Safe execution of arbitrary artifact-embedded '
    'commands is therefore not achievable here, so --execute-commands is refused '
    'rather than shipped.';

/// The scan half of [runCheckCitations], injectable so a caller can observe
/// whether a request ever reached the scan.
///
/// This exists for one reason: the "a refusal must short-circuit *before* the
/// scan" ordering is a safety requirement, and asserting it on the returned
/// message proves only that the returned refusal says nothing about a scan — an
/// implementation that scanned and threw the result away satisfies that. An
/// injectable seam lets a test assert the stronger, real property: the scanner
/// was never invoked.
///
/// It cannot make the command execute anything. The default is [checkArtifacts],
/// which has no execution primitive at all (see [kThreatModel]), and no CLI
/// flag can substitute a scanner — the seam is a library parameter only.
typedef ArtifactScanner =
    DriftReport Function({
      required Directory artifactRoot,
      required Directory scanRoot,
    });

/// Runs the citation and command drift check.
///
/// Read-only: reads the scanned artifacts and stats cited files, and never
/// writes, never mutates, and never spawns a subprocess.
///
/// [scanner] is the scan seam; see [ArtifactScanner]. It defaults to
/// [checkArtifacts] and is never substituted by any command-line path.
///
/// Returns [ResultFamily.commandComplete] (exit 0) when nothing drifted and
/// [ResultFamily.validationFailed] (exit 20) when any citation or command drift
/// was found, when the arguments were unusable, or when `--execute-commands` was
/// requested. Returns [ResultFamily.internalError] (exit 40) when some artifact
/// or cited file could not be read: the scan continues over everything that
/// *was* readable, but the verdict is then `indeterminate` rather than a
/// false `no drift`.
Future<CommandResult> runCheckCitations({
  String? dir,
  String? root,
  ArtifactScanner scanner = checkArtifacts,
}) async {
  if (dir == null || dir.trim().isEmpty) {
    return _usageFailure(
      'Missing required --dir: pass the directory of design artifacts to check.',
    );
  }

  final Directory artifactRoot;
  try {
    artifactRoot = Directory(dir).absolute;
  } on FileSystemException catch (error) {
    return _usageFailure('Invalid --dir "$dir": ${error.message}');
  }
  final normalizedArtifactRoot = Directory(
    normalizeFilesystemPath(artifactRoot.path),
  );
  if (_entityTypeOf(normalizedArtifactRoot) == FileSystemEntityType.notFound) {
    return _usageFailure(
      '--dir does not exist: ${normalizedArtifactRoot.path}',
    );
  }
  if (!_isDirectory(normalizedArtifactRoot)) {
    return _usageFailure(
      '--dir is not a directory: ${normalizedArtifactRoot.path}',
    );
  }

  final Directory scanRoot = root == null || root.trim().isEmpty
      ? Directory.current.absolute
      : Directory(root).absolute;
  final normalizedScanRoot = Directory(normalizeFilesystemPath(scanRoot.path));
  if (_entityTypeOf(normalizedScanRoot) == FileSystemEntityType.notFound) {
    return _usageFailure('--root does not exist: ${normalizedScanRoot.path}');
  }
  if (!_isInside(normalizedScanRoot, normalizedArtifactRoot)) {
    return _usageFailure(
      '--dir (${normalizedArtifactRoot.path}) is not inside --root '
      '(${normalizedScanRoot.path}). Citations are resolved against --root, so '
      'pass an explicit --root that contains the artifact directory.',
    );
  }

  final report = checkArtifacts(
    artifactRoot: normalizedArtifactRoot,
    scanRoot: normalizedScanRoot,
    scanner: scanner,
  );

  final skipCount =
      report.artifactsSkipped.length + report.citationUnverified.length;
  final driftCount = report.citationDrift.length + report.commandDrift.length;
  final message = StringBuffer()
    ..writeln(
      'Citation and command drift check '
      '(read-only; never executes artifact-embedded commands).',
    )
    ..writeln('root: ${normalizedScanRoot.path}')
    ..writeln('artifact_dir: ${normalizedArtifactRoot.path}')
    ..writeln('artifacts_scanned: ${report.artifactsScanned}')
    ..writeln('artifacts_skipped: ${report.artifactsSkipped.length}')
    ..writeln('citations_checked: ${report.citationsChecked}')
    ..writeln('citations_unverified: ${report.citationUnverified.length}')
    ..writeln('citation_drift: ${report.citationDrift.length}')
    ..writeln('commands_extracted: ${report.commands.length}')
    ..writeln('non_command_blocks: ${report.nonCommandBlocks}')
    ..writeln('unlabelled_blocks: ${report.unlabelledBlocks}')
    ..writeln('transcript_blocks: ${report.transcriptBlocks}')
    ..writeln('commands_executed: 0')
    ..writeln(
      'drift_found: ${driftCount == 0 ? (skipCount == 0 ? 'no' : 'indeterminate') : 'yes'}',
    );
  for (final command in report.commands) {
    message.writeln(command.toWireLine());
  }

  return CommandResult(
    // A skipped artifact makes the verdict `indeterminate`, so the result may
    // not claim success — nor reuse the drift category, which would blame the
    // caller's artifacts for a failure to read them. Exit 40 it is.
    family: skipCount > 0
        ? ResultFamily.internalError
        : driftCount == 0
        ? ResultFamily.commandComplete
        : ResultFamily.validationFailed,
    command: CommandNames.checkCitations,
    message: message.toString().trimRight(),
    blockers: <String>[
      // What could not be checked is reported first: it qualifies everything
      // below it, and a caller must not read the drift list without it.
      ...report.artifactsSkipped.map((skipped) => skipped.toWireLine()),
      ...report.citationUnverified.map((row) => row.toWireLine()),
      ...report.citationDrift.map((drift) => drift.toWireLine()),
      ...report.commandDrift,
    ],
  );
}

/// The result returned when `--execute-commands` is requested.
///
/// Not a stub and not a success: an explicit, machine-detectable refusal with
/// the threat model that justifies it. Exit category `PREFLIGHT_POLICY_FAILURE`
/// (20) — a validation refusal, not a not-implemented (50) code and not success.
CommandResult executionRefusedResult() {
  return CommandResult(
    family: ResultFamily.validationFailed,
    command: CommandNames.checkCitations,
    message:
        'Refused: $kExecutionRefusalReason. '
        'The command was not executed and no subprocess was spawned.',
    blockers: <String>[kThreatModel],
  );
}

CommandResult _usageFailure(String blocker) {
  return CommandResult(
    family: ResultFamily.validationFailed,
    command: CommandNames.checkCitations,
    message: 'Citation and command drift check could not run.',
    blockers: <String>[blocker],
  );
}

/// Everything one check run observed.
class DriftReport {
  DriftReport({
    required this.scanRoot,
    required this.artifactRoot,
    required this.artifactsScanned,
    required this.citationsChecked,
    required this.citationDrift,
    required this.citationUnverified,
    required this.commands,
    required this.commandDrift,
    required this.nonCommandBlocks,
    required this.unlabelledBlocks,
    required this.transcriptBlocks,
    required this.artifactsSkipped,
  });

  /// Absolute scan root citations are resolved against.
  final Directory scanRoot;

  /// Absolute artifact directory that was walked.
  final Directory artifactRoot;

  /// Number of Markdown artifacts read.
  final int artifactsScanned;

  /// Number of `path:line` citations resolved.
  final int citationsChecked;

  /// Citation drift found, in artifact then line order.
  final List<ResolvedCitationDrift> citationDrift;

  /// Citations whose target file could not be read, in artifact then line order.
  final List<ResolvedCitationUnverified> citationUnverified;

  /// Every runnable command extracted, never executed.
  final List<ExtractedCommand> commands;

  /// Command drift found, in artifact then line order.
  final List<String> commandDrift;

  /// Fenced blocks tagged with a non-command language.
  final int nonCommandBlocks;

  /// Fenced blocks with no language tag.
  final int unlabelledBlocks;

  /// Shell-tagged fenced blocks identified as terminal transcripts.
  final int transcriptBlocks;

  /// Artifacts and directories that could not be read, in walk order.
  ///
  /// Non-empty means the scan is incomplete; the run then reports
  /// `drift_found: indeterminate` and exits 40 rather than claiming a verdict
  /// it could not establish.
  final List<ArtifactSkipped> artifactsSkipped;

  /// Total number of findings.
  int get driftCount => citationDrift.length + commandDrift.length;
}

/// Why a part of the artifact tree could not be checked.
enum ArtifactSkipClass {
  /// An artifact file exists but could not be read as UTF-8 text — a binary
  /// blob or an image named `*.md`, or a file this process may not read.
  unreadable('UNREADABLE'),

  /// A directory below the artifact root could not be listed. Its contents are
  /// unknown; every sibling that could be listed was still scanned.
  unlistable('UNLISTABLE');

  const ArtifactSkipClass(this.wireName);

  /// Stable identifier emitted in machine-readable output.
  final String wireName;
}

/// An artifact (or a directory of artifacts) that was skipped, never silently.
///
/// Design artifacts are untrusted input, so "I could not read this" is a
/// routine outcome rather than an exceptional one. It is reported as a first
/// class row instead of being swallowed, because a silently dropped artifact
/// would otherwise turn into a false `drift_found: no`.
class ArtifactSkipped {
  const ArtifactSkipped({
    required this.skipClass,
    required this.relativePath,
    required this.detail,
  });

  /// Why the artifact or directory was skipped.
  final ArtifactSkipClass skipClass;

  /// POSIX path of the artifact or directory, **relative to the scan root** —
  /// the same base every other `artifact=` in the report uses, so one `--root`
  /// resolves them all. `.` is the scan root itself.
  ///
  /// This used to be relative to the *artifact* root for [ArtifactSkipClass.unlistable]
  /// and to the scan root for [ArtifactSkipClass.unreadable], so the same run
  /// emitted two bases for one key and a caller resolving uniformly against
  /// `--root` mis-resolved every `UNLISTABLE` row. One base, always the scan
  /// root: `--help` prints `root:` in the same report, and it is the base the
  /// citation and command rows were already using.
  final String relativePath;

  /// A human-readable explanation, free of spaces.
  final String detail;

  /// Deterministic, machine-parseable single-line rendering.
  ///
  /// Format:
  /// `ARTIFACT_SKIPPED <CLASS> artifact=<relPath> detail=<text>`
  String toWireLine() =>
      'ARTIFACT_SKIPPED ${skipClass.wireName} '
      'artifact=$relativePath detail=$detail';
}

/// A citation drift bound to the artifact it was found in.
class ResolvedCitationDrift {
  const ResolvedCitationDrift({required this.artifact, required this.drift});

  /// POSIX path of the artifact, relative to the scan root.
  final String artifact;

  /// The drift itself.
  final CitationDrift drift;

  /// Deterministic, machine-parseable single-line rendering.
  String toWireLine() => drift.toWireLine(artifact);
}

/// An unverified citation bound to the artifact it was found in.
class ResolvedCitationUnverified {
  const ResolvedCitationUnverified({
    required this.artifact,
    required this.unverified,
  });

  /// POSIX path of the artifact, relative to the scan root.
  final String artifact;

  /// The unverified citation itself.
  final CitationUnverified unverified;

  /// Deterministic, machine-parseable single-line rendering.
  String toWireLine() => unverified.toWireLine(artifact);
}

/// Walks [artifactRoot] and performs both drift classes.
///
/// Pure with respect to subprocesses: the only I/O is reading the artifacts and
/// statting/reading cited files.
///
/// Robust with respect to unreadable input: a file or directory that cannot be
/// read is recorded in [DriftReport.artifactsSkipped] and the scan continues,
/// because a design artifact tree is untrusted input and one unreadable file
/// must not suppress every other finding.
///
/// [scanner] is accepted only so [runCheckCitations] can hand in its seam; the
/// function itself always performs the walk below.
DriftReport checkArtifacts({
  required Directory artifactRoot,
  required Directory scanRoot,
  ArtifactScanner? scanner,
}) {
  if (scanner != null && !identical(scanner, checkArtifacts)) {
    return scanner(artifactRoot: artifactRoot, scanRoot: scanRoot);
  }
  final listing = _listArtifacts(artifactRoot);
  final artifactPaths = listing.files;
  final citationDrift = <ResolvedCitationDrift>[];
  final citationUnverified = <ResolvedCitationUnverified>[];
  final commands = <ExtractedCommand>[];
  final commandDrift = <String>[];
  final artifactsSkipped = <ArtifactSkipped>[
    // Rebased onto the scan root here rather than in the walk: the walk itself
    // needs artifact-root-relative paths to decide what is scannable and which
    // nested directories to prune, so only the *reported* path moves base.
    for (final directory in listing.unlistable)
      ArtifactSkipped(
        skipClass: ArtifactSkipClass.unlistable,
        relativePath: _scanRelativeTo(scanRoot, directory),
        detail: 'directory-could-not-be-listed-contents-unchecked',
      ),
  ];
  var citationsChecked = 0;
  var nonCommandBlocks = 0;
  var unlabelledBlocks = 0;
  var transcriptBlocks = 0;

  for (final artifactPath in artifactPaths) {
    final artifactFromRoot = _relativeTo(scanRoot, artifactPath);
    // Self-reference compares a command's scope token, which is resolved
    // against the scan root, with the artifact's own directory — so both sides
    // must be expressed relative to the same base. `artifactDirRelative` is
    // already root-relative, so the directory is rebuilt from the *scan root*,
    // never from `artifactRoot` (which would append the segment twice).
    final artifactDirRelative = _dirNameOf(artifactFromRoot);
    final resolver = CitationResolver(
      root: scanRoot,
      artifactDir: Directory(
        '${normalizeFilesystemPath(scanRoot.path)}/$artifactDirRelative',
      ),
    );

    // Guarded, following the CLI's existing idiom. An artifact is untrusted
    // input: a binary blob or an image named `*.md`, a UTF-16 file, or a file
    // this process cannot read must not throw out of the whole run. Skipping
    // it keeps the rest of the report, and the skip is reported, never dropped.
    final String content;
    try {
      content = artifactPath.readAsStringSync();
    } on FileSystemException {
      artifactsSkipped.add(
        ArtifactSkipped(
          skipClass: ArtifactSkipClass.unreadable,
          relativePath: artifactFromRoot,
          detail: 'artifact-could-not-be-read-as-utf8-text',
        ),
      );
      continue;
    }

    for (final citation in citationsIn(content)) {
      citationsChecked++;
      final checked = _checkCitation(citation, resolver);
      for (final drift in checked.drift) {
        citationDrift.add(
          ResolvedCitationDrift(artifact: artifactFromRoot, drift: drift),
        );
      }
      if (checked.unverified != null) {
        citationUnverified.add(
          ResolvedCitationUnverified(
            artifact: artifactFromRoot,
            unverified: checked.unverified!,
          ),
        );
      }
    }

    for (final extraction in extractBlocks(artifactFromRoot, content)) {
      switch (extraction.classification) {
        case BlockClassification.nonCommand:
          nonCommandBlocks++;
        case BlockClassification.unlabelled:
          unlabelledBlocks++;
        case BlockClassification.transcript:
          transcriptBlocks++;
        case BlockClassification.command:
          break;
      }
      if (!extraction.isCommand) continue;

      final drifts = _checkCommand(extraction, artifactDirRelative, resolver);
      commands.add(
        ExtractedCommand(
          artifactPath: artifactFromRoot,
          classification: extraction.classification,
          block: extraction.block,
          claimedValue: extraction.claimedValue,
          claimedRevision: extraction.claimedRevision,
          drift: drifts,
        ),
      );
      commandDrift.addAll(
        drifts.map((drift) => drift.toWireLine(extraction.block.flatText)),
      );
    }
  }

  return DriftReport(
    scanRoot: scanRoot,
    artifactRoot: artifactRoot,
    artifactsScanned: artifactPaths.length,
    citationsChecked: citationsChecked,
    citationDrift: citationDrift,
    citationUnverified: citationUnverified,
    commands: commands,
    commandDrift: commandDrift,
    nonCommandBlocks: nonCommandBlocks,
    unlabelledBlocks: unlabelledBlocks,
    transcriptBlocks: transcriptBlocks,
    artifactsSkipped: artifactsSkipped,
  );
}

/// What checking one citation established.
class CitationCheckResult {
  const CitationCheckResult({
    this.drift = const <CitationDrift>[],
    this.unverified,
  });

  /// Drift proven for this citation; empty when clean or merely unverifiable.
  final List<CitationDrift> drift;

  /// Set when the cited file could not be read, so the citation's line bound
  /// could not be checked. Reported *in addition to* [drift], never instead of
  /// it: an unreadable file must not hide a structural finding such as an
  /// inverted range, and must not hide itself either.
  final CitationUnverified? unverified;
}

CitationCheckResult _checkCitation(
  Citation citation,
  CitationResolver resolver,
) {
  final File? file;
  try {
    file = resolver.resolve(citation.rawPath);
  } on PathSafetyException catch (error) {
    return CitationCheckResult(
      drift: <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.outsideRoot,
          citation: citation,
          detail: error.reason,
        ),
      ],
    );
  }
  if (file == null) {
    return CitationCheckResult(
      drift: <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.unresolvedPath,
          citation: citation,
          detail: 'path-does-not-exist-under-root',
        ),
      ],
    );
  }

  // A null line count means the cited file exists but is unreadable (binary or
  // non-UTF-8 content, or no read permission). Every check that needs the line
  // count is then skipped; every check that does not, still runs.
  final lineCount = resolver.lineCountOf(file);
  final unverified = lineCount == null
      ? CitationUnverified(
          citation: citation,
          detail: 'cited-file-could-not-be-read-as-utf8-text',
        )
      : null;

  if (!citation.isRange) {
    if (citation.start < 1) {
      return CitationCheckResult(
        drift: <CitationDrift>[
          CitationDrift(
            driftClass: CitationDriftClass.lineNotPositive,
            citation: citation,
            detail: 'line-0-is-not-a-line',
          ),
        ],
        unverified: unverified,
      );
    }
    if (lineCount != null && citation.start > lineCount) {
      return CitationCheckResult(
        drift: <CitationDrift>[
          CitationDrift(
            driftClass: CitationDriftClass.lineBeyondEof,
            citation: citation,
            detail: 'file-has-$lineCount-line(s)',
          ),
        ],
        unverified: unverified,
      );
    }
    return CitationCheckResult(unverified: unverified);
  }

  final end = citation.end!;
  if (citation.start > end) {
    return CitationCheckResult(
      drift: <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.invertedRange,
          citation: citation,
          detail: 'start-${citation.start}-is-after-end-$end',
        ),
      ],
      unverified: unverified,
    );
  }
  if (citation.start < 1 || end < 1) {
    return CitationCheckResult(
      drift: <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.lineNotPositive,
          citation: citation,
          detail: 'range-must-start-at-or-after-line-1',
        ),
      ],
      unverified: unverified,
    );
  }
  if (lineCount != null && (citation.start > lineCount || end > lineCount)) {
    return CitationCheckResult(
      drift: <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.rangeBeyondEof,
          citation: citation,
          detail: 'file-has-$lineCount-line(s)',
        ),
      ],
      unverified: unverified,
    );
  }
  return CitationCheckResult(unverified: unverified);
}

List<CommandDrift> _checkCommand(
  BlockExtraction extraction,
  String artifactDirRelative,
  CitationResolver resolver,
) {
  final drifts = <CommandDrift>[];
  final seen = <String>{};
  for (final rawLine in extraction.block.body) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    for (final token in scopeTokens(line)) {
      if (selfReferences(token, artifactDirRelative)) {
        final key = '${CommandDriftClass.selfReferencingScope.wireName}|$token';
        if (seen.add(key)) {
          drifts.add(
            CommandDrift(
              driftClass: CommandDriftClass.selfReferencingScope,
              artifactPath: extraction.artifactPath,
              line: extraction.block.reportLine,
              scope: token,
              detail: 'scope-includes-this-artifact-counts-its-own-row',
            ),
          );
        }
        continue;
      }
      if (!isRepositoryPath(token, resolver)) continue;
      if (resolver.pathExists(token)) continue;
      final key = '${CommandDriftClass.missingScopePath.wireName}|$token';
      if (seen.add(key)) {
        drifts.add(
          CommandDrift(
            driftClass: CommandDriftClass.missingScopePath,
            artifactPath: extraction.artifactPath,
            line: extraction.block.reportLine,
            scope: token,
            detail: 'path-does-not-exist-under-root',
          ),
        );
      }
    }
  }
  return drifts;
}

/// The scannable artifacts under [root], plus any directory that could not be
/// listed.
///
/// Walks one directory at a time rather than with a single
/// `listSync(recursive: true)`: a recursive listing is all-or-nothing, so one
/// unreadable subdirectory would take the entire report down with it — the very
/// suppression the per-artifact rows exist to prevent. Listing per directory and
/// catching per directory keeps a bad directory from hiding its readable
/// siblings.
_ArtifactListing _listArtifacts(Directory root) {
  final files = <File>[];
  final unlistable = <Directory>[];
  if (!root.existsSync()) {
    return _ArtifactListing(files: files, unlistable: unlistable);
  }
  _walkArtifactTree(root, root, files, unlistable);
  files.sort((a, b) => _relativeTo(root, a).compareTo(_relativeTo(root, b)));
  return _ArtifactListing(files: files, unlistable: unlistable);
}

void _walkArtifactTree(
  Directory root,
  Directory directory,
  List<File> files,
  List<Directory> unlistable,
) {
  final List<FileSystemEntity> entries;
  try {
    entries = directory.listSync(followLinks: false);
  } on FileSystemException {
    // Guarded, following the CLI's existing idiom. Recorded and stepped over:
    // the rest of the tree is still scanned.
    unlistable.add(directory);
    return;
  }
  for (final entity in entries) {
    // `followLinks: false` means a symlink is a `Link`, never a `File` or a
    // `Directory`, so links are skipped here exactly as the recursive listing
    // skipped them: this walk follows no symlink and loops through none.
    if (entity is File) {
      if (isScannableArtifact(_relativeTo(root, entity))) files.add(entity);
    } else if (entity is Directory) {
      // A nested dot-directory can hold no scannable artifact (see
      // [isScannableArtifact]), so it is pruned here instead of being listed
      // and filtered afterwards. The walk's own starting directory is exempt,
      // which is what keeps `--dir .claude` working.
      if (_baseNameOf(entity).startsWith('.')) continue;
      _walkArtifactTree(root, entity, files, unlistable);
    }
  }
}

/// The scannable files and the directories that could not be listed.
class _ArtifactListing {
  const _ArtifactListing({required this.files, required this.unlistable});

  /// Scannable artifacts, sorted by relative path.
  final List<File> files;

  /// The directories that could not be listed, as the directories themselves:
  /// they are rebased onto the scan root when the skip row is rendered, so the
  /// walk never has to know which base the report uses.
  final List<Directory> unlistable;
}

String _pathRelativeTo(Directory root, String path) {
  final rootPath = normalizeFilesystemPath(root.path);
  var candidate = normalizeFilesystemPath(path);
  if (candidate.startsWith('$rootPath/')) {
    candidate = candidate.substring(rootPath.length + 1);
  }
  return candidate;
}

String _relativeTo(Directory root, File file) =>
    _pathRelativeTo(root, file.path);

/// [directory] as a POSIX path relative to the scan root, `.` for the root
/// itself.
///
/// The single base for every `artifact=` in the report.
String _scanRelativeTo(Directory root, Directory directory) {
  final candidate = normalizeFilesystemPath(directory.path);
  if (candidate == normalizeFilesystemPath(root.path)) return '.';
  return _pathRelativeTo(root, candidate);
}

/// The last path segment of [directory], as a POSIX name.
String _baseNameOf(Directory directory) =>
    normalizeFilesystemPath(directory.path).split('/').last;

/// The directory part of [relativePath], using `.` for a top-level path.
String _dirNameOf(String relativePath) {
  final index = relativePath.lastIndexOf('/');
  return index < 0 ? '.' : relativePath.substring(0, index);
}

/// The filesystem entity type of [directory].
///
/// Uses [FileSystemEntity.typeSync] rather than `Directory.existsSync`, because
/// `existsSync` answers "does a *directory* exist here" — it reports `false` for
/// a regular file, which would make an "is not a directory" diagnostic
/// unreachable and report a wrong reason for an existing file.
FileSystemEntityType _entityTypeOf(Directory directory) =>
    FileSystemEntity.typeSync(directory.path);

bool _isDirectory(Directory directory) =>
    _entityTypeOf(directory) == FileSystemEntityType.directory;

bool _isInside(Directory root, Directory candidate) {
  final rootPath = normalizeFilesystemPath(root.path);
  final candidatePath = normalizeFilesystemPath(candidate.path);
  return candidatePath == rootPath || candidatePath.startsWith('$rootPath/');
}
