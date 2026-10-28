part of 'portable_book_prepare.dart';

bool _isMarkup(String name) => RegExp(
  r'\.(html?|xhtml|md|markdown)$',
  caseSensitive: false,
).hasMatch(name);

bool _markupNoteReference(dom.Element node) =>
    epubSemantic(
      node,
    ).split(RegExp(r'\s+')).any({'noteref', 'doc-noteref'}.contains) ||
    node.attributes['rel'] == 'footnote';

typedef _MarkupJob = ({
  String name,
  String source,
  String directory,
  String? archive,
  String? member,
  List<String> names,
  RootIsolateToken? token,
});

/// Parse, resolve only granted archive resources, and write disk-backed EPUB
/// chapters off the UI isolate. No web view, HTTP fetch or neighbour-file access.
Future<({String path, List<String> companions})> _prepareMarkup(
  _MarkupJob job,
) async {
  if (job.token case final token?) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  }
  final work = Directory(job.directory).createTempSync('markup-');
  final resources = _MarkupResources(job, work);
  _MarkupWriter? writer;
  final output = File(
    '${job.directory}/${work.uri.pathSegments.where((s) => s.isNotEmpty).last}.epub',
  );
  try {
    final source = await resources.text(
      File(job.source),
      localBookByteLimit(job.name),
    );
    final isMarkdown = bookFormatKey(job.name) == 'markdown';
    final document = html.parse(
      isMarkdown
          ? markdown.markdownToHtml(
              source,
              extensionSet: markdown.ExtensionSet.gitHubWeb,
            )
          : source,
    );
    final fallback = job.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final title = _shortLabel(
      document.querySelector('title')?.text ?? '',
      fallback,
    );
    final author =
        document.querySelector('meta[name="author"]')?.attributes['content'] ??
        '';
    writer = _MarkupWriter(work, title);
    final documentPath = job.member ?? job.name;
    final auxiliary = <String, dom.Document>{};
    final companions = <String>[];
    // Read explicitly linked local note documents, never arbitrary web pages.
    // They are non-linear EPUB resources, not extra chapters in this book.
    for (final anchor in document.querySelectorAll('a[href]')) {
      final ref = resources.reference(documentPath, anchor.attributes['href']!);
      if (ref == null ||
          ref.fragment.isEmpty ||
          ref.path == documentPath ||
          auxiliary.containsKey(ref.path)) {
        continue;
      }
      if (!RegExp(
            r'\.(html?|xhtml|xht)$',
            caseSensitive: false,
          ).hasMatch(ref.path) &&
          !_markupNoteReference(anchor)) {
        continue;
      }
      if (auxiliary.length >= 32) {
        throw const FormatException('注释文档过多，请拆分 HTML 后导入');
      }
      final file = resources.asset(ref.path, 1024 * 1024);
      if (file == null) continue;
      final noteDocument = html.parse(await resources.text(file, 1024 * 1024));
      final note = noteDocument.getElementById(ref.fragment);
      if (note != null &&
          (epubNoteElement(note) ||
              _markupNoteReference(anchor) ||
              anchor.attributes['rel'] == 'footnote')) {
        auxiliary[ref.path] = noteDocument;
        final remainder = noteDocument.body!.clone(true);
        for (final element
            in remainder.querySelectorAll('*').where(epubNoteElement)) {
          element.remove();
        }
        for (final element in remainder.querySelectorAll(
          'script, style, nav',
        )) {
          element.remove();
        }
        if (remainder.text.trim().isEmpty) companions.add(ref.path);
      }
    }
    await resources.sanitize(document, documentPath, writer);
    writer.visit(document.body!, documentPath);
    writer.finish();
    for (final entry in auxiliary.entries) {
      await resources.sanitize(entry.value, entry.key, writer);
      writer.auxiliary(entry.value.body!, entry.key);
    }
    writer.resolveLinks();
    _writeMarkupEpub(output, title, author, writer, resources);
    return (path: output.path, companions: companions);
  } catch (_) {
    if (output.existsSync()) output.deleteSync();
    rethrow;
  } finally {
    writer?.abort();
    resources.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}

String _shortLabel(String text, String fallback) {
  final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final selected = value.isEmpty ? fallback : value;
  if (selected.length <= 200) return selected;
  final unit = selected.codeUnitAt(199);
  return selected.substring(0, unit >= 0xd800 && unit <= 0xdbff ? 199 : 200);
}

String _xml(String text) => const HtmlEscape().convert(
  text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ''),
);

