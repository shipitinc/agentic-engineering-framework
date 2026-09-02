import 'dart:convert';
import 'dart:io';

import 'package:framework_cli/framework_cli.dart';
import 'package:test/test.dart';

void main() {
  group('ContentHash', () {
    test('is deterministic and stable for unchanged content', () {
      final a = hashText('hello framework');
      final b = hashText('hello framework');
      expect(a, equals(b));
      expect(a.toString(), equals(b.toString()));
    });

    test('is sensitive to content changes', () {
      final a = hashText('hello framework');
      final b = hashText('hello Framework');
      expect(a, isNot(equals(b)));
    });

    test('normalizes CRLF and lone CR to LF (line-ending independent)', () {
      final lf = hashText('line1\nline2\n');
      final crlf = hashText('line1\r\nline2\r\n');
      final cr = hashText('line1\rline2\r');
      expect(crlf, equals(lf));
      expect(cr, equals(lf));
    });

    test('emits a stable "sha256:hex" representation and round-trips', () {
      final hash = hashText('payload');
      final text = hash.toString();
      expect(text, startsWith('sha256:'));
      expect(text.split(':').last.length, equals(64));
      expect(ContentHash.parse(text), equals(hash));
    });

    test('parse rejects malformed digests', () {
      expect(() => ContentHash.parse('nope'), throwsFormatException);
      expect(() => ContentHash.parse('md5:abc'), throwsFormatException);
      expect(() => ContentHash.parse('sha256:XYZ'), throwsFormatException);
      expect(() => ContentHash.parse('sha256:abc'), throwsFormatException);
    });

    test('binary content is hashed as raw bytes (no LF normalization)', () {
      // Two binaries differing only by a single 0x0d vs 0x0a byte. Both are
      // classified binary via the NUL byte, so they must hash differently.
      final withCr = ContentHash.ofBytes(<int>[0x00, 0x0d, 0x41]);
      final withLf = ContentHash.ofBytes(<int>[0x00, 0x0a, 0x41]);
      expect(withCr, isNot(equals(withLf)));
    });

    test('NUL-containing content is treated as binary', () {
      // As binary, CRLF differs from LF (unlike text, which normalizes).
      final binaryCrlf = ContentHash.ofBytes(<int>[0x00, 0x0d, 0x0a]);
      final binaryLf = ContentHash.ofBytes(<int>[0x00, 0x0a]);
      expect(binaryCrlf, isNot(equals(binaryLf)));
      // Forcing the same bytes as text would normalize CRLF -> LF and match.
      final asTextCrlf = ContentHash.ofBytes(<int>[
        0x00,
        0x0d,
        0x0a,
      ], isText: true);
      final asTextLf = ContentHash.ofBytes(<int>[0x00, 0x0a], isText: true);
      expect(asTextCrlf, equals(asTextLf));
    });

    test('text CRLF and LF still hash identically (backward-compatible)', () {
      final crlf = ContentHash.ofBytes(utf8.encode('a\r\nb\r\n'));
      final lf = ContentHash.ofBytes(utf8.encode('a\nb\n'));
      expect(crlf, equals(lf));
    });

    test('ofFile equals ofBytes for the same content', () {
      final dir = Directory.systemTemp.createTempSync('hash_test_');
      try {
        final file = File('${dir.path}/a.txt');
        file.writeAsBytesSync(utf8.encode('file content'));
        expect(ContentHash.ofFile(file), equals(hashText('file content')));
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
