import 'dart:io';

import '../manifest/path_safety.dart';

/// File extensions a `path:line` citation may point at.
///
/// Deliberately limited to text sources a design artifact can meaningfully cite
/// (implementation source, configuration, and documentation). Widening it raises
/// the false-positive rate on binary/asset names without adding real coverage.
const List<String> kCitableExtensions = <String>[
  'dart',
  'yaml',
  'yml',
  'json',
  'md',
  'txt',
  'toml',
  'lock',
];

/// Matches a `path:line` / `path:start-end` citation.
///
/// The lookbehind rejects any match whose first character would continue a longer
/// path or URL, which is what keeps `https://host/a.md:3` and `github.com:o/r.md:3`
/// out of the citation set, while `` `docs/a.md:3` ``, `(cli/a.dart:1)` and
/// `-> cli/a.dart:1-4` still match. A leading `/` is accepted so that an absolute
/// citation is reported as [CitationDriftClass.outsideRoot] rather than silently
/// skipped; a leading `.` is not accepted, which additionally keeps the
/// regex-inside-a-command self-reference case (`.dart:3` inside a quoted `grep`
/// pattern) and `./relative.md:3` out of the citation set. Both limits are stated
/// in `--help` rather than left implicit.
final RegExp _citationPattern = RegExp(
  r'(?<![A-Za-z0-9_/.:\-])'
  r'([A-Za-z0-9_/][A-Za-z0-9_/\-.]*\.(?:dart|yaml|yml|json|md|txt|toml|lock))'
  r':(\d+)(?:-(\d+))?',
);

/// Classes of citation drift reported by the citation checker.
///
/// Every class is a distinct, deterministic outcome; none of them overlaps a
/// not-implemented or tool-failure outcome.
enum CitationDriftClass {
  /// The cited path does not exist under the scan root.
  unresolvedPath('UNRESOLVED_PATH'),

  /// The cited path is absolute or contains a parent-directory segment, so it
  /// is not verifiable against the scanned working tree (ADR 0002 mitigation 16).
  outsideRoot('OUTSIDE_ROOT'),

  /// A single cited line is past the end of the file.
  lineBeyondEof('LINE_BEYOND_EOF'),

  /// A cited line (or range endpoint) is below the first line of the file.
  lineNotPositive('LINE_NOT_POSITIVE'),

  /// A cited range has its start after its end.
  invertedRange('INVERTED_RANGE'),

  /// A cited range endpoint lies outside the cited file.
  rangeBeyondEof('RANGE_BEYOND_EOF');

  const CitationDriftClass(this.wireName);

  /// Stable identifier emitted in machine-readable output.
  final String wireName;
}

/// A citation that could not be checked because its target file was unreadable.
///
/// This is a *visibility* finding, not a drift class: it says "nothing is known
/// about this citation", where every [CitationDriftClass] says "this is known
/// to be wrong". The two are kept distinct so a caller can never mistake an
/// unreadable file for a verified verdict — and so an unreadable file can never
/// silently vanish from the report.
class CitationUnverified {
  const CitationUnverified({required this.citation, required this.detail});

  /// The citation that could not be checked.
  final Citation citation;

  /// A human-readable explanation, free of spaces.
  final String detail;

  /// Deterministic, machine-parseable single-line rendering.
  ///
  /// Format:
  /// `CITATION_UNVERIFIED artifact=<relPath> at=<line> path=<citedPath> claimed_line=<n> claimed_end=<n|-> detail=<text>`
  ///
  /// Same space-free `key=value` shape as [CitationDrift.toWireLine], and for
  /// the same reason: a `path:line` label here would re-enter as a fresh
  /// citation if this report were published into the artifact set.
  String toWireLine(String artifactPath) {
    return 'CITATION_UNVERIFIED '
        'artifact=$artifactPath at=${citation.line} '
        'path=${citation.rawPath} '
        'claimed_line=${citation.start} claimed_end=${citation.end ?? '-'} '
        'detail=$detail';
  }
}

/// One `path:line` / `path:start-end` occurrence found in an artifact.
class Citation {
  const Citation({
    required this.rawPath,
    required this.start,
    required this.end,
    required this.line,
    required this.column,
  });

