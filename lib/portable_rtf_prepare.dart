part of 'portable_book_prepare.dart';

class _RtfInput {
  _RtfInput(File file) : input = file.openSync();
  final RandomAccessFile input;
  List<int> buffer = const [];
  int at = 0, pushed = -1;
  int read() {
    if (pushed >= 0) {
      final value = pushed;
      pushed = -1;
      return value;
    }
    if (at == buffer.length) {
      buffer = input.readSync(65536);
      at = 0;
    }
    return at < buffer.length ? buffer[at++] : -1;
  }

  void unread(int value) {
    if (value >= 0) pushed = value;
  }

  void close() => input.closeSync();
}

class _RtfState {
  _RtfState({
    this.ignored = false,
    this.uc = 1,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.align = '',
    this.outline = 9,
  });
  bool ignored, bold, italic, underline;
  int uc, outline;
  String align;
  _RtfState copy() => _RtfState(
    ignored: ignored,
    uc: uc,
    bold: bold,
    italic: italic,
    underline: underline,
    align: align,
    outline: outline,
  );
}

class _RtfPicture {
  _RtfPicture(this.file, this.depth, this.key)
    : sink = file.openSync(mode: FileMode.write);
  final File file;
  final RandomAccessFile sink;
  final int depth;
  final String key;
  final buffer = <int>[];
  int count = 0, high = -1;
  double? width, height;
  bool bad = false, raster = false;
  void add(int byte) {
    if (++count > 8 * 1024 * 1024) {
      bad = true;
      return;
    }
    buffer.add(byte);
    if (buffer.length >= 16384) flush();
  }

  void hex(int byte) {
    if ({9, 10, 13, 32}.contains(byte)) return;
    final digit = byte >= 48 && byte <= 57
        ? byte - 48
        : byte >= 65 && byte <= 70
        ? byte - 55
        : byte >= 97 && byte <= 102
        ? byte - 87
        : -1;
    if (digit < 0) {
      bad = true;
      return;
    }
    if (high < 0) {
      high = digit;
    } else {
      add(high * 16 + digit);
      high = -1;
    }
  }

  void flush() {
    if (buffer.isNotEmpty) {
      sink.writeFromSync(buffer);
      buffer.clear();
    }
  }

  void close() {
    flush();
    sink.closeSync();
  }
}

String _rtfEncoding(int codePage) => switch (codePage) {
  65001 || 20127 => 'UTF-8',
  936 => 'GB18030',
  950 => 'Big5',
  932 => 'CP932',
  final cp when cp >= 1250 && cp <= 1258 => 'WINDOWS-$cp',
  _ => throw FormatException('暂不支持 RTF 字节编码 $codePage，请转换为 EPUB 或 UTF-8 文档'),
};