class _MarkupResources {
  _MarkupResources(this.job, this.work);
  final _MarkupJob job;
  final Directory work;
  InputFileStream? _input;
  ZipDirectory? _directory;
  final _assets = <String, File>{};
  final _images = <String, ({File file, String type})>{};
  final _imageNames = <String, String>{};
  final _styles = <String, String>{};
  String? cover;
  int _expanded = 0, _missing = 0;
  static const channel = MethodChannel('org.mewx.wenku8/book_documents');

  Future<String> text(File file, int maximum) async {
    return withDecoded(file, maximum, (decoded) {
      if (decoded.lengthSync() > 64 * 1024 * 1024) {
        throw const FormatException('转换后的 HTML 过大，请拆分后导入');
      }
      return decoded.readAsStringSync();
    });
  }

  Future<T> withDecoded<T>(
    File file,
    int maximum,
    FutureOr<T> Function(File) read, {
    String? encoding,
  }) async {
    if (file.lengthSync() < 1 || file.lengthSync() > maximum) {
      throw const FormatException('文档为空或超过此格式的大小限制');
    }
    final handle = file.openSync();
    late List<int> sample;
    try {
      sample = handle.readSync(math.min(65536, file.lengthSync()));
    } finally {
      handle.closeSync();
    }
    final charset = encoding ?? _markupCharset(sample);
    // Isolated Dart fixtures use strict UTF-8/UTF-16; production always supplies
    // a root token and uses the native streaming legacy codec below.
    if (job.token == null) {
      final decoded = File('${work.path}/fixture-decoded-${_serialDecoded++}');
      try {
        decoded.writeAsStringSync(decodeLocalMarkup(file.readAsBytesSync()));
        return await read(decoded);
      } finally {
        if (decoded.existsSync()) decoded.deleteSync();
      }
    }
    final decoded = await channel.invokeMethod<String>('decodeTextFile', {
      'path': file.path,
      'encoding': charset,
      'maximumInputBytes': maximum,
      'maximumOutputBytes': math.min(_maxExpanded, maximum * 3),
    });
    if (decoded == null) throw const FormatException('文字编码转换没有返回文件，请重试');
    try {
      final result = File(decoded);
      if (result.lengthSync() > math.min(_maxExpanded, maximum * 3)) {
        throw const FormatException('转换后的文档超过大小限制，请拆分后导入');
      }
      return await read(result);
    } finally {
      await channel.invokeMethod<void>('releaseBooks', {
        'paths': [decoded],
      });
    }
  }

  int _serialDecoded = 0;

  String fileImage(String key, File? file, {bool isCover = false}) {
    if (_imageNames[key] case final existing?) return existing;
    if (file != null && file.lengthSync() <= 8 * 1024 * 1024) {
      final input = file.openSync();
      late List<int> header;
      try {
        header = input.readSync(12);
      } finally {
        input.closeSync();
      }
      final kind = _markupImageKind(header);
      if (kind != null) {
        final name = 'image-${_images.length}.${kind.extension}';
        _images[name] = (file: file, type: kind.type);
        _imageNames[key] = name;
        if (isCover) cover = name;
        return name;
      }
    }
    return _imageNames[key] = 'unavailable-image-${_missing++}.png';
  }

  ({String path, String fragment})? reference(String base, String value) {
    if (value.trim().isEmpty || value.contains('\\')) return null;
    try {
      final raw = Uri.parse(value.trim());
      if (raw.hasScheme || raw.hasAuthority) return null;
      final baseUri = Uri(
        scheme: 'https',
        host: 'local.invalid',
        pathSegments: ['', ...base.split('/')],
      );
      final resolved = baseUri.resolveUri(raw);
      final path = resolved.pathSegments.join('/');
      _validateArchivePath(path);
      return (path: path, fragment: resolved.fragment);
    } on FormatException {
      return null;
    }
  }

  File? asset(String path, int maximum) {
    if (_assets[path] case final existing?) {
      if (existing.lengthSync() > maximum) {
        throw const FormatException('HTML 关联资源过大');
      }
      return existing;
    }
    if (job.archive == null) return null;
    _input ??= InputFileStream(job.archive!);
    if (_directory == null) {
      _preflightDirectory(_input!);
      _directory = ZipDirectory()..read(_input!);
      if (_directory!.fileHeaders.length != job.names.length) {
        throw const FormatException('ZIP 目录已变化，请重新选择');
      }
    }
    final index = job.names.indexOf(path);
    if (index < 0) return null;
    if (job.names.indexOf(path, index + 1) >= 0) {
      throw const FormatException('ZIP 内存在同路径的重复资源，无法确定对应图片');
    }
    final file = File('${work.path}/asset-${_assets.length}');
    final header = _directory!.fileHeaders[index];
    _writeZipEntry(header, file, math.min(maximum, _maxExpanded - _expanded));
    _expanded += header.uncompressedSize;
    _assets[path] = file;
    return file;
  }

