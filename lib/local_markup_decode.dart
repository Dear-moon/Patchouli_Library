import 'dart:convert';
import 'dart:typed_data';

/// EPUB XML/XHTML may use UTF-8 or UTF-16, independently of the device language.
/// Each caller already bounds the uncompressed entry; malformed text is rejected
/// rather than silently replacing characters in chapter content or image URLs.
String decodeLocalMarkup(List<int> bytes) {
  bool? littleEndian;
  var start = 0;
  if (bytes.length >= 2) {
    if (bytes[0] == 0xff && bytes[1] == 0xfe) {
      littleEndian = true;
      start = 2;
    } else if (bytes[0] == 0xfe && bytes[1] == 0xff) {
      littleEndian = false;
      start = 2;
    } else if (bytes.length >= 4) {
      if (bytes[0] == 0x3c && bytes[1] == 0 && bytes[3] == 0) {
        littleEndian = true;
      } else if (bytes[0] == 0 && bytes[1] == 0x3c && bytes[2] == 0) {
        littleEndian = false;
      }
    }
  }
  if (littleEndian == null) return utf8.decode(bytes);
  if ((bytes.length - start).isOdd) {
    throw const FormatException('EPUB 的 UTF-16 文本不完整');
  }
  final units = Uint16List((bytes.length - start) ~/ 2);
  var highSurrogate = false;
  for (var i = 0; i < units.length; i++) {
    final at = start + i * 2;
    final unit = littleEndian
        ? bytes[at] | (bytes[at + 1] << 8)
        : (bytes[at] << 8) | bytes[at + 1];
    final lowSurrogate = unit >= 0xdc00 && unit <= 0xdfff;
    if (highSurrogate != lowSurrogate) {
      throw const FormatException('EPUB 的 UTF-16 字符不完整');
    }
    highSurrogate = unit >= 0xd800 && unit <= 0xdbff;
    units[i] = unit;
  }
  if (highSurrogate) {
    throw const FormatException('EPUB 的 UTF-16 字符不完整');
  }
  return String.fromCharCodes(units);
}
