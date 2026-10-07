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

/// Runs the citation and command drift check.
///
/// Read-only: reads the scanned artifacts and stats cited files, and never
/// writes, never mutates, and never spawns a subprocess.
///
/// Returns [ResultFamily.commandComplete] (exit 0) when nothing drifted and
/// [ResultFamily.validationFailed] (exit 20) when any citation or command drift
/// was found, when the arguments were unusable, or when `--execute-commands` was
/// requested.
Future<CommandResult> runCheckCitations({String? dir, String? root}) async {
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
  );

  final driftCount = report.citationDrift.length + report.commandDrift.length;
  final message = StringBuffer()
    ..writeln(
      'Citation and command drift check '
      '(read-only; never executes artifact-embedded commands).',
    )
    ..writeln('root: ${normalizedScanRoot.path}')
    ..writeln('artifact_dir: ${normalizedArtifactRoot.path}')
    ..writeln('artifacts_scanned: ${report.artifactsScanned}')
    ..writeln('citations_checked: ${report.citationsChecked}')
    ..writeln('citation_drift: ${report.citationDrift.length}')
    ..writeln('commands_extracted: ${report.commands.length}')
    ..writeln('non_command_blocks: ${report.nonCommandBlocks}')
    ..writeln('unlabelled_blocks: ${report.unlabelledBlocks}')
    ..writeln('transcript_blocks: ${report.transcriptBlocks}')
    ..writeln('commands_executed: 0')
    ..writeln('drift_found: ${driftCount == 0 ? 'no' : 'yes'}');
  for (final command in report.commands) {
    message.writeln(command.toWireLine());
  }

  return CommandResult(
    family: driftCount == 0
        ? ResultFamily.commandComplete
        : ResultFamily.validationFailed,
    command: CommandNames.checkCitations,
    message: message.toString().trimRight(),
    blockers: <String>[
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
    required this.commands,
    required this.commandDrift,
    required this.nonCommandBlocks,
    required this.unlabelledBlocks,
    required this.transcriptBlocks,
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

  /// Total number of findings.
  int get driftCount => citationDrift.length + commandDrift.length;
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

/// Walks [artifactRoot] and performs both drift classes.
///
/// Pure with respect to subprocesses: the only I/O is reading the artifacts and
/// statting/reading cited files.
DriftReport checkArtifacts({
  required Directory artifactRoot,
  required Directory scanRoot,
}) {
  final artifactPaths = _listArtifacts(artifactRoot);
  final citationDrift = <ResolvedCitationDrift>[];
  final commands = <ExtractedCommand>[];
  final commandDrift = <String>[];
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
    final content = artifactPath.readAsStringSync();

    for (final citation in citationsIn(content)) {
      citationsChecked++;
      for (final drift in _checkCitation(citation, resolver)) {
        citationDrift.add(
          ResolvedCitationDrift(artifact: artifactFromRoot, drift: drift),
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
    commands: commands,
    commandDrift: commandDrift,
    nonCommandBlocks: nonCommandBlocks,
    unlabelledBlocks: unlabelledBlocks,
    transcriptBlocks: transcriptBlocks,
  );
}

List<CitationDrift> _checkCitation(
  Citation citation,
  CitationResolver resolver,
) {
  final File? file;
  try {
    file = resolver.resolve(citation.rawPath);
  } on PathSafetyException catch (error) {
    return <CitationDrift>[
      CitationDrift(
        driftClass: CitationDriftClass.outsideRoot,
        citation: citation,
        detail: error.reason,
      ),
    ];
  }
  if (file == null) {
    return <CitationDrift>[
      CitationDrift(
        driftClass: CitationDriftClass.unresolvedPath,
        citation: citation,
        detail: 'path-does-not-exist-under-root',
      ),
    ];
  }

  final lineCount = resolver.lineCountOf(file);
  if (!citation.isRange) {
    if (citation.start < 1) {
      return <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.lineNotPositive,
          citation: citation,
          detail: 'line-0-is-not-a-line',
        ),
      ];
    }
    if (citation.start > lineCount) {
      return <CitationDrift>[
        CitationDrift(
          driftClass: CitationDriftClass.lineBeyondEof,
          citation: citation,
          detail: 'file-has-$lineCount-line(s)',
        ),
      ];
    }
    return const <CitationDrift>[];
  }

  final end = citation.end!;
  if (citation.start > end) {
    return <CitationDrift>[
      CitationDrift(
        driftClass: CitationDriftClass.invertedRange,
        citation: citation,
        detail: 'start-${citation.start}-is-after-end-$end',
      ),
    ];
  }
  if (citation.start < 1 || end < 1) {
    return <CitationDrift>[
      CitationDrift(
        driftClass: CitationDriftClass.lineNotPositive,
        citation: citation,
        detail: 'range-must-start-at-or-after-line-1',
      ),
    ];
  }
  if (citation.start > lineCount || end > lineCount) {
    return <CitationDrift>[
      CitationDrift(
        driftClass: CitationDriftClass.rangeBeyondEof,
        citation: citation,
        detail: 'file-has-$lineCount-line(s)',
      ),
    ];
  }
  return const <CitationDrift>[];
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

List<File> _listArtifacts(Directory root) {
  if (!root.existsSync()) return const <File>[];
  final files = <File>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = _relativeTo(root, entity);
    if (isScannableArtifact(relative)) files.add(entity);
  }
  files.sort((a, b) => _relativeTo(root, a).compareTo(_relativeTo(root, b)));
  return files;
}

String _relativeTo(Directory root, File file) {
  final rootPath = normalizeFilesystemPath(root.path);
  var filePath = normalizeFilesystemPath(file.path);
  if (filePath.startsWith('$rootPath/')) {
    filePath = filePath.substring(rootPath.length + 1);
  }
  return filePath;
}

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