  Future<String?> stylesheet(
    String base,
    String href, [
    Set<String>? trail,
  ]) async {
    final ref = reference(base, href);
    if (ref == null) return null;
    if (_styles[ref.path] case final cached?) return cached;
    final visited = {...?trail};
    if (!visited.add(ref.path)) return '';
    if (visited.length > 8 || _styles.length >= 32) {
      throw const FormatException('HTML 样式引用过多，请简化后导入');
    }
    final file = asset(ref.path, 1024 * 1024);
    if (file == null) return null;
    var css = await text(file, 1024 * 1024);
    final imports = RegExp(
      r'''@import\s+(?:url\(\s*)?["']([^"']+)["']\s*\)?\s*;''',
      caseSensitive: false,
    );
    final prefix = StringBuffer();
    for (final match in imports.allMatches(css)) {
      prefix.writeln(await stylesheet(ref.path, match[1]!, visited) ?? '');
    }
    css = '${prefix.toString()}${css.replaceAll(imports, '')}';
    if (css.length > 4 * 1024 * 1024) {
      throw const FormatException('HTML 合并样式过大，请简化后导入');
    }
    return _styles[ref.path] = css;
  }

  Future<String> image(String base, String src) async {
    final ref = reference(base, src);
    final key = ref?.path ?? src;
    if (_imageNames[key] case final cached?) return cached;
    File? file;
    try {
      if (src.toLowerCase().startsWith('data:image/')) {
        if (src.length > 12 * 1024 * 1024) {
          throw const FormatException('内嵌图片过大');
        }
        final uri = UriData.parse(src);
        final bytes = uri.contentAsBytes();
        if (bytes.length > 8 * 1024 * 1024) {
          throw const FormatException('图片超过 8 MiB');
        }
        file = File('${work.path}/inline-${_images.length}')
          ..writeAsBytesSync(bytes);
      } else if (ref != null) {
        file = asset(ref.path, 8 * 1024 * 1024);
      }
      if (file != null) {
        final handle = file.openSync();
        late List<int> header;
        try {
          header = handle.readSync(12);
        } finally {
          handle.closeSync();
        }
        final kind = _markupImageKind(header);
        if (kind != null) {
          if (_images.length >= 4096) {
            throw const FormatException('HTML 图片过多，请拆分后导入');
          }
          final name = 'image-${_images.length}.${kind.extension}';
          _images[name] = (file: file, type: kind.type);
          return _imageNames[key] = name;
        }
      }
    } on FormatException {
      // Existing EPUB import warnings report unavailable pictures while keeping
      // the surrounding prose. Never substitute a network image fetch.
    }
    return _imageNames[key] = 'unavailable-image-${_missing++}.png';
  }

