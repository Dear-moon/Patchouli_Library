part of 'portable_book_prepare.dart';

bool _isPortableDocument(String name) =>
    _isMarkup(name) ||
    RegExp(r'\.(fb2|docx|rtf)$', caseSensitive: false).hasMatch(name);

typedef _StructuredBook = ({
  File document,
  String title,
  String author,
  Map<String, File> images,
  String? cover,
});

Future<({String path, List<String> companions})> _prepareStructured(
  _MarkupJob job,
) async {
  if (job.token case final token?) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final work = Directory(job.directory).createTempSync('document-');
  final output = File(
    '${job.directory}/${work.uri.pathSegments.where((s) => s.isNotEmpty).last}.epub',
  );
  var resources = _MarkupResources(job, work);
  _MarkupWriter? writer;
  try {
    final source = File(job.source);
    if (source.lengthSync() < 1) {
      throw const FormatException('文档为空，请重新选择原文件');
    }
    if (source.lengthSync() > localBookByteLimit(job.name)) {
      throw FormatException(localBookSizeMessage(job.name));
    }
    late _StructuredBook book;
    switch (bookFormatKey(job.name)) {
      case 'fb2':
        book = await resources.withDecoded(
          source,
          maxLocalTextBytes,
          (decoded) => _readFb2(decoded, work, job.name),
        );
      case 'docx':
        resources.close();
        resources = await _docxResources(job, work);
        book = await _readDocx(resources, work, job.name);
      case 'rtf':
        book = await _readRtf(source, resources, work, job.name);
      default:
        throw const FormatException('此文档格式尚未适配');
    }
    writer = _MarkupWriter(work, book.title);
    if (book.cover case final cover?) {
      resources.fileImage(cover, book.images[cover], isCover: true);
    }
    await _renderStructured(book, writer, resources, job.name);
    writer.finish();
    writer.resolveLinks();
    _writeMarkupEpub(output, book.title, book.author, writer, resources);
    return (path: output.path, companions: const <String>[]);
  } catch (_) {
    if (output.existsSync()) output.deleteSync();
    rethrow;
  } finally {
    writer?.abort();
    resources.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

class _XmlEventsSink implements Sink<List<events.XmlEvent>> {
  _XmlEventsSink(this.receive);
  final void Function(events.XmlEvent) receive;
  int stop = 0;
  @override
  void add(List<events.XmlEvent> batch) {
    for (final event in batch) {
      stop = event.stop ?? stop;
      receive(event);
    }
  }

  @override
  void close() {}
}

/// Event streams retain only an incomplete XML token, not a document tree.
/// Keep entity references together across input chunks before accessing .text.
Future<void> _structuredXml(
  File source, {
  required void Function(String, Map<String, String>) start,
  required void Function(String) text,
  required void Function(String) end,
}) async {
  var depth = 0;
  final sink = _XmlEventsSink((event) {
    switch (event) {
      case events.XmlDoctypeEvent():
        throw const FormatException('不支持含 DTD 或外部实体的本地文档');
      case events.XmlStartElementEvent():
        if (++depth > 256) throw const FormatException('XML 文档嵌套超过 256 层');
        final name = event.name.split(':').last;
        final attrs = {for (final a in event.attributes) a.name: a.value};
        start(name, attrs);
        if (event.isSelfClosing) {
          end(name);
          depth--;
        }
      case events.XmlEndElementEvent():
        end(event.name.split(':').last);
        depth--;
      case events.XmlTextEvent():
        text(event.value);
      case events.XmlCDATAEvent():
        text(event.value);
      default:
        break;
    }
  });
  final decoder = events.XmlEventDecoder(
    validateNesting: true,
    validateDocument: true,
    withLocation: true,
  ).startChunkedConversion(sink);
  var pending = '', count = 0;
  try {
    await for (final chunk in source.openRead().transform(utf8.decoder)) {
      var value = pending + chunk;
      pending = '';
      final amp = value.lastIndexOf('&');
      if (amp >= 0 &&
          value.length - amp <= 64 &&
          RegExp(
            r'^&(?:#x?[0-9a-fA-F]*|[A-Za-z][A-Za-z0-9]*)?$',
          ).hasMatch(value.substring(amp))) {
        pending = value.substring(amp);
        value = value.substring(0, amp);
      }
      count += value.length;
      decoder.add(value);
      if (count - sink.stop > 12 * 1024 * 1024) {
        throw const FormatException('XML 的单个结构片段过大，请检查或拆分原文件');
      }
    }
    decoder.add(pending);
    decoder.close();
  } on xml.XmlException {
    throw const FormatException('XML 结构不完整或损坏，请检查原文件');
  }
}

String? _attr(Map<String, String> attrs, String local) {
  for (final entry in attrs.entries) {
    if (entry.key.split(':').last == local) return entry.value;
  }
  return null;
}

class _BufferedDocumentOutput {
  _BufferedDocumentOutput(File file)
    : output = file.openSync(mode: FileMode.write);
  final RandomAccessFile output;
  final buffer = <int>[];
  bool closed = false;
  void addByte(int byte) {
    buffer.add(byte);
    if (buffer.length >= 65536) flush();
  }

  void writeFromSync(List<int> bytes) {
    if (bytes.length >= 65536) {
      flush();
      output.writeFromSync(bytes);
    } else {
      buffer.addAll(bytes);
      if (buffer.length >= 65536) flush();
    }
  }

  void flush() {
    if (buffer.isNotEmpty) {
      output.writeFromSync(buffer);
      buffer.clear();
    }
  }

  void closeSync() {
    if (!closed) {
      closed = true;
      flush();
      output.closeSync();
    }
  }
}

class _DocumentSpool {
  _DocumentSpool(this.file) : sink = _BufferedDocumentOutput(file) {
    write(
      '<?xml version="1.0" encoding="UTF-8"?><doc xmlns:epub="http://www.idpf.org/2007/ops">',
    );
  }
  final File file;
  final _BufferedDocumentOutput sink;
  int size = 0;
  bool closed = false;
  void write(String value) {
    final bytes = utf8.encode(value);
    if (size + bytes.length > _maxExpanded) {
      throw const FormatException('转换后的文档超过 1 GiB');
    }
    sink.writeFromSync(bytes);
    size += bytes.length;
  }

  void open(String name, [Map<String, String> attrs = const {}]) => write(
    '<$name${attrs.entries.map((e) => ' ${e.key}="${_xml(e.value)}"').join()}>',
  );
  void empty(String name, [Map<String, String> attrs = const {}]) => write(
    '<$name${attrs.entries.map((e) => ' ${e.key}="${_xml(e.value)}"').join()}/>',
  );
  void text(String value) => write(_xml(value));
  void closeTag(String tag) => write('</$tag>');
  void node(dom.Node node) {
    if (node is dom.Text) {
      text(node.data);
      return;
    }
    if (node is! dom.Element) return;
    final attrs = node.attributes.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (_MarkupWriter._void.contains(node.localName)) {
      empty(node.localName!, attrs);
      return;
    }
    open(node.localName!, attrs);
    for (final child in node.nodes) {
      this.node(child);
    }
    closeTag(node.localName!);
  }

  void finish() {
    write('</doc>');
    close();
  }

  void close() {
    if (!closed) {
      closed = true;
      sink.closeSync();
    }
  }
}

Future<void> _renderStructured(
  _StructuredBook book,
  _MarkupWriter writer,
  _MarkupResources resources,
  String base,
) async {
  var root = dom.Element.tag('div');
  var stack = <dom.Element>[root];
  var count = 0;
  bool atomic() => stack.any(
    (e) =>
        epubNoteElement(e) ||
        e.localName == 'ruby' ||
        RegExp(r'^h[1-6]$').hasMatch(e.localName ?? ''),
  );
  void flush() {
    writer.visit(root, base);
    final old = stack;
    root = dom.Element.tag('div');
    stack = [root];
    count = 0;
    for (final element in old.skip(1)) {
      final clone = dom.Element.tag(element.localName!)
        ..attributes.addAll(element.attributes)
        ..attributes.remove('id');
      stack.last.append(clone);
      stack.add(clone);
    }
  }

  await _structuredXml(
    book.document,
    start: (name, attrs) {
      final tag = name == 'doc' ? 'div' : name;
      if (tag == 'img') {
        final key = attrs.remove('data-image-key') ?? '';
        attrs['src'] = resources.fileImage(key, book.images[key]);
      }
      if (tag == 'a') {
        final href = attrs.remove('href');
        if (href != null && href.startsWith('#')) {
          attrs['href'] = writer.link(
            '$base#${Uri.decodeComponent(href.substring(1))}',
          );
        }
      }
      final element = dom.Element.tag(tag)..attributes.addAll(attrs);
      stack.last.append(element);
      stack.add(element);
    },
    text: (value) {
      stack.last.append(dom.Text(value));
      count += value.length;
      if (count > 1024 * 1024 && atomic()) {
        throw const FormatException('单条注释、标题或注音超过大小限制');
      }
      if (count >= 64000 && !atomic()) flush();
    },
    end: (name) {
      stack.removeLast();
      final inTable = stack.any((e) => e.localName == 'table');
      if (!atomic() &&
          (!inTable &&
                  {
                    'p',
                    'h1',
                    'h2',
                    'h3',
                    'h4',
                    'aside',
                    'div',
                    'doc',
                  }.contains(name) ||
              name == 'tr')) {
        flush();
      }
    },
  );
  if (root.nodes.isNotEmpty) flush();
}

Future<_StructuredBook> _readFb2(
  File source,
  Directory work,
  String name,
) async {
  final spool = _DocumentSpool(File('${work.path}/fb2.xml'));
  final path = <String>[], outputTags = <String?>[];
  final images = <String, File>{};
  var title = name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
      author = '',
      cover = '';
  var body = false, notes = false, sectionDepth = 0, hasRoot = false;
  String? field, binaryKey;
  final metadata = StringBuffer();
  File? binary;
  StringConversionSink? binaryDecoder;
  _BoundedBookSink? binaryOutput;
  var binaryFailed = false, binarySize = 0, binarySerial = 0;
  try {
    await _structuredXml(
      source,
      start: (local, attrs) {
        path.add(local);
        outputTags.add(null);
        if (path.length == 1) {
          if (local != 'FictionBook') throw const FormatException('FB2 文件头无效');
          hasRoot = true;
        }
        if (local == 'binary') {
          binaryKey = _attr(attrs, 'id') ?? '';
          if (images.containsKey(binaryKey)) {
            throw const FormatException('FB2 含重复图片标识，无法确定对应插图');
          }
          binary = File('${work.path}/fb2-image-${binarySerial++}');
          binaryOutput = _BoundedBookSink(binary!, 8 * 1024 * 1024);
          binaryDecoder = base64.decoder.startChunkedConversion(binaryOutput!);
          binarySize = 0;
          binaryFailed = false;
          return;
        }
        if (!body &&
            path.contains('title-info') &&
            {
              'book-title',
              'first-name',
              'middle-name',
              'last-name',
              'nickname',
            }.contains(local)) {
          field = local;
          metadata.clear();
        }
        if (local == 'image' && path.contains('coverpage')) {
          cover = (_attr(attrs, 'href') ?? '').replaceFirst('#', '');
        }
        if (local == 'body') {
          body = true;
          notes = {
            'notes',
            'comments',
          }.contains((_attr(attrs, 'name') ?? '').toLowerCase());
          sectionDepth = 0;
        }
        if (!body) return;
        final attributes = <String, String>{};
        if (_attr(attrs, 'id') case final id?) attributes['id'] = id;
        String tag;
        switch (local) {
          case 'body':
            tag = 'div';
          case 'section':
            sectionDepth++;
            tag = notes && sectionDepth == 1 ? 'aside' : 'div';
            if (tag == 'aside') attributes['epub:type'] = 'footnote';
          case 'title':
            tag = notes ? 'div' : 'h1';
          case 'p' || 'v':
            tag = path.contains('title') ? 'span' : 'p';
          case 'subtitle':
            tag = 'p';
            attributes['style'] = 'text-align:center';
          case 'text-author':
            tag = 'p';
            attributes['style'] = 'text-align:right';
          case 'emphasis':
            tag = 'em';
          case 'strong':
            tag = 'strong';
          case 'strikethrough':
            tag = 's';
          case 'epigraph' || 'cite':
            tag = 'blockquote';
          case 'poem' || 'stanza':
            tag = 'div';
          case 'a':
            tag = 'a';
            final href = _attr(attrs, 'href');
            if (href != null && href.startsWith('#')) attributes['href'] = href;
            if (_attr(attrs, 'type') == 'note') {
              attributes['epub:type'] = 'noteref';
            }
          case 'image':
            spool.empty('img', {
              'data-image-key': (_attr(attrs, 'href') ?? '').replaceFirst(
                '#',
                '',
              ),
              'alt': ?_attr(attrs, 'title'),
            });
            return;
          case 'empty-line':
            spool.empty('br');
            return;
          case 'table' || 'tr' || 'td' || 'th' || 'sup' || 'sub' || 'code':
            tag = local;
          default:
            tag = 'span';
        }
        outputTags[outputTags.length - 1] = tag;
        spool.open(tag, attributes);
      },
      text: (value) {
        if (binaryDecoder != null) {
          binarySize += value.length;
          if (binarySize > 12 * 1024 * 1024) {
            binaryFailed = true;
          }
          if (!binaryFailed) {
            try {
              binaryDecoder!.add(value.replaceAll(RegExp(r'\s'), ''));
            } on FormatException {
              binaryFailed = true;
            }
          }
        } else if (field != null) {
          if (metadata.length < 4096) {
            metadata.write(
              value.substring(
                0,
                math.min(value.length, 4096 - metadata.length),
              ),
            );
          }
        } else if (body) {
          spool.text(value);
        }
      },
      end: (local) {
        if (local == 'binary') {
          try {
            binaryDecoder!.close();
          } on FormatException {
            binaryFailed = true;
          }
          binaryDecoder = null;
          binaryOutput?.close();
          binaryOutput = null;
          if (!binaryFailed && binaryKey!.isNotEmpty) {
            images[binaryKey!] = binary!;
          } else if (binary!.existsSync()) {
            binary!.deleteSync();
          }
          binary = null;
          binaryKey = null;
        }
        if (local == field) {
          final value = metadata.toString().trim();
          if (field == 'book-title' && value.isNotEmpty) {
            title = _shortLabel(value, title);
          } else if (value.isNotEmpty) {
            author = _shortLabel('$author $value', '').trim();
          }
          field = null;
          metadata.clear();
        }
        final tag = outputTags.removeLast();
        if (tag != null) spool.closeTag(tag);
        if (body && local == 'section') sectionDepth--;
        if (local == 'body') body = false;
        path.removeLast();
      },
    );
    if (!hasRoot) throw const FormatException('FB2 文件头无效');
    spool.finish();
    return (
      document: spool.file,
      title: title,
      author: author,
      images: images,
      cover: cover.isEmpty ? null : cover,
    );
  } finally {
    try {
      binaryDecoder?.close();
    } on FormatException {
      /* Failed binary remains a missing-picture warning. */
    }
    binaryOutput?.close();
    spool.close();
  }
}

Future<_MarkupResources> _docxResources(_MarkupJob job, Directory work) async {
  final input = InputFileStream(job.source);
  late List<Uint8List> rawNames;
  try {
    _preflightDirectory(input);
    final zip = ZipDirectory()..read(input);
    var total = 0;
    for (final header in zip.fileHeaders) {
      if (header.uncompressedSize < 0 ||
          header.uncompressedSize > 40 * 1024 * 1024 ||
          total + header.uncompressedSize > _maxExpanded ||
          (header.externalFileAttributes >> 16) & 0xf000 == 0xa000) {
        throw const FormatException('DOCX 含不安全文件或解压后超过大小限制');
      }
      total += header.uncompressedSize;
    }
    rawNames = _rawDirectoryNames(input, zip);
  } finally {
    input.closeSync();
  }
  final names = <String>[];
  for (var start = 0; start < rawNames.length; start += 64) {
    final chunk = rawNames.sublist(
      start,
      math.min(start + 64, rawNames.length),
    );
    if (job.token == null) {
      names.addAll(chunk.map(utf8.decode));
    } else {
      final decoded = await _MarkupResources.channel.invokeListMethod<String>(
        'decodeBookNames',
        {'names': chunk},
      );
      if (decoded == null || decoded.length != chunk.length) {
        throw const FormatException('DOCX 文件目录无法读取');
      }
      names.addAll(decoded);
    }
  }
  _validateArchiveNames(names);
  return _MarkupResources((
    name: job.name,
    source: job.source,
    directory: job.directory,
    archive: job.source,
    member: 'word/document.xml',
    names: names,
    token: job.token,
  ), work);
}

typedef _WordRelations = Map<String, ({String path, String type})>;

Future<_WordRelations> _wordRelations(
  _MarkupResources resources,
  String document,
) async {
  final split = document.lastIndexOf('/');
  final relPath =
      '${document.substring(0, split + 1)}_rels/${document.substring(split + 1)}.rels';
  final file = resources.asset(relPath, 40 * 1024 * 1024);
  final values = <String, ({String path, String type})>{};
  if (file == null) return values;
  await resources.withDecoded(
    file,
    40 * 1024 * 1024,
    (decoded) => _structuredXml(
      decoded,
      start: (name, attrs) {
        if (name != 'Relationship' ||
            _attr(attrs, 'TargetMode')?.toLowerCase() == 'external') {
          return;
        }
        final id = _attr(attrs, 'Id'), target = _attr(attrs, 'Target');
        if (id == null || target == null) return;
        final ref = resources.reference(document, target);
        if (ref != null && ref.fragment.isEmpty) {
          values[id] = (path: ref.path, type: _attr(attrs, 'Type') ?? '');
        }
      },
      text: (_) {},
      end: (_) {},
    ),
  );
  return values;
}

class _WordStyles {
  final definitions = <String, Map<String, String>>{};
  final defaults = <String, String>{};
  final _resolved = <String, Map<String, String>>{};
  Map<String, String> resolve(String id, [Set<String>? seen]) {
    if (_resolved[id] case final existing?) return existing;
    final trail = {...?seen};
    if (!trail.add(id) || trail.length > 32) return {};
    final style = definitions[id] ?? {};
    return _resolved[id] = {
      if (style['basedOn'] case final base?) ...resolve(base, trail),
      ...style,
    };
  }
}

MapEntry<String, String>? _wordProperty(
  String name,
  Map<String, String> attrs,
) {
  final value = _attr(attrs, 'val') ?? '';
  final on = !{'0', 'false', 'off', 'none'}.contains(value);
  return switch (name) {
    'b' => MapEntry('font-weight', on ? 'bold' : 'normal'),
    'i' => MapEntry('font-style', on ? 'italic' : 'normal'),
    'u' => MapEntry('text-decoration', on ? 'underline' : 'none'),
    'vanish' => MapEntry('display', on ? 'none' : 'inline'),
    'jc' => MapEntry('text-align', value == 'both' ? 'justify' : value),
    'outlineLvl' => MapEntry('outline', value),
    'basedOn' => MapEntry('basedOn', value),
    'pageBreakBefore' when on => const MapEntry('break-before', 'page'),
    'textDirection' => MapEntry(
      'writing-mode',
      value.toLowerCase().startsWith('tb') && value.toLowerCase() != 'tblr'
          ? 'vertical-rl'
          : 'horizontal-tb',
    ),
    _ => null,
  };
}

String _wordCss(Map<String, String> properties) => properties.entries
    .where((e) => !{'outline', 'basedOn', 'name'}.contains(e.key))
    .map((e) => '${e.key}:${e.value}')
    .join(';');

Future<_WordStyles> _readWordStyles(_MarkupResources resources) async {
  final styles = _WordStyles(), path = <String>[];
  final file = resources.asset('word/styles.xml', 40 * 1024 * 1024);
  if (file == null) return styles;
  String? id;
  await resources.withDecoded(
    file,
    40 * 1024 * 1024,
    (decoded) => _structuredXml(
      decoded,
      start: (local, attrs) {
        path.add(local);
        if (local == 'style') {
          id = _attr(attrs, 'styleId');
          if (id != null) {
            if (styles.definitions.length >= 20000) {
              throw const FormatException('DOCX 样式过多');
            }
            styles.definitions[id!] = {};
          }
        }
        final property = _wordProperty(local, attrs);
        if (property != null) {
          if (id != null) {
            styles.definitions[id!]![property.key] = property.value;
          } else if (path.contains('docDefaults')) {
            styles.defaults[property.key] = property.value;
          }
        }
      },
      text: (_) {},
      end: (local) {
        if (local == 'style') id = null;
        path.removeLast();
      },
    ),
  );
  return styles;
}

class _WordParagraph {
  _WordParagraph(this.defaults);
  final Map<String, String> defaults;
  String style = '', runStyle = '';
  final properties = <String, String>{}, runProperties = <String, String>{};
  final nodes = <dom.Node>[];
  dom.Element? run;
  int characters = 0, fragments = 0;
  void newRun() {
    run = null;
    runStyle = '';
    runProperties.clear();
  }

  dom.Element span(_WordStyles styles) {
    if (run case final existing?) return existing;
    final span = dom.Element.tag('span')
      ..attributes['style'] = _wordCss({
        ...styles.resolve(runStyle),
        ...runProperties,
      });
    nodes.add(span);
    return run = span;
  }

  void flush(_DocumentSpool spool, _WordStyles styles) {
    if (nodes.isEmpty) return;
    final resolved = {...defaults, ...styles.resolve(style), ...properties};
    final outline =
        int.tryParse(resolved['outline'] ?? '') ??
        ((RegExp(r'heading|标题', caseSensitive: false).hasMatch(style)) ? 0 : 9);
    final tag = fragments == 0 && outline >= 0 && outline < 9
        ? 'h${math.min(outline + 1, 6)}'
        : 'p';
    final element = dom.Element.tag(tag)
      ..attributes['style'] = _wordCss(resolved);
    for (final node in nodes) {
      element.append(node);
    }
    spool.node(element);
    nodes.clear();
    run = null;
    characters = 0;
    fragments++;
  }
}

Future<void> _readWordBody(
  File source,
  _DocumentSpool spool,
  _WordStyles styles,
  _WordRelations relations,
  _MarkupResources resources,
  Map<String, File> images, {
  String? noteKind,
}) async {
  final path = <String>[], paragraphs = <_WordParagraph>[];
  var noteVisible = false, skipAlternate = 0;
  String width = '', height = '';
  StringBuffer? rubyBase, rubyReading;
  _WordParagraph? current() => paragraphs.isEmpty ? null : paragraphs.last;
  bool visible() =>
      !path.contains('del') &&
      skipAlternate == 0 &&
      (noteKind == null || noteVisible);
  void flush() => current()?.flush(spool, styles);
  void text(String value) {
    if (!visible() || current() == null) return;
    if (rubyBase != null) {
      if (path.contains('rt')) {
        rubyReading!.write(value);
      } else if (path.contains('rubyBase')) {
        rubyBase!.write(value);
      }
      if (rubyBase!.length + rubyReading!.length > 1024 * 1024) {
        throw const FormatException('DOCX 单条注音过大');
      }
      return;
    }
    current()!.span(styles).append(dom.Text(value));
    current()!.characters += value.length;
    if (current()!.characters >= 64000) flush();
  }

  await _structuredXml(
    source,
    start: (local, attrs) {
      if (path.isEmpty &&
          local != (noteKind == null ? 'document' : '${noteKind}s')) {
        throw const FormatException('DOCX 正文或注释结构无效');
      }
      path.add(local);
      if (local == 'Fallback') skipAlternate++;
      if (local == noteKind) {
        final id = _attr(attrs, 'id') ?? '';
        noteVisible =
            !{
              'separator',
              'continuationSeparator',
              'continuationNotice',
            }.contains(_attr(attrs, 'type')) &&
            (int.tryParse(id) ?? -1) >= 0;
        if (noteVisible) {
          spool.open('aside', {
            'epub:type': 'footnote',
            'id': 'docx-$noteKind-$id',
          });
        }
      }
      if (!visible()) return;
      if (local == 'ruby') {
        if (rubyBase != null) throw const FormatException('DOCX 不支持嵌套注音');
        rubyBase = StringBuffer();
        rubyReading = StringBuffer();
      }
      if (local == 'p') {
        flush();
        paragraphs.add(_WordParagraph(styles.defaults));
        return;
      }
      final paragraph = current();
      if (local == 'r') paragraph?.newRun();
      if (local == 'pStyle') paragraph?.style = _attr(attrs, 'val') ?? '';
      if (local == 'rStyle') paragraph?.runStyle = _attr(attrs, 'val') ?? '';
      if (path.contains('pPr') || path.contains('rPr')) {
        final property = _wordProperty(local, attrs);
        if (property != null && paragraph != null) {
          (path.contains('rPr')
                  ? paragraph.runProperties
                  : paragraph.properties)[property.key] =
              property.value;
        }
      }
      if (local == 'tab') text('\u2003');
      if (local == 'br') {
        if (_attr(attrs, 'type') == 'page') {
          flush();
          spool.open('p', {'style': 'break-before:page'});
          spool.closeTag('p');
        } else {
          paragraph?.span(styles).append(dom.Element.tag('br'));
        }
      }
      if (local == 'drawing' || local == 'pict') {
        width = '';
        height = '';
      }
      if (local == 'extent') {
        final cx = double.tryParse(_attr(attrs, 'cx') ?? ''),
            cy = double.tryParse(_attr(attrs, 'cy') ?? '');
        width = cx == null ? '' : '${cx / 9525}px';
        height = cy == null ? '' : '${cy / 9525}px';
      }
      if (local == 'blip' || local == 'imagedata') {
        final id = _attr(attrs, local == 'blip' ? 'embed' : 'id') ?? '';
        final relation = relations[id];
        final key = relation?.path ?? 'missing:$id';
        if (!images.containsKey(key) && relation != null) {
          try {
            final file = resources.asset(relation.path, 8 * 1024 * 1024);
            if (file != null) images[key] = file;
          } on FormatException {
            /* Preserve the paragraph and report the missing image. */
          }
        }
        paragraph
            ?.span(styles)
            .append(
              dom.Element.tag('img')
                ..attributes.addAll({
                  'data-image-key': key,
                  if (width.isNotEmpty || height.isNotEmpty)
                    'style':
                        '${width.isEmpty ? '' : 'width:$width;'}${height.isEmpty ? '' : 'height:$height;'}',
                }),
            );
      }
      if (local == 'footnoteReference' || local == 'endnoteReference') {
        final kind = local == 'footnoteReference' ? 'footnote' : 'endnote';
        final id = _attr(attrs, 'id') ?? '';
        paragraph
            ?.span(styles)
            .append(
              dom.Element.tag('a')
                ..attributes.addAll({
                  'epub:type': 'noteref',
                  'href': '#docx-$kind-$id',
                })
                ..append(dom.Text('〔$id〕')),
            );
      }
      if (local == 'bookmarkStart') {
        final id = _attr(attrs, 'name');
        if (id != null) {
          paragraph?.span(styles).append(dom.Element.tag('span')..id = id);
        }
      }
      if ({'tbl', 'tr', 'tc'}.contains(local)) {
        flush();
        spool.open(switch (local) {
          'tbl' => 'table',
          'tc' => 'td',
          _ => 'tr',
        });
      }
    },
    text: (value) {
      if (path.lastOrNull == 't') text(value);
    },
    end: (local) {
      if (visible()) {
        if (local == 'ruby' && rubyBase != null) {
          final base = rubyBase.toString(), reading = rubyReading.toString();
          final ruby = dom.Element.tag('ruby')..append(dom.Text(base));
          if (reading.isNotEmpty) {
            ruby.append(dom.Element.tag('rt')..append(dom.Text(reading)));
          }
          current()?.span(styles).append(ruby);
          if (current() case final paragraph?) {
            paragraph.characters += base.length;
          }
          rubyBase = null;
          rubyReading = null;
        }
        if (local == 'p' && paragraphs.isNotEmpty) {
          flush();
          paragraphs.removeLast();
        }
        if ({'tbl', 'tr', 'tc'}.contains(local)) {
          flush();
          spool.closeTag(switch (local) {
            'tbl' => 'table',
            'tc' => 'td',
            _ => 'tr',
          });
        }
      }
      if (local == noteKind && noteVisible) {
        flush();
        spool.closeTag('aside');
        noteVisible = false;
      }
      if (local == 'Fallback') skipAlternate--;
      path.removeLast();
    },
  );
}

Future<_StructuredBook> _readDocx(
  _MarkupResources resources,
  Directory work,
  String name,
) async {
  final main = resources.asset('word/document.xml', 40 * 1024 * 1024);
  if (main == null) throw const FormatException('DOCX 缺少正文，文件可能损坏或已加密');
  var title = name.replaceFirst(RegExp(r'\.[^.]+$'), ''), author = '';
  final core = resources.asset('docProps/core.xml', 40 * 1024 * 1024);
  if (core != null) {
    String? field;
    final value = StringBuffer();
    await resources.withDecoded(
      core,
      40 * 1024 * 1024,
      (file) => _structuredXml(
        file,
        start: (local, _) {
          if ({'title', 'creator'}.contains(local)) {
            field = local;
            value.clear();
          }
        },
        text: (text) {
          if (field != null && value.length < 4096) {
            value.write(
              text.substring(0, math.min(text.length, 4096 - value.length)),
            );
          }
        },
        end: (local) {
          if (local == field) {
            if (local == 'title') {
              title = _shortLabel(value.toString(), title);
            } else {
              author = _shortLabel(value.toString(), '');
            }
            field = null;
          }
        },
      ),
    );
  }
  final styles = await _readWordStyles(resources);
  final spool = _DocumentSpool(File('${work.path}/word.xml'));
  final images = <String, File>{};
  try {
    final relations = await _wordRelations(resources, 'word/document.xml');
    await resources.withDecoded(
      main,
      40 * 1024 * 1024,
      (file) =>
          _readWordBody(file, spool, styles, relations, resources, images),
    );
    for (final kind in ['footnote', 'endnote']) {
      final relation = relations.values
          .where((r) => r.type.endsWith('/${kind}s'))
          .firstOrNull;
      final path = relation?.path ?? 'word/${kind}s.xml';
      final file = resources.asset(path, 40 * 1024 * 1024);
      if (file != null) {
        final noteRelations = await _wordRelations(resources, path);
        await resources.withDecoded(
          file,
          40 * 1024 * 1024,
          (decoded) => _readWordBody(
            decoded,
            spool,
            styles,
            noteRelations,
            resources,
            images,
            noteKind: kind,
          ),
        );
      }
    }
    spool.finish();
    return (
      document: spool.file,
      title: title,
      author: author,
      images: images,
      cover: null,
    );
  } finally {
    spool.close();
  }
}
