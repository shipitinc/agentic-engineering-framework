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
/// Content is classified per artifact as **text** or **binary**, and
/// line-ending normalization is applied **only to text**:
///
/// - **Text** content is hashed after **line-ending normalization**: every
///   `CRLF` (`\r\n`) and every lone `CR` (`\r`) is converted to a single `LF`
///   (`\n`) before hashing. This makes the hash independent of the line-ending
///   style a product repository happens to check out with (e.g. Git
///   `core.autocrlf`), so a text artifact that differs only by line endings is
///   treated as *unchanged*.
/// - **Binary** content is hashed as **raw bytes** with no normalization, so a
///   binary artifact differing only by a `0x0d`/`0x0a` byte is (correctly)
///   treated as changed and never misclassified as a line-ending difference.
///
/// The (possibly normalized) bytes are then hashed with SHA-256. This decision
/// is fixed and deterministic so hashes are byte-for-byte reproducible across
/// platforms and runs.
///
/// ### Binary-detection heuristic (deterministic, dependency-free)
///
/// Content is classified as **binary** when either of the following holds:
/// - it contains at least one `NUL` (`0x00`) byte; or
/// - more than 30% of its bytes are non-text control bytes, where a
///   "non-text control byte" is any byte `< 0x20` that is **not** one of the
///   common text whitespace controls TAB (`0x09`), LF (`0x0a`), CR (`0x0d`)
///   or FF (`0x0c`).
///
/// Empty content is treated as text. Callers may bypass the heuristic with an
/// explicit `isText` override (see [ContentHash.ofBytes]).
class ContentHash {
  const ContentHash._(this.algorithm, this.hex);

  /// The hashing algorithm identifier (currently always `sha256`).
  final String algorithm;

  /// The lowercase hexadecimal digest.
  final String hex;

  /// The algorithm identifier used for all Phase 2 hashing.
  static const String defaultAlgorithm = 'sha256';

  /// Computes the [ContentHash] of raw [bytes].
  ///
  /// Text content is line-ending normalized before hashing; binary content is
  /// hashed as raw bytes. Classification uses the deterministic heuristic
  /// documented on [ContentHash] unless [isText] is supplied to force text
  /// (`true`) or binary (`false`) treatment. [isText] is a backward-compatible
  /// optional override: with the default (`null`) the heuristic decides, and
  /// text artifacts hash identically to previous releases.
  factory ContentHash.ofBytes(List<int> bytes, {bool? isText}) {
    final treatAsText = isText ?? !_looksBinary(bytes);
    final toHash = treatAsText ? _normalizeLineEndings(bytes) : bytes;
    final digest = sha256.convert(toHash);
    return ContentHash._(defaultAlgorithm, digest.toString());
  }

  /// Computes the [ContentHash] of a [file]'s current on-disk content.
  ///
  /// Pass [isText] to override the automatic text/binary classification.
  factory ContentHash.ofFile(File file, {bool? isText}) {
    return ContentHash.ofBytes(file.readAsBytesSync(), isText: isText);
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

  /// Classifies [bytes] as binary per the heuristic documented on
  /// [ContentHash]: any `NUL` byte, or more than 30% non-text control bytes.
  /// Empty content is treated as text (not binary).
  static bool _looksBinary(List<int> bytes) {
    if (bytes.isEmpty) return false;
    const nul = 0x00;
    const tab = 0x09;
    const lf = 0x0a;
    const ff = 0x0c;
    const cr = 0x0d;
    const space = 0x20;
    var controlCount = 0;
    for (final b in bytes) {
      if (b == nul) return true;
      if (b < space && b != tab && b != lf && b != ff && b != cr) {
        controlCount++;
      }
    }
    return controlCount * 10 > bytes.length * 3; // > 30%
  }

  /// Converts `\r\n` and lone `\r` to `\n`. Operates on raw bytes so the same
  /// deterministic rule applies to every *text* artifact (see class doc).
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
