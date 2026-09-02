import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Immutable, algorithm-tagged content hash of a managed artifact.
///
/// A [ContentHash] is the single source of truth for a managed artifact's
/// content fingerprint. It is deterministic and stable for unchanged content,
/// and is used both as a stored baseline (in the manifest) and as a freshly
/// computed current value (during modification detection). Local-modification
/// state is *derived* by comparing a current [ContentHash] against a stored
/// baseline — it is never persisted as a flag (ADR 0002, mitigation 15).
///
/// ## Normalization choice (documented, deterministic)
///
/// Content is hashed after **line-ending normalization**: every `CRLF`
/// (`\r\n`) and every lone `CR` (`\r`) is converted to a single `LF` (`\n`)
/// before hashing. This makes the hash independent of the line-ending style a
/// product repository happens to check out with (e.g. Git `core.autocrlf`), so
/// an artifact that differs only by line endings is treated as *unchanged*.
/// The normalized bytes are then hashed with SHA-256. This decision is fixed
/// and applied uniformly to every artifact so hashes are byte-for-byte
/// reproducible across platforms and runs.
class ContentHash {
  const ContentHash._(this.algorithm, this.hex);

  /// The hashing algorithm identifier (currently always `sha256`).
  final String algorithm;

  /// The lowercase hexadecimal digest.
  final String hex;

  /// The algorithm identifier used for all Phase 2 hashing.
  static const String defaultAlgorithm = 'sha256';

  /// Computes the [ContentHash] of raw [bytes] after line-ending normalization.
  factory ContentHash.ofBytes(List<int> bytes) {
    final normalized = _normalizeLineEndings(bytes);
    final digest = sha256.convert(normalized);
    return ContentHash._(defaultAlgorithm, digest.toString());
  }

  /// Computes the [ContentHash] of a [file]'s current on-disk content.
  factory ContentHash.ofFile(File file) {
    return ContentHash.ofBytes(file.readAsBytesSync());
  }

  /// Parses a stored `"algorithm:hex"` representation (e.g. `sha256:ab12...`).
  ///
  /// Throws [FormatException] if [value] is not a well-formed, lowercase-hex,
  /// SHA-256 tagged digest, keeping stored baselines unambiguous.
  factory ContentHash.parse(String value) {
    final sep = value.indexOf(':');
    if (sep <= 0) {
      throw FormatException(
        'Malformed content hash (expected "algo:hex")',
        value,
      );
    }
    final algorithm = value.substring(0, sep);
    final hex = value.substring(sep + 1);
    if (algorithm != defaultAlgorithm) {
      throw FormatException('Unsupported hash algorithm "$algorithm"', value);
    }
    if (hex.length != 64 || !_isLowerHex(hex)) {
      throw FormatException('Malformed sha256 digest', value);
    }
    return ContentHash._(algorithm, hex);
  }

  /// Stable `"algorithm:hex"` representation stored in the manifest.
  @override
  String toString() => '$algorithm:$hex';

  @override
  bool operator ==(Object other) =>
      other is ContentHash && other.algorithm == algorithm && other.hex == hex;

  @override
  int get hashCode => Object.hash(algorithm, hex);

  static bool _isLowerHex(String s) {
    for (final unit in s.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isLower = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isLower) return false;
    }
    return true;
  }

  /// Converts `\r\n` and lone `\r` to `\n`. Operates on raw bytes so the same
  /// deterministic rule applies uniformly to every artifact (see class doc).
  static List<int> _normalizeLineEndings(List<int> bytes) {
    const cr = 0x0d;
    const lf = 0x0a;
    final out = <int>[];
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b == cr) {
        out.add(lf);
        if (i + 1 < bytes.length && bytes[i + 1] == lf) {
          i++; // Skip the LF of a CRLF pair (already emitted one LF).
        }
      } else {
        out.add(b);
      }
    }
    return out;
  }
}

/// Convenience: UTF-8 encodes [text] and computes its normalized [ContentHash].
ContentHash hashText(String text) => ContentHash.ofBytes(utf8.encode(text));
