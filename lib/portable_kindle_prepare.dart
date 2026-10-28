part of 'portable_book_prepare.dart';

bool _isKindle(String name) =>
    RegExp(r'\.(mobi|azw|azw3|prc)$', caseSensitive: false).hasMatch(name);

extension on PortableBookPreparer {
  Future<PreparedBookDocument> _kindle(
    String name,
    String source,
    Directory job,
  ) => _nativeResources(name, source, job, 'kindle', 'Kindle', (
    input,
    output,
  ) async {
    final status = await extractKindle!(input, output);
    if (status != 0) {
      throw FormatException(switch (status) {
        1 => '此 Kindle 书籍受 DRM 保护，无法导入；请使用无 DRM 的合法原文件',
        3 => 'Kindle 正文或资源展开后超过安全大小限制',
        4 => 'Kindle 转换无法写入，请检查剩余空间后重试',
        _ => 'Kindle 原书格式损坏或不受支持，请检查原文件',
      });
    }
  });

  Future<PreparedBookDocument> _pdf(
    String name,
    String source,
    Directory job,
  ) => _nativeResources(
    name,
    source,
    job,
    'pdf',
    'PDF',
    (input, output) => extractPdf!(name, input, output),
  );

  Future<PreparedBookDocument> _nativeResources(
    String name,
    String source,
    Directory job,
    String kind,
    String label,
    Future<void> Function(String input, String output) extract,
  ) async {
    final length = await File(source).length();
    if (length < 1) throw FormatException('$label 原书为空，请检查原文件');
    if (length > localBookByteLimit(name)) {
      throw FormatException(
        '$label 原书超过 ${localBookByteLimit(name) ~/ (1024 * 1024)} MiB，请拆分后导入',
      );
    }
    final work = await job.createTemp('$kind-');
    final resources = await Directory('${work.path}/OEBPS').create();
    final output = File('${work.path}.epub');
    try {
      // Hosts extract on background workers; packaging never blocks Flutter's
      // UI isolate. The caller's source stays under its original owner.
      await extract(source, resources.path);
      await compute(_packageNativeBook, (
        directory: resources.path,
        output: output.path,
        kind: kind,
        label: label,
      ), debugLabel: 'local-$kind-epub');
      return (
        name: name.replaceFirst(RegExp(r'\.[^.]+$'), '.epub'),
        path: output.path,
        error: null,
      );
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      if (await work.exists()) await work.delete(recursive: true);
    }
  }
}

void _packageNativeBook(
  ({String directory, String output, String kind, String label}) job,
) {
  final directory = Directory(job.directory);
  if (directory.resolveSymbolicLinksSync() != directory.path) {
    throw FormatException('${job.label} 转换资源路径已变化，未读取外部文件');
  }
  final files = <File>[];
  var total = 0;
  for (final entry in directory.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.last;
    if (entry is! File ||
        !RegExp(
          r'^(content\.opf|(?:part|flow|resource)[0-9]+\.[a-z0-9]+)$',
        ).hasMatch(name) ||
        entry.resolveSymbolicLinksSync() != entry.path) {
      throw FormatException('${job.label} 转换资源包含无效路径');
    }
    final size = entry.lengthSync();
    final maximum = job.kind == 'pdf' ? _maxExpanded : maxLocalEpubBytes;
    if (size > 40 * 1024 * 1024 || size > maximum - total) {
      throw FormatException('${job.label} 资源展开后超过安全大小限制');
    }
    total += size;
    files.add(entry);
    if (files.length > (job.kind == 'pdf' ? 30000 : 12000)) {
      throw FormatException('${job.label} 资源数量过多');
    }
  }
  if (!files.any((file) => file.uri.pathSegments.last == 'content.opf') ||
      !files.any(
        (file) => RegExp(r'/part[0-9]+\.(html|xhtml)$').hasMatch(file.path),
      )) {
    throw FormatException('${job.label} 转换结果缺少书目或正文');
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  final output = _PortableEpubOutput(File(job.output));
  try {
    output.add(
      ArchiveFile.string('mimetype', 'application/epub+zip')
        ..compression = CompressionType.none,
    );
    output.text(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    for (final file in files) {
      output.resource('OEBPS/${file.uri.pathSegments.last}', file);
    }
    output.finish();
  } finally {
    output.close();
  }
}