  Future<void> sanitize(
    dom.Document doc,
    String base,
    _MarkupWriter writer,
  ) async {
    final elements = doc.querySelectorAll('*');
    if (elements.length > 200000) {
      throw const FormatException('HTML 结构过于复杂，请拆分后导入');
    }
    final sheets = <String, String>{};
    for (final link in doc.querySelectorAll('link[rel~="stylesheet"]')) {
      final href = link.attributes['href'] ?? '';
      final value = await stylesheet(base, href);
      if (value != null) sheets[href] = value;
    }
    final properties = epubStyleProperties(doc, (href) => sheets[href]);
    const dropped = {
      'script',
      'style',
      'head',
      'noscript',
      'iframe',
      'frame',
      'object',
      'embed',
      'applet',
      'form',
      'input',
      'button',
      'select',
      'textarea',
      'base',
      'meta',
      'link',
      'nav',
    };
    const allowed = {
      'id',
      'lang',
      'dir',
      'role',
      'epub:type',
      'rel',
      'href',
      'alt',
      'width',
      'height',
      'hidden',
    };
    for (final element in elements.where(
      (element) => dropped.contains(element.localName),
    )) {
      element.remove();
    }
    // Re-list after pruning so web UI and script subtrees cannot make us
    // decode their image payloads or manufacture extra book resources.
    for (final element in [doc.body!, ...doc.body!.querySelectorAll('*')]) {
      if (dropped.contains(element.localName)) {
        element.remove();
        continue;
      }
      if (element.localName == 'image') {
        // SVG wrappers containing a raster image are common in exported HTML.
        element.attributes['src'] =
            element.attributes['href'] ??
            element.attributes['xlink:href'] ??
            '';
      }
      final src = element.attributes['src'];
      final isImage =
          element.localName == 'img' || element.localName == 'image';
      final imagePath = isImage ? await image(base, src ?? '') : null;
      final href = element.attributes['href'];
      final retained = <String, String>{};
      for (final entry in element.attributes.entries) {
        final key = entry.key.toString();
        if (allowed.contains(key)) retained[key] = entry.value;
      }
      element.attributes.clear();
      element.attributes.addAll(retained);
      if (imagePath != null) element.attributes['src'] = imagePath;
      if (href != null && !isImage) {
        final target = reference(base, href);
        element.attributes.remove('href');
        if (target != null) {
          element.attributes['href'] = writer.link(
            '${target.path}#${target.fragment}',
          );
        }
      }
      final styles = properties[element] ?? const <String, String>{};
      final safe = styles.entries.where(
        (entry) => !RegExp(
          r'url\s*\(|expression|[<>]',
          caseSensitive: false,
        ).hasMatch(entry.value),
      );
      final inline = safe
          .map((entry) => '${entry.key}:${entry.value}')
          .join(';');
      if (inline.isNotEmpty) element.attributes['style'] = inline;
    }
  }

  void close() => _input?.closeSync();
}

String _markupCharset(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return 'UTF-8';
  }
  if (bytes.length >= 4 &&
      (bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xfe && bytes[3] == 0xff ||
          bytes[0] == 0xff &&
              bytes[1] == 0xfe &&
              bytes[2] == 0 &&
              bytes[3] == 0)) {
    throw const FormatException('暂不支持 UTF-32 HTML，请转换为 UTF-8 后导入');
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 0xff && bytes[1] == 0xfe) return 'UTF-16LE';
    if (bytes[0] == 0xfe && bytes[1] == 0xff) return 'UTF-16BE';
    if (bytes.length >= 4) {
      if (bytes[0] == 60 && bytes[1] == 0 && bytes[3] == 0) return 'UTF-16LE';
      if (bytes[0] == 0 && bytes[1] == 60 && bytes[2] == 0) return 'UTF-16BE';
    }
  }
  // Charset-looking words in prose are not a file encoding declaration.
  final ascii = RegExp(
    r'<(?:meta\b|\?xml\b)[^>]*>',
    caseSensitive: false,
  ).allMatches(latin1.decode(bytes)).map((m) => m[0]!).join('\n');
  final label = RegExp(
    r'''(?:charset\s*=\s*["']?\s*|encoding\s*=\s*["'])([a-zA-Z0-9_-]+)''',
    caseSensitive: false,
  ).firstMatch(ascii)?[1]?.toLowerCase();
  if (label == null) return 'auto';
  return switch (label) {
    'utf8' || 'utf-8' => 'UTF-8',
    'utf16' || 'utf-16' || 'utf-16le' => 'UTF-16LE',
    'utf-16be' => 'UTF-16BE',
    'gb2312' || 'gbk' || 'gb18030' || 'cp936' => 'GB18030',
    'big5' || 'big-5' => 'Big5',
    'big5-hkscs' => 'Big5-HKSCS',
    'shift_jis' || 'shift-jis' || 'sjis' || 'windows-31j' || 'cp932' => 'CP932',
    'euc-jp' || 'euc_jp' => 'EUC-JP',
    'windows-1252' || 'cp1252' => 'WINDOWS-1252',
    'iso-8859-1' || 'latin1' => 'ISO-8859-1',
    'koi8-r' || 'koi8r' => 'KOI8-R',
    final name when RegExp(r'^(?:windows-|cp)125[0-8]$').hasMatch(name) =>
      'WINDOWS-${name.substring(name.length - 4)}',
    _ => throw FormatException('暂不支持声明的文字编码：$label，请转换为 UTF-8 后导入'),
  };
}

