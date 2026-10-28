package org.mewx.wenku8_flutter

import org.apache.poi.EncryptedDocumentException
import org.apache.poi.hwpf.HWPFDocument

/** Word 97–2003 documents are converted locally through Apache POI HWPF.
 * Read the main story in source order; field instructions are not prose. */
internal object BookDocImport {
    fun read(source: BookDocumentInput, writer: BookEpubWriter) {
        try {
            source.inputStream().use { input -> HWPFDocument(input).use { document ->
                document.summaryInformation?.let { info ->
                    info.title?.trim()?.takeIf { it.isNotEmpty() }?.let { writer.title = it.take(2048) }
                    writer.author = info.author?.trim()?.take(2048).orEmpty()
                }
                val range = document.range
                require(range.numParagraphs() <= 200000) { "DOC 段落过多，请拆分后导入" }
                val fields = ArrayDeque<Boolean>()
                fun image(bytes: ByteArray, type: String) {
                    if (type !in setOf("png", "jpg", "jpeg", "gif", "webp")) return
                    require(bytes.size <= 8 * 1024 * 1024) { "DOC 单张图片超过 8 MiB" }
                    val key = writer.inlineResourceKey()
                    writer.resource(key, type, bytes.inputStream()); writer.image(key)
                }
                for (index in 0 until range.numParagraphs()) {
                    val paragraph = range.getParagraph(index)
                    val text = StringBuilder()
                    val style = document.styleSheet.getStyleDescription(paragraph.styleIndex.toInt())?.name.orEmpty()
                    val heading = style.matches(Regex("(?i)(heading|标题|標題|見出し)\\s*[1-6]?"))
                    fun flush() {
                        if (text.isNotBlank()) {
                            if (heading) writer.heading(text.toString()) else writer.text(text.toString())
                        }
                        text.setLength(0)
                    }
                    for (runIndex in 0 until paragraph.numCharacterRuns()) {
                        val run = paragraph.getCharacterRun(runIndex)
                        if (document.picturesTable.hasPicture(run)) {
                            flush()
                            val picture = document.picturesTable.extractPicture(run, false)
                            val type = picture.suggestFileExtension().lowercase()
                            image(picture.content, type)
                            continue
                        }
                        for ((offset, char) in run.text().withIndex()) when (char) {
                            '\u0008' -> {
                                flush()
                                document.officeDrawingsMain.getOfficeDrawingAt(run.startOffset + offset)?.pictureData?.let { bytes ->
                                    val type = when {
                                        bytes.size >= 8 && bytes[0] == 0x89.toByte() && bytes[1] == 0x50.toByte() -> "png"
                                        bytes.size >= 3 && bytes[0] == 0xff.toByte() && bytes[1] == 0xd8.toByte() -> "jpg"
                                        bytes.size >= 6 && bytes.copyOfRange(0, 3).toString(Charsets.US_ASCII) == "GIF" -> "gif"
                                        bytes.size >= 12 && bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII) == "WEBP" -> "webp"
                                        else -> ""
                                    }
                                    image(bytes, type)
                                }
                            }
                            '\u0013' -> fields.addLast(false)
                            '\u0014' -> if (fields.isNotEmpty()) { fields.removeLast(); fields.addLast(true) }
                            '\u0015' -> if (fields.isNotEmpty()) fields.removeLast()
                            else -> if (fields.all { it }) {
                                when {
                                    char == '\r' || char == '\u000b' -> text.append('\n')
                                    char == '\u0007' || char == '\t' -> text.append('\t')
                                    char.code >= 32 && char != '\uFFFC' -> text.append(char)
                                }
                            }
                        }
                    }
                    flush()
                }
            } }
        } catch (_: EncryptedDocumentException) {
            error("DOC 已加密，请先在 Word 中解除密码后导入")
        } catch (failure: org.apache.poi.OldFileFormatException) {
            throw IllegalArgumentException("此 DOC 版本过旧，请另存为 Word 97–2003 DOC 或 DOCX 后导入", failure)
        } catch (failure: LinkageError) {
            throw IllegalArgumentException("DOC 读取组件不支持此文件，请另存为 DOCX 或 EPUB 后导入", failure)
        }
    }
}
