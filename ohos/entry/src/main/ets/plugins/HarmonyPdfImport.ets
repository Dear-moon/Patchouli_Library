import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import util from '@ohos.util';
import { pdfService } from '@kit.PDFKit';
import { HarmonyDocumentFailure } from './HarmonyDocumentPolicy';

interface PdfPart { name: string; label: string; }

/** System PDFKit extracts one page at a time on a TaskPool worker. */
export async function writeHarmonyPdf(name: string, source: string, output: string): Promise<void> {
  const document = new pdfService.PdfDocument();
  try {
    if (document.isEncrypted(source)) {
      throw new HarmonyDocumentFailure('pdf_protected', '不支持加密或禁止提取内容的 PDF');
    }
    const parsed = document.loadDocument(source);
    if (parsed !== pdfService.ParseResult.PARSE_SUCCESS) {
      throw new HarmonyDocumentFailure('pdf_parse', 'PDF 结构损坏或无法识别，请检查完整原文件');
    }
    const count = document.getPageCount();
    if (!Number.isSafeInteger(count) || count <= 0 || count > 10000) {
      throw new HarmonyDocumentFailure('pdf_pages', 'PDF 页数无效或超过 10000 页');
    }
    const metadata = document.getMetadata();
    const title = metadata.title?.trim() || name.replace(/\.[^.]+$/, '');
    const writer = new HarmonyPdfResources(output, title, metadata.author || '');
    for (let index = 0; index < count; index++) {
      const page = document.getPage(index);
      let objects: pdfService.GraphicsObject[] = [];
      try {
        const width = page.getWidth(), height = page.getHeight();
        if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || width > 100000 || height > 100000) {
          throw new HarmonyDocumentFailure('pdf_geometry', 'PDF 页面尺寸无效或过大');
        }
        objects = page.getGraphicsObjects();
        if (objects.length > 20000) { throw new HarmonyDocumentFailure('pdf_graphics', '单页图形对象过多'); }
        let textLength = 0;
        for (const object of objects) {
          if (object.type === pdfService.GraphicsObjectType.OBJECT_TEXT) { textLength += (object as pdfService.TextObject).text.length; }
        }
        if (textLength > 6 * 1024 * 1024) { throw new HarmonyDocumentFailure('pdf_text_limit', '单页正文过大，请拆分原书后导入'); }
        writer.beginPage(index + 1);
        // Forms, vector artwork and annotations are rendered as a complete page,
        // rather than dropping visible content not represented by text/images.
        const preservePage = textLength === 0 || objects.some((object: pdfService.GraphicsObject): boolean =>
          object.type !== pdfService.GraphicsObjectType.OBJECT_TEXT && object.type !== pdfService.GraphicsObjectType.OBJECT_IMAGE) ||
          page.getAnnotations().length > 0;
        if (preservePage) {
          const scale = Math.min(120 / 72, 1800 / Math.max(width, height));
          const matrix = new pdfService.PdfMatrix();
          matrix.x = 0; matrix.y = 0; matrix.width = Math.max(1, Math.ceil(width * scale));
          matrix.height = Math.max(1, Math.ceil(height * scale)); matrix.rotate = 0;
          const pixels = page.getCustomPagePixelMap(matrix, false, true);
          try { await writer.picture(pixels, width, height); } finally { await pixels.release(); }
        } else {
          // PDFKit returns positional reading order; do not re-sort columns by Y.
          for (const object of objects) {
            if (object.type === pdfService.GraphicsObjectType.OBJECT_TEXT) {
              await writer.text((object as pdfService.TextObject).text);
            } else {
              const graphic = object as pdfService.ImageObject;
              await writer.picture(graphic.pixelMap, graphic.width, graphic.height);
            }
          }
        }
        await writer.endPage();
      } catch (error) {
        throw new HarmonyDocumentFailure('pdf_page', 'PDF 第 ' + (index + 1) + ' 页处理失败：' + (error as Error).message);
      } finally {
        try {
          for (const object of objects) {
            if (object.type === pdfService.GraphicsObjectType.OBJECT_IMAGE) { await (object as pdfService.ImageObject).pixelMap.release(); }
          }
        } finally { page.release(); }
      }
    }
    await writer.finish();
  } finally { document.releaseDocument(); }
}