({String extension, String type})? _markupImageKind(List<int> b) {
  if (b.length < 4) return null;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
    return (extension: 'png', type: 'image/png');
  }
  if (b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return (extension: 'jpg', type: 'image/jpeg');
  }
  if (ascii.decode(b.take(3).toList(), allowInvalid: true) == 'GIF') {
    return (extension: 'gif', type: 'image/gif');
  }
  if (b.length >= 12 &&
      ascii.decode(b.take(4).toList(), allowInvalid: true) == 'RIFF' &&
      ascii.decode(b.skip(8).take(4).toList(), allowInvalid: true) == 'WEBP') {
    return (extension: 'webp', type: 'image/webp');
  }
  return null;
}

typedef _MarkupChapter = ({File file, String href, String title});
typedef _MarkupTag = ({String name, String open});

class _MarkupWriter {
  _MarkupWriter(this.directory, this.title);
  final Directory directory;
  final String title;
  final chapters = <_MarkupChapter>[];
  final notes = <_MarkupChapter>[];
  final _stack = <_MarkupTag>[];
  final _ids = <String, String>{};
  final _links = <String, String>{};
  RandomAccessFile? _sink;
  String _label = '', _href = '';
  int _characters = 0, _serial = 0;
  bool _readable = false, _auxiliary = false;

  String link(String key) {
    final token = '__paper_reference_${_links.length}__';
    _links[token] = key;
    return token;
  }

  void _write(String value) => _sink!.writeStringSync(value);
  void _begin() {
    if (_serial >= 10000) throw const FormatException('文档章节过多，请拆分后导入');
    _href = 'part-${_serial++}.xhtml';
    _sink = File('${directory.path}/$_href').openSync(mode: FileMode.write);
    _write(
      '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>${_xml(title)}</title></head><body>',
    );
    for (final tag in _stack) {
      _write(tag.open);
    }
    _characters = 0;
    _readable = false;
  }

  void _end() {
    if (_sink == null) return;
    for (final tag in _stack.reversed) {
      _write('</${tag.name}>');
    }
    _write('</body></html>');
    _sink!.closeSync();
    _sink = null;
    final file = File('${directory.path}/$_href');
    if (_readable || _auxiliary) {
      (_auxiliary ? notes : chapters).add((
        file: file,
        href: _href,
        title: _label.isEmpty ? title : _label,
      ));
    } else {
      file.deleteSync();
    }
  }

  void _split([String? label]) {
    if (_sink != null && _readable) {
      _end();
      _begin();
    }
    _label = label ?? _label;
  }

  void _id(dom.Element element, String base) {
    final id = element.id;
    if (id.isNotEmpty) {
      _ids.putIfAbsent('$base#$id', () => '$_href#${Uri.encodeComponent(id)}');
    }
    _ids.putIfAbsent('$base#', () => _href);
  }

  String _open(dom.Element element, String tag, {bool withoutId = false}) =>
      '<$tag${element.attributes.entries.where((e) => !withoutId || e.key != 'id').map((e) => ' ${e.key}="${_xml(e.value)}"').join()}>';

  static const _tags = {
    'div',
    'section',
    'article',
    'p',
    'span',
    'a',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'small',
    'sup',
    'sub',
    'pre',
    'code',
    'ul',
    'ol',
    'li',
    'dl',
    'dt',
    'dd',
    'table',
    'tbody',
    'thead',
    'tfoot',
    'tr',
    'td',
    'th',
    'br',
    'hr',
    'img',
    'aside',
    'ruby',
    'rb',
    'rt',
    'rp',
  };
  static const _void = {'br', 'hr', 'img'};

  String _tag(dom.Element element) => switch (element.localName) {
    'body' || 'svg' => 'div',
    'image' => 'img',
    final name when _tags.contains(name) => name!,
    _ => 'span',
  };