Future<_StructuredBook> _readRtf(
  File source,
  _MarkupResources resources,
  Directory work,
  String name,
) async {
  final input = _RtfInput(source),
      encoded = File('${work.path}/rtf-encoded.xml');
  final sink = _BufferedDocumentOutput(encoded);
  var target = sink;
  final images = <String, File>{};
  final stack = <_RtfState>[];
  var state = _RtfState(), encoding = 'WINDOWS-1252';
  var fallback = 0, highSurrogate = -1, bytes = 0, serial = 0, noteSerial = 0;
  var paragraph = '', span = false, seenHeader = false, visibleBytes = false;
  final notes = <File>[];
  final noteContexts =
      <
        ({
          int depth,
          _BufferedDocumentOutput parent,
          _BufferedDocumentOutput sink,
          String paragraph,
          File file,
        })
      >[];
  _RtfPicture? picture;
  void raw(List<int> value) {
    bytes += value.length;
    if (bytes > _maxExpanded) throw const FormatException('转换后的 RTF 超过大小限制');
    target.writeFromSync(value);
  }

  void markup(String value) => raw(ascii.encode(value));
  void closeSpan() {
    if (span) {
      markup('</span>');
      span = false;
    }
  }

  void endParagraph() {
    closeSpan();
    if (paragraph.isNotEmpty) {
      markup('</$paragraph>');
      paragraph = '';
    }
  }

  void begin() {
    if (paragraph.isEmpty) {
      paragraph = state.outline >= 0 && state.outline < 9
          ? 'h${math.min(6, state.outline + 1)}'
          : 'p';
      markup(
        '<$paragraph${state.align.isEmpty ? '' : ' style="text-align:${state.align}"'}>',
      );
    }
    if (!span) {
      markup(
        '<span style="font-weight:${state.bold ? 'bold' : 'normal'};font-style:${state.italic ? 'italic' : 'normal'};text-decoration:${state.underline ? 'underline' : 'none'}">',
      );
      span = true;
    }
  }

  void requireScalar() {
    if (highSurrogate >= 0) throw const FormatException('RTF 的 Unicode 字符不完整');
  }

  void emitByte(int value) {
    if (fallback > 0) {
      fallback--;
      return;
    }
    if (state.ignored) return;
    requireScalar();
    begin();
    visibleBytes = true;
    switch (value) {
      case 38:
        markup('&amp;');
      case 60:
        markup('&lt;');
      case 62:
        markup('&gt;');
      case 0:
        break;
      default:
        if (value >= 32 || value == 9) {
          if (++bytes > _maxExpanded) {
            throw const FormatException('转换后的 RTF 超过大小限制');
          }
          target.addByte(value);
        }
    }
  }

  void emitUnicode(int scalar, {bool fallbackUnit = false}) {
    if (state.ignored) return;
    if (fallbackUnit) {
      final unit = scalar & 0xffff;
      if (unit >= 0xd800 && unit <= 0xdbff) {
        requireScalar();
        highSurrogate = unit;
      } else {
        if (unit >= 0xdc00 && unit <= 0xdfff) {
          if (highSurrogate < 0) {
            throw const FormatException('RTF 的 Unicode 字符不完整');
          }
          scalar = 0x10000 + ((highSurrogate - 0xd800) << 10) + unit - 0xdc00;
          highSurrogate = -1;
        } else {
          requireScalar();
          scalar = unit;
        }
        begin();
        markup('&#$scalar;');
      }
      fallback = state.uc;
    } else {
      requireScalar();
      begin();
      markup('&#$scalar;');
    }
  }

  bool letter(int c) => c >= 65 && c <= 90 || c >= 97 && c <= 122;
  bool digit(int c) => c >= 48 && c <= 57;
  void finishPicture() {
    final current = picture!;
    current.close();
    picture = null;
    if (!current.bad && current.raster && current.high < 0) {
      images[current.key] = current.file;
    }
    begin();
    closeSpan();
    markup(
      '<img data-image-key="${current.key}"${current.width == null && current.height == null ? '' : ' style="${current.width == null ? '' : 'width:${current.width}px;'}${current.height == null ? '' : 'height:${current.height}px;'}"'}/>',
    );
  }

  markup(
    '<?xml version="1.0"?><doc xmlns:epub="http://www.idpf.org/2007/ops">',
  );
  try {
    final header = [for (var i = 0; i < 5; i++) input.read()];
    if (header.any((value) => value < 0) ||
        ascii.decode(header, allowInvalid: true) != '{\\rtf') {
      throw const FormatException('RTF 文件头无效');
    }
    // The consumed header is the opening group plus the first control word.
    stack.add(state);
    state = state.copy();
    seenHeader = true;
    var next = input.read();
    while (digit(next)) {
      next = input.read();
    }
    input.unread(next);
    while ((next = input.read()) >= 0) {
      if (next == 123) {
        if (stack.length >= 512) throw const FormatException('RTF 分组超过 512 层');
        closeSpan();
        stack.add(state);
        state = state.copy();
      } else if (next == 125) {
        if (stack.isEmpty) throw const FormatException('RTF 分组损坏');
        if (picture?.depth == stack.length) finishPicture();
        if (noteContexts.isNotEmpty &&
            noteContexts.last.depth == stack.length) {
          endParagraph();
          markup('</aside>');
          final note = noteContexts.removeLast();
          note.sink.closeSync();
          notes.add(note.file);
          target = note.parent;
          paragraph = note.paragraph;
          span = false;
        }
        closeSpan();
        state = stack.removeLast();
      } else if (next == 92) {
        final symbol = input.read();
        if (symbol < 0) throw const FormatException('RTF 转义不完整');
        if (symbol == 39) {
          final a = input.read(), b = input.read();
          if (a < 0 || b < 0) throw const FormatException('RTF 字符转义不完整');
          final value = int.tryParse(String.fromCharCodes([a, b]), radix: 16);
          if (value == null) throw const FormatException('RTF 字符转义无效');
          if (picture != null) {
            picture!.add(value);
          } else {
            emitByte(value);
          }
          continue;
        }
        if (!letter(symbol)) {
          switch (symbol) {
            case 42:
              state.ignored = true;
            case 92 || 123 || 125:
              emitByte(symbol);
            case 126:
              if (fallback > 0) {
                fallback--;
              } else {
                emitUnicode(160);
              }
            case 95:
              if (fallback > 0) {
                fallback--;
              } else {
                emitUnicode(8209);
              }
            default:
              break;
          }
          continue;
        }
        final word = StringBuffer()..writeCharCode(symbol);
        var current = input.read();
        while (letter(current)) {
          if (word.length >= 64) throw const FormatException('RTF 控制词无效');
          word.writeCharCode(current);
          current = input.read();
        }
        final number = StringBuffer();
        if (current == 45 || digit(current)) {
          number.writeCharCode(current);
          current = input.read();
          while (digit(current)) {
            if (number.length > 11) throw const FormatException('RTF 参数无效');
            number.writeCharCode(current);
            current = input.read();
          }
        }
        if (current != 32) input.unread(current);
        final code = word.toString(),
            value = int.tryParse(number.toString()) ?? 0;
        if (code == 'bin') {
          if (value < 0 || value > maxLocalTextBytes) {
            throw const FormatException('RTF 二进制长度无效');
          }
          for (var i = 0; i < value; i++) {
            final byte = input.read();
            if (byte < 0) throw const FormatException('RTF 二进制内容不完整');
            picture?.add(byte);
          }
          continue;
        }
        if (picture != null) {
          switch (code) {
            case 'pngblip' || 'jpegblip':
              picture!.raster = true;
            case 'picwgoal':
              picture!.width = value > 0 ? value / 15 : null;
            case 'pichgoal':
              picture!.height = value > 0 ? value / 15 : null;
            default:
              break;
          }
          continue;
        }
        if ({
          'fonttbl',
          'colortbl',
          'stylesheet',
          'info',
          'object',
          'objdata',
          'header',
          'footer',
          'fldinst',
          'filetbl',
          'listtable',
          'listoverridetable',
        }.contains(code)) {
          state.ignored = true;
          continue;
        }
        if (code == 'ansicpg') {
          final selected = _rtfEncoding(value);
          if (visibleBytes && selected != encoding) {
            throw const FormatException('RTF 包含多种字节编码，请转换为 EPUB 后导入');
          }
          encoding = selected;
          continue;
        }
        if (state.ignored) continue;
        closeSpan();
        switch (code) {
          case 'pict':
            picture = _RtfPicture(
              File('${work.path}/rtf-picture-$serial'),
              stack.length,
              'rtf-picture-${serial++}',
            );
          case 'uc':
            state.uc = value.clamp(0, 16);
          case 'u':
            emitUnicode(value, fallbackUnit: true);
          case 'b':
            state.bold = number.isEmpty || value != 0;
          case 'i':
            state.italic = number.isEmpty || value != 0;
          case 'ul':
            state.underline = number.isEmpty || value != 0;
          case 'ulnone':
            state.underline = false;
          case 'plain':
            state.bold = false;
            state.italic = false;
            state.underline = false;
          case 'pard':
            endParagraph();
            state.align = '';
            state.outline = 9;
          case 'qc' || 'qr' || 'ql' || 'qj':
            state.align = {
              'qc': 'center',
              'qr': 'right',
              'ql': 'left',
              'qj': 'justify',
            }[code]!;
          case 'outlinelevel':
            state.outline = value.clamp(0, 9);
          case 'par':
            requireScalar();
            endParagraph();
          case 'page':
            requireScalar();
            endParagraph();
            markup('<p style="break-before:page"></p>');
          case 'line':
            requireScalar();
            begin();
            markup('<br/>');
          case 'tab':
            emitUnicode(8195);
          case 'emdash':
            emitUnicode(8212);
          case 'endash':
            emitUnicode(8211);
          case 'lquote':
            emitUnicode(8216);
          case 'rquote':
            emitUnicode(8217);
          case 'ldblquote':
            emitUnicode(8220);
          case 'rdblquote':
            emitUnicode(8221);
          case 'footnote':
            begin();
            closeSpan();
            final id = 'rtf-note-${noteSerial++}';
            markup('<a epub:type="noteref" href="#$id">[$noteSerial]</a>');
            final file = File('${work.path}/$id.xml');
            final noteSink = _BufferedDocumentOutput(file);
            noteContexts.add((
              depth: stack.length,
              parent: target,
              sink: noteSink,
              paragraph: paragraph,
              file: file,
            ));
            target = noteSink;
            paragraph = '';
            span = false;
            markup('<aside epub:type="footnote" id="$id">');
          default:
            break;
        }
      } else if (picture != null) {
        picture!.hex(next);
      } else if (next != 10 && next != 13) {
        emitByte(next);
      }
    }
    if (!seenHeader || stack.isNotEmpty) {
      throw const FormatException('RTF 文件不完整');
    }
    requireScalar();
    endParagraph();
    for (final file in notes) {
      final input = file.openSync();
      try {
        while (true) {
          final chunk = input.readSync(65536);
          if (chunk.isEmpty) break;
          // These bytes were already counted while the note was written.
          sink.writeFromSync(chunk);
        }
      } finally {
        input.closeSync();
      }
    }
    markup('</doc>');
  } finally {
    picture?.close();
    for (final note in noteContexts) {
      note.sink.closeSync();
    }
    input.close();
    sink.closeSync();
  }
  final normalized = File('${work.path}/rtf.xml');
  await resources.withDecoded(encoded, _maxExpanded, (decoded) async {
    await decoded.copy(normalized.path);
  }, encoding: encoding);
  return (
    document: normalized,
    title: name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
    author: '',
    images: images,
    cover: null,
  );
}