export function pdfXml(text: string): string {
  return text.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

class HarmonyPdfResources {
  private directory: string;
  private title: string;
  private author: string;
  private label: string = '';
  private body: string = '';
  private bytes: number = 0;
  private parts: PdfPart[] = [];
  private pictures: string[] = [];
  constructor(directory: string, title: string, author: string) {
    this.directory = directory; this.title = title.substring(0, 2048); this.author = author.substring(0, 2048);
  }
  beginPage(page: number): void { this.label = '第 ' + page + ' 页'; }
  async text(value: string): Promise<void> {
    for (const line of value.split(/\r\n|[\n\r]/)) {
      for (let offset = 0; offset < line.length;) {
        let end = Math.min(offset + 4000, line.length);
        if (end < line.length && /[\ud800-\udbff]/.test(line.charAt(end - 1))) { end--; }
        await this.append('<p>' + pdfXml(line.substring(offset, end)) + '</p>'); offset = end;
      }
    }
  }
  private async append(value: string): Promise<void> {
    if (this.body.length + value.length > 200000) { await this.endPage(); }
    this.body += value;
  }
  private async write(name: string, bytes: Uint8Array): Promise<void> {
    if (bytes.length > 40 * 1024 * 1024 || bytes.length > 1024 * 1024 * 1024 - this.bytes) {
      throw new HarmonyDocumentFailure('pdf_expanded', 'PDF 展开后超过 1 GiB 或单个资源过大');
    }
    const path = this.directory + '/' + name;
    if (fs.accessSync(path)) { throw new HarmonyDocumentFailure('pdf_output', 'PDF 转换目录已变化，请重新导入'); }
    const file = await fs.open(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
    try {
      for (let offset = 0; offset < bytes.length;) {
        const count = await fs.write(file.fd, bytes.slice(offset, Math.min(offset + 65536, bytes.length)).buffer as ArrayBuffer);
        if (count <= 0) { throw new Error('无法写入 PDF 转换结果，请检查剩余空间'); }
        offset += count;
      }
    } finally { await fs.close(file); }
    this.bytes += bytes.length;
  }
  private async writeText(name: string, text: string): Promise<void> {
    await this.write(name, new util.TextEncoder().encodeInto(text));
  }
  async endPage(): Promise<void> {
    if (!this.body) { return; }
    if (this.parts.length >= 10000) { throw new HarmonyDocumentFailure('pdf_parts', 'PDF 转换章节过多，请拆分后导入'); }
    const name = 'part' + String(this.parts.length).padStart(5, '0') + '.html';
    await this.writeText(name, '<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>' +
      pdfXml(this.label) + '</title></head><body>' + this.body + '</body></html>');
    this.parts.push({ name: name, label: this.label }); this.body = '';
  }
  async picture(pixels: image.PixelMap, width: number, height: number): Promise<void> {
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || this.pictures.length >= 19998) {
      throw new HarmonyDocumentFailure('pdf_images', 'PDF 图片范围无效或数量过多');
    }
    const info = await pixels.getImageInfo();
    if (info.size.width <= 0 || info.size.height <= 0 || info.size.width > 24000000 / info.size.height) {
      throw new HarmonyDocumentFailure('pdf_images', 'PDF 单张图片超过 2400 万像素或尺寸无效');
    }
    const scale = Math.min(1, 1800 / Math.max(info.size.width, info.size.height));
    if (scale < 1) { await pixels.scale(scale, scale); }
    const packer = image.createImagePacker();
    let bytes: ArrayBuffer;
    try { bytes = await packer.packing(pixels, { format: 'image/jpeg', quality: 88 }); }
    finally { await packer.release(); }
    if (bytes.byteLength > 8 * 1024 * 1024) { throw new HarmonyDocumentFailure('pdf_images', 'PDF 图片编码后超过 8 MiB'); }
    const name = 'resource' + String(this.pictures.length + 1).padStart(5, '0') + '.jpg';
    await this.write(name, new Uint8Array(bytes)); this.pictures.push(name);
    await this.append('<img src="' + name + '" style="width:' + width + 'px;height:' + height + 'px"/>');
  }
  async finish(): Promise<void> {
    await this.endPage();
    if (!this.parts.length) { throw new HarmonyDocumentFailure('pdf_empty', 'PDF 中没有可阅读的页面'); }
    const manifest = this.parts.map((part: PdfPart, index: number): string => '<item id="c' + index + '" href="' + part.name + '" media-type="application/xhtml+xml"/>').join('') +
      this.pictures.map((name: string, index: number): string => '<item id="i' + index + '" href="' + name + '" media-type="image/jpeg"/>').join('');
    const spine = this.parts.map((_part: PdfPart, index: number): string => '<itemref idref="c' + index + '"/>').join('');
    const nav = this.parts.map((part: PdfPart, index: number): string => '<navPoint id="p' + index + '" playOrder="' + (index + 1) + '"><navLabel><text>' + pdfXml(part.label) +
      '</text></navLabel><content src="' + part.name + '"/></navPoint>').join('');
    await this.writeText('resource00000.ncx', '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="urn:local:pdf"/></head><docTitle><text>' +
      pdfXml(this.title) + '</text></docTitle><navMap>' + nav + '</navMap></ncx>');
    await this.writeText('content.opf', '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:local:pdf</dc:identifier><dc:title>' +
      pdfXml(this.title) + '</dc:title><dc:creator>' + pdfXml(this.author) + '</dc:creator><dc:language>und</dc:language></metadata><manifest><item id="nav" href="resource00000.ncx" media-type="application/x-dtbncx+xml"/>' + manifest + '</manifest><spine toc="nav">' + spine + '</spine></package>');
  }
}