  void visit(dom.Node node, String base) {
    if (_sink == null) _begin();
    if (node is dom.Text) {
      final text = node.data;
      for (var start = 0; start < text.length;) {
        var end = math.min(start + 4000, text.length);
        if (end < text.length &&
            text.codeUnitAt(end - 1) >= 0xd800 &&
            text.codeUnitAt(end - 1) <= 0xdbff) {
          end--;
        }
        if (_characters >= 200000 && !_auxiliary) _split();
        final chunk = text.substring(start, end);
        _write(_xml(chunk));
        _characters += chunk.length;
        _readable |= chunk.trim().isNotEmpty;
        start = end;
      }
      return;
    }
    if (node is! dom.Element) return;
    if (node.attributes.containsKey('hidden') ||
        RegExp(
          r'display\s*:\s*none(?:;|$)',
        ).hasMatch(node.attributes['style'] ?? '')) {
      return;
    }
    final tag = _tag(node);
    if (RegExp(r'^h[1-6]$').hasMatch(tag) && !_auxiliary) {
      final label = node.clone(true);
      for (final phonetic in label.querySelectorAll('rt, rp')) {
        phonetic.remove();
      }
      _split(_shortLabel(label.text, title));
    }
    _id(node, base);
    if (tag == 'ruby' ||
        epubNoteElement(node) ||
        tag == 'a' && _markupNoteReference(node)) {
      final value = _atomic(node, base);
      if (value.length > 1024 * 1024) {
        throw const FormatException('单条注释或注音过大，请检查原文件');
      }
      _write(value);
      if (!epubNoteElement(node)) {
        _readable |= node.text.trim().isNotEmpty;
        _characters += node.text.length;
      }
      return;
    }
    if (_void.contains(tag)) {
      final open = _open(node, tag);
      _write('${open.substring(0, open.length - 1)}/>');
      if (tag == 'img') _readable = true;
      return;
    }
    _write(_open(node, tag));
    _stack.add((name: tag, open: _open(node, tag, withoutId: true)));
    for (final child in node.nodes) {
      visit(child, base);
    }
    _write('</$tag>');
    _stack.removeLast();
  }

  String _atomic(dom.Node node, String base) {
    if (node is dom.Text) return _xml(node.data);
    if (node is! dom.Element) return '';
    _id(node, base);
    final tag = _tag(node), open = _open(node, _tag(node));
    if (_void.contains(tag)) return '${open.substring(0, open.length - 1)}/>';
    return '$open${node.nodes.map((n) => _atomic(n, base)).join()}</$tag>';
  }

  void finish() {
    _end();
    if (chapters.isEmpty) throw const FormatException('文档中没有可阅读的正文');
  }

  void abort() {
    _sink?.closeSync();
    _sink = null;
  }

  void auxiliary(dom.Element body, String base) {
    _auxiliary = true;
    _label = title;
    visit(body, base);
    _end();
    _auxiliary = false;
  }

  void resolveLinks() {
    if (_links.isEmpty) return;
    for (final chapter in [...chapters, ...notes]) {
      final text = chapter.file.readAsStringSync().replaceAllMapped(
        RegExp(r'__paper_reference_(\d+)__'),
        (m) => _xml(_ids[_links[m[0]]] ?? '#unavailable-reference'),
      );
      chapter.file.writeAsStringSync(text);
    }
  }
}

void _writeMarkupEpub(
  File output,
  String title,
  String author,
  _MarkupWriter writer,
  _MarkupResources resources,
) {
  final sink = _PortableEpubOutput(output);
  void add(String name, String text) => sink.text(name, text);
  final manifest = StringBuffer(), spine = StringBuffer(), nav = StringBuffer();
  var coverMetadata = '';
  var size = 0, index = 0;
  void file(String name, File source) {
    size += source.lengthSync();
    if (size > _maxExpanded) {
      throw const FormatException('转换后的文档超过 1 GiB，请拆分后导入');
    }
    sink.resource('OPS/$name', source);
  }

  try {
    sink.add(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    );
    add(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    for (final chapter in [...writer.chapters, ...writer.notes]) {
      final id = 'c${index++}';
      file(chapter.href, chapter.file);
      manifest.write(
        '<item id="$id" href="${chapter.href}" media-type="application/xhtml+xml"/>',
      );
      final linear = writer.chapters.contains(chapter);
      spine.write('<itemref idref="$id"${linear ? '' : ' linear="no"'}/>');
      if (linear) {
        nav.write(
          '<li><a href="${chapter.href}">${_xml(chapter.title)}</a></li>',
        );
      }
    }
    for (final image in resources._images.entries) {
      file(image.key, image.value.file);
      final id = 'i${index++}';
      final isCover = image.key == resources.cover;
      if (isCover) coverMetadata = '<meta name="cover" content="$id"/>';
      manifest.write(
        '<item id="$id" href="${image.key}" media-type="${image.value.type}"${isCover ? ' properties="cover-image"' : ''}/>',
      );
    }
    add(
      'OPS/nav.xhtml',
      '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol>$nav</ol></nav></body></html>',
    );
    add(
      'OPS/content.opf',
      '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:local:portable-markup</dc:identifier><dc:title>${_xml(title)}</dc:title><dc:creator>${_xml(author)}</dc:creator><dc:language>und</dc:language>$coverMetadata</metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>$manifest</manifest><spine>$spine</spine></package>',
    );
    sink.finish();
  } finally {
    sink.close();
  }
}
