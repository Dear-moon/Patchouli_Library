import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

Uint8List bilingualEpubFixture() {
  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    'META-INF/container.xml',
    '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
  );
  add(
    'OPS/book.opf',
    '<package><metadata><title>双语排版测试</title><language>zh-CN</language></metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>',
  );
  add(
    'OPS/c.xhtml',
    '''<html lang="zh-CN"><head><style>.translation {opacity:40%} .group {opacity:.5}</style></head><body>
  <h1>双语排版测试</h1>
  <p>这是中文第一段，原文和译文应当可以分别显示。</p>
  <p lang="ja" style="opacity:0.4">これは日本語の段落です。</p>
  <p>这是中文第二段，隐藏日文不能改变原始坐标。</p>
  <p xml:lang="ja-JP" class="translation">日本語の二つ目の段落です。</p>
  <div class="group"><p lang="ja" style="opacity:.8">親の透明度も保持します。</p></div>
  <p lang="en">The final English paragraph stays in order.</p>
  </body></html>''',
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
