/// A fenced code block found in a Markdown artifact.
class FencedBlock {
  const FencedBlock({
    required this.language,
    required this.startLine,
    required this.endLine,
    required this.body,
  });

  /// Normalized (lowercased, first word only) info string of the opening fence.
  ///
  /// The empty string when the fence carries no language tag.
  final String language;

  /// 1-based line number of the opening fence line.
  final int startLine;

  /// 1-based line number of the closing fence line, or of the artifact's last
  /// line when the block is never closed.
  final int endLine;

  /// Body lines, excluding both fence lines.
  final List<String> body;

  /// The body collapsed to a single whitespace-normalized line, for reporting.
  String get flatText => body
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ');

  /// The line reported as the block's location: the first body line when the
  /// block has one, otherwise the opening fence.
  int get reportLine => body.isEmpty ? startLine : startLine + 1;
}

/// Matches an opening or closing backtick/tilde fence.
///
/// Groups: `marker` (the run of fence characters) and `info` (everything after).
final RegExp _fencePattern = RegExp(
  r'^[ \t]*(?<marker>`{3,}|~{3,})(?<info>.*)$',
);

/// Scans [lines] and returns every fenced code block in document order.
///
/// Implements the CommonMark fence rules that matter for drift detection: a
/// tilde fence may carry a backtick in its info string but a backtick fence may
/// not, a closing fence must use the same character, be at least as long, and
/// carry no info string, and an unclosed fence extends to the end of the file.
///
/// Pure: no filesystem access, no subprocess.
List<FencedBlock> fencedBlocks(List<String> lines) {
  final blocks = <FencedBlock>[];
  var index = 0;
  while (index < lines.length) {
    final open = _fencePattern.firstMatch(lines[index]);
    if (open == null) {
      index++;
      continue;
    }
    final marker = open.namedGroup('marker')!;
    final fenceChar = marker[0];
    final info = open.namedGroup('info')!.trim();
    // A backtick fence's info string may not contain a backtick; such a line is
    // not a fence at all.
    if (fenceChar == '`' && info.contains('`')) {
      index++;
      continue;
    }
    final language = info.isEmpty
        ? ''
        : info.split(RegExp(r'\s+')).first.toLowerCase();

    final bodyStart = index + 1;
    var cursor = bodyStart;
    int? closingIndex;
    while (cursor < lines.length) {
      final trimmed = lines[cursor].trim();
      if (trimmed.length >= marker.length &&
          trimmed.split('').every((char) => char == fenceChar)) {
        closingIndex = cursor;
        break;
      }
      cursor++;
    }

    final bodyEnd = closingIndex ?? lines.length;
    blocks.add(
      FencedBlock(
        language: language,
        startLine: index + 1,
        endLine: closingIndex == null ? lines.length : closingIndex + 1,
        body: lines.sublist(bodyStart, bodyEnd),
      ),
    );
    index = bodyEnd + 1;
  }
  return blocks;
}

/// Whether [relativePath] — a path relative to the scan root — is scanned.
///
/// Only Markdown is scanned. Nested dot-directories (including `.git/`) are
/// skipped; a dot-directory passed *as* the scan root is not a nested segment,
/// so `--dir .claude` still scans everything under it.
bool isScannableArtifact(String relativePath) {
  if (!relativePath.toLowerCase().endsWith('.md')) return false;
  final segments = relativePath.split('/');
  for (var index = 0; index < segments.length - 1; index++) {
    if (segments[index].startsWith('.')) return false;
  }
  return true;
}
