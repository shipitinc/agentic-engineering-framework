import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() {
  final brickDir = Directory('../framework/templates');
  final hashes = <String>[];

  for (final entity in brickDir.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      final rel = entity.absolute.path
          .replaceFirst(brickDir.absolute.path, '')
          .replaceAll('\\', '/');
      final normalized = rel.startsWith('/') ? rel.substring(1) : rel;

      if (normalized.startsWith('.mason/') || normalized.startsWith('.git/')) {
        continue;
      }
      if (normalized == 'brick.yaml' ||
          normalized == 'BLOCKS.md' ||
          normalized == 'README.md') {
        continue;
      }

      final content = entity.readAsBytesSync();
      final hash = sha256.convert(content);
      hashes.add('$normalized:${hash.toString()}');
    }
  }
  hashes.sort();
  final combined = hashes.join('\n');
  final combinedHash = sha256.convert(utf8.encode(combined));
  print('Brick content hash: $combinedHash');
  print('Revision: ${_resolveRevision()}');
}

/// The framework repository revision this brick content corresponds to.
///
/// Derived from git rather than hardcoded: a literal here silently goes stale
/// and then misreports which revision produced a hash. `git rev-parse HEAD` is
/// run from the framework repository root, which is the parent of `cli/` — the
/// directory this tool is documented to run from (`brickDir` is `../framework/
/// templates`, so the working directory is `cli/`).
String _resolveRevision() {
  final result = Process.runSync('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: '..');
  final revision = (result.stdout as String).trim();
  if (result.exitCode != 0 || revision.isEmpty) {
    return 'UNKNOWN (git rev-parse HEAD failed: '
        '${(result.stderr as String).trim()})';
  }
  return revision;
}