  /// The cited path exactly as written in the artifact.
  final String rawPath;

  /// First cited line (1-based).
  final int start;

  /// Last cited line (1-based), or null for a single-line citation.
  final int? end;

  /// 1-based line of the artifact on which this citation was found.
  final int line;

  /// 0-based column of the citation within that artifact line.
  final int column;

  /// Whether this citation is a `start-end` range.
  bool get isRange => end != null;

  /// The citation as written, e.g. `cli/a.dart:3` or `cli/a.dart:3-9`.
  String get label => isRange ? '$rawPath:$start-$end' : '$rawPath:$start';
}

/// A resolved citation that no longer matches the working tree.
class CitationDrift {
  const CitationDrift({
    required this.driftClass,
    required this.citation,
    required this.detail,
  });

  /// The class of drift detected.
  final CitationDriftClass driftClass;

  /// The citation that drifted.
  final Citation citation;

  /// A human-readable explanation, free of spaces in the key/value prefix.
  final String detail;

  /// Deterministic, machine-parseable single-line rendering.
  ///
  /// Format:
  /// `CITATION_DRIFT <CLASS> artifact=<relPath> at=<line> path=<citedPath> claimed_line=<n> claimed_end=<n|-> detail=<text>`
  ///
  /// Every `key=value` pair is space-free so a consumer can tokenize the line up
  /// to `detail=`; the two renderings the CLI emits (human and `--json`) both
  /// carry this exact string, so they can never disagree.
  ///
  /// The cited line and endpoint are emitted as two separate space-free fields
  /// rather than as a re-assembled `path:line` label. That is what makes the
  /// report **idempotent under its own reporting**: a `path:line` label would be
  /// itself a citation, so publishing this report into the artifact set would
  /// manufacture a fresh citation for the checker to find — the reporter's
  /// measured lesson, reproduced inside this command's own output. A test asserts
  /// that no rendered finding is a citation.
  String toWireLine(String artifactPath) {
    return 'CITATION_DRIFT ${driftClass.wireName} '
        'artifact=$artifactPath at=${citation.line} '
        'path=${citation.rawPath} '
        'claimed_line=${citation.start} claimed_end=${citation.end ?? '-'} '
        'detail=$detail';
  }
}

/// Extracts every citation from [content] in document order.
///
/// Pure: no filesystem access, no subprocess.
List<Citation> citationsIn(String content) {
  final lines = content.split('\n');
  final found = <Citation>[];
  for (var index = 0; index < lines.length; index++) {
    for (final match in _citationPattern.allMatches(lines[index])) {
      found.add(
        Citation(
          rawPath: match.group(1)!,
          start: int.parse(match.group(2)!),
          end: match.group(3) == null ? null : int.parse(match.group(3)!),
          line: index + 1,
          column: match.start,
        ),
      );
    }
  }
  return found;
}

/// Counts the lines of [content] the way an editor does.
///
/// A trailing newline terminates the last line rather than starting a new one,
/// so `"a\nb\nc\n"` is 3 lines and an empty file is 0 lines. Pure.
int countLines(String content) {
  if (content.isEmpty) return 0;
  final body = content.endsWith('\n')
      ? content.substring(0, content.length - 1)
      : content;
  return '\n'.allMatches(body).length + 1;
}

/// Resolves citation paths against a scanned working tree.
///
/// Resolution is **pure**: it only stats and reads files. It never spawns a
/// subprocess, so citation checking cannot be turned into command execution by
/// any artifact content.
class CitationResolver {
  CitationResolver({required Directory root, required Directory artifactDir})
    : _rootPath = normalizeFilesystemPath(root.absolute.path),
      _bases = _resolutionBases(root, artifactDir);

  final String _rootPath;

  /// Search bases in deterministic order: the scan root first (repo-relative
  /// citations are the dominant form), then the artifact's own directory and
  /// each of its ancestors up to the scan root.
  final List<Directory> _bases;

  /// Memoizes successes *and* failures, so a file cited a hundred times is
  /// read (or refused) once.
  final Map<String, int?> _lineCounts = <String, int?>{};

  /// The normalized POSIX path of the scan root.
  String get rootPath => _rootPath;

  /// The bases searched, in order.
  List<String> get searchBases =>
      _bases.map((base) => normalizeFilesystemPath(base.path)).toList();

