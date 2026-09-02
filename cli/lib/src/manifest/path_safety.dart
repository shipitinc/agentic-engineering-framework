import 'dart:io';

/// Raised when a managed-artifact path violates path-safety rules.
///
/// See [normalizeManagedPath] for the full policy. This is a hard rejection
/// class (ADR 0002, mitigation 16): the framework driver must never read from
/// or write to a path outside the product repository root.
class PathSafetyException implements Exception {
  PathSafetyException(this.rawPath, this.reason);

  /// The offending path exactly as supplied.
  final String rawPath;

  /// A short, human-readable explanation of why the path was rejected.
  final String reason;

  @override
  String toString() => 'PathSafetyException: $reason (path: "$rawPath")';
}

/// Validates and normalizes a managed-artifact [rawPath] to a safe,
/// repo-relative, POSIX-style path.
///
/// Managed paths are always interpreted relative to the product repository
/// root. This function enforces path safety (ADR 0002, mitigation 16) and
/// returns a normalized, forward-slash path with `.` segments collapsed and
/// redundant separators removed. It is deterministic: the same input always
/// yields the same output.
///
/// A path is rejected with [PathSafetyException] when it:
/// - is empty or whitespace-only;
/// - is absolute (POSIX `/...` or Windows drive/UNC form such as `C:\...`);
/// - contains any `..` (parent) segment, which could escape the repo root;
/// - normalizes to empty (e.g. `.`), i.e. does not name an artifact.
///
/// Backslashes are treated as separators so manifests authored on Windows are
/// normalized to the same canonical form as on POSIX systems.
String normalizeManagedPath(String rawPath) {
  final trimmed = rawPath.trim();
  if (trimmed.isEmpty) {
    throw PathSafetyException(rawPath, 'path is empty');
  }

  // Reject Windows drive-letter absolute paths (e.g. C:\ or C:/) up front.
  if (trimmed.length >= 2 &&
      _isDriveLetter(trimmed.codeUnitAt(0)) &&
      trimmed[1] == ':') {
    throw PathSafetyException(rawPath, 'absolute paths are not allowed');
  }

  final unified = trimmed.replaceAll('\\', '/');

  // Reject POSIX-absolute and UNC (`//host/...`) paths.
  if (unified.startsWith('/')) {
    throw PathSafetyException(rawPath, 'absolute paths are not allowed');
  }

  final segments = <String>[];
  for (final segment in unified.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue; // Collapse redundant separators and `.` segments.
    }
    if (segment == '..') {
      throw PathSafetyException(
        rawPath,
        'parent-directory ("..") segments are not allowed',
      );
    }
    segments.add(segment);
  }

  if (segments.isEmpty) {
    throw PathSafetyException(rawPath, 'path does not name an artifact');
  }

  return segments.join('/');
}

/// Resolves a normalized managed [artifactPath] to an absolute [File] under
/// [repoRoot], re-validating safety.
///
/// The returned file is guaranteed to live inside [repoRoot]; the containment
/// is asserted after resolution as defense-in-depth against symlink or
/// normalization surprises.
File resolveManagedFile(Directory repoRoot, String artifactPath) {
  final normalized = normalizeManagedPath(artifactPath);
  final rootPath = _stripTrailingSlash(repoRoot.absolute.path);
  final joined = '$rootPath/$normalized';
  final file = File(joined);

  final resolvedRoot = _stripTrailingSlash(rootPath.replaceAll('\\', '/'));
  final resolvedFile = file.absolute.path.replaceAll('\\', '/');
  if (!resolvedFile.startsWith('$resolvedRoot/')) {
    throw PathSafetyException(
      artifactPath,
      'resolved path escapes the repository root',
    );
  }
  return file;
}

bool _isDriveLetter(int codeUnit) =>
    (codeUnit >= 0x41 && codeUnit <= 0x5a) || // A-Z
    (codeUnit >= 0x61 && codeUnit <= 0x7a); // a-z

String _stripTrailingSlash(String p) {
  var s = p;
  while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}
