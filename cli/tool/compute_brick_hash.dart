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
      
      if (normalized.startsWith('.mason/') || normalized.startsWith('.git/')) continue;
      if (normalized == 'brick.yaml' || normalized == 'BLOCKS.md' || normalized == 'README.md') continue;
      
      final content = entity.readAsBytesSync();
      final hash = sha256.convert(content);
      hashes.add('$normalized:${hash.toString()}');
    }
  }
  hashes.sort();
  final combined = hashes.join('\n');
  final combinedHash = sha256.convert(utf8.encode(combined));
  print('Brick content hash: $combinedHash');
  print('Revision: 4c7baa12a9e117454ce55bde76afb3550aaa8afb');
}