  /// Resolves [rawPath] to an existing file, or null when it does not exist.
  ///
  /// Throws [PathSafetyException] when [rawPath] is absolute or contains a
  /// parent-directory segment; those are reported as
  /// [CitationDriftClass.outsideRoot] by the caller.
  File? resolve(String rawPath) {
    final normalized = normalizeManagedPath(rawPath);
    for (final base in _bases) {
      final candidate = File(
        '${normalizeFilesystemPath(base.path)}/$normalized',
      );
      if (_insideRoot(candidate.path) &&
          FileSystemEntity.typeSync(candidate.path) ==
              FileSystemEntityType.file) {
        return candidate;
      }
    }
    return null;
  }

  /// Whether [path] is a repo-relative path that exists (file or directory)
  /// under the scan root or any resolution base.
  bool pathExists(String relPath) {
    String normalized;
    try {
      normalized = normalizeManagedPath(relPath);
    } on PathSafetyException {
      return false;
    }
    for (final base in _bases) {
      final candidate = Directory(
        '${normalizeFilesystemPath(base.path)}/$normalized',
      );
      if (_insideRoot(candidate.path) && candidate.existsSync()) {
        return true;
      }
      final asFile = File(candidate.path);
      if (_insideRoot(asFile.path) && asFile.existsSync()) {
        return true;
      }
    }
    return false;
  }

  /// Number of lines in [file], memoized per absolute path.
  ///
  /// Returns null when [file] exists but could not be read: its bytes are not
  /// valid UTF-8, or this process may not read it. A cited file is repository
  /// content rather than trusted input, so an unreadable file is a *skip*, not
  /// a reason to abandon the run — inventing a line count for it would
  /// manufacture a false `LINE_BEYOND_EOF`. The caller reports the citation as
  /// unverified instead, and the failure is memoized so one unreadable file
  /// cannot abort the scan or be re-read for every citation.
  int? lineCountOf(File file) {
    final key = normalizeFilesystemPath(file.path);
    if (_lineCounts.containsKey(key)) return _lineCounts[key];
    int? count;
    try {
      count = countLines(file.readAsStringSync());
    } on FileSystemException {
      count = null;
    }
    _lineCounts[key] = count;
    return count;
  }

  bool _insideRoot(String absolutePath) {
    final normalized = normalizeFilesystemPath(absolutePath);
    return normalized == _rootPath || normalized.startsWith('$_rootPath/');
  }

  static List<Directory> _resolutionBases(
    Directory root,
    Directory artifactDir,
  ) {
    final bases = <Directory>[root];
    final rootPath = normalizeFilesystemPath(root.path);
    var cursor = Directory(normalizeFilesystemPath(artifactDir.path));
    while (true) {
      final cursorPath = normalizeFilesystemPath(cursor.path);
      if (!bases.any(
        (base) => normalizeFilesystemPath(base.path) == cursorPath,
      )) {
        bases.add(cursor);
      }
      if (cursorPath == rootPath) break;
      final parentPath = normalizeFilesystemPath(cursor.parent.path);
      if (parentPath == cursorPath) break;
      if (parentPath != rootPath && !parentPath.startsWith('$rootPath/')) break;
      cursor = Directory(parentPath);
    }
    return bases;
  }
}

/// Normalizes a path by collapsing `.` and `..` segments.
///
/// Absoluteness is preserved: an absolute input stays absolute and a relative
/// input stays relative, so a caller-supplied `--dir ../artifacts` is not turned
/// into a root-relative path. A leading `..` that cannot be collapsed is kept
/// for relative inputs and dropped for absolute ones, matching the platform's
/// own resolution. Used for containment comparison against the scan root and for
/// the paths this command prints — never to write.
String normalizeFilesystemPath(String path) {
  final unified = path.replaceAll('\\', '/');
  final isAbsolute = unified.startsWith('/');
  final segments = <String>[];
  for (final segment in unified.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty && segments.last != '..') {
        segments.removeLast();
      } else if (!isAbsolute) {
        segments.add('..');
      }
      continue;
    }
    segments.add(segment);
  }
  return isAbsolute ? '/${segments.join('/')}' : segments.join('/');
}
