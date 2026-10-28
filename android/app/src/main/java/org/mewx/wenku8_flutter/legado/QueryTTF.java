/* Adapted from LegadoTeam/legado, GPL-3.0-only.
 * Upstream 3046111c1718e7b67c2ad468e54edf295ec05820, QueryTTF.java.
 * Preserve upstream glyph signatures; add bounded parsing and cancellation.
 */
package org.mewx.wenku8_flutter.legado;

import androidx.annotation.Keep;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.LinkedList;

@Keep
@SuppressWarnings({"FieldCanBeLocal", "unused"})
public class QueryTTF {
    private Runnable budget = () -> {};
    private long mappingSteps;
    private long pointCount;
    private long signatureChars;
    private final HashMap<Integer, String> signatures = new HashMap<>();

    private void check() { budget.run(); }
    private void mappingStep() {
        if (++mappingSteps > 2_000_000) throw new IllegalArgumentException("书源字体字符映射过大");
        if ((mappingSteps & 1023) == 0) check();
    }

    private static class Header {
        public long sfntVersion;
        public int numTables;
        public int searchRange;
        public int entrySelector;
        public int rangeShift;
    }

    private static class Directory {
        public String tableTag;
        public int checkSum;
        public int offset;
        public int length;
    }

    private static class NameLayout {
        public int format;
        public int count;
        public int stringOffset;
        public LinkedList<NameRecord> records = new LinkedList<>();
    }

    private static class NameRecord {
        public int platformID;           // 平台标识符<0:Unicode, 1:Mac, 2:ISO, 3:Windows, 4:Custom>
        public int encodingID;           // 编码标识符
        public int languageID;           // 语言标识符
        public int nameID;               // 名称标识符
        public int length;               // 名称字符串的长度
        public int offset;               // 名称字符串相对于stringOffset的字节偏移量
    }

    private static class HeadLayout {
        public int majorVersion;
        public int minorVersion;
        public int fontRevision;
        public int checkSumAdjustment;
        public int magicNumber;
        public int flags;
        public int unitsPerEm;
        public long created;
        public long modified;
        public short xMin;
        public short yMin;
        public short xMax;
        public short yMax;
        public int macStyle;
        public int lowestRecPPEM;
        public short fontDirectionHint;
        public short indexToLocFormat;
        public short glyphDataFormat;
    }

    private static class MaxpLayout {
        public int version;
        public int numGlyphs;
        public int maxPoints;
        public int maxContours;
        public int maxCompositePoints;
        public int maxCompositeContours;
        public int maxZones;
        public int maxTwilightPoints;
        public int maxStorage;
        public int maxFunctionDefs;
        public int maxInstructionDefs;
        public int maxStackElements;
        public int maxSizeOfInstructions;
        public int maxComponentElements;
        public int maxComponentDepth;
    }

    private static class CmapLayout {
        public int version;
        public int numTables;
        public LinkedList<CmapRecord> records = new LinkedList<>();
        public HashMap<Integer, CmapFormat> tables = new HashMap<>();
    }

    private static class CmapRecord {
        public int platformID;
        public int encodingID;
        public int offset;
    }

    private static class CmapFormat {
        public int format;
        public int length;
        public int language;
        public int[] subHeaderKeys;
        public int[] subHeaders;
        public int segCountX2;
        public int searchRange;
        public int entrySelector;
        public int rangeShift;
        public int[] endCode;
        public int reservedPad;
        public int[] startCode;
        public int[] idDelta;
        public int[] idRangeOffsets;
        public int firstCode;
        public int entryCount;
        public int[] glyphIdArray;
    }

    private static class GlyfLayout {
        public short numberOfContours;
        public short xMin;
        public short yMin;
        public short xMax;
        public short yMax;
        public GlyphTableBySimple glyphSimple;
        public LinkedList<GlyphTableComponent> glyphComponent;
    }

    private static class GlyphTableBySimple {
        int[] endPtsOfContours;
        int instructionLength;
        int[] instructions;
        int[] flags;
        int[] xCoordinates;
        int[] yCoordinates;
    }

    private static class GlyphTableComponent {
        int flags;
        int glyphIndex;
        int argument1;
        int argument2;
        float xScale;
        float scale01;
        float scale10;
        float yScale;
    }

    private class BufferReader {
        private final ByteBuffer byteBuffer;

        public BufferReader(byte[] buffer, int index) {
            check();
            this.byteBuffer = ByteBuffer.wrap(buffer);
            this.byteBuffer.order(ByteOrder.BIG_ENDIAN); // 设置为大端模式
            this.byteBuffer.position(index); // 设置起始索引
        }

        public void position(int index) {
            check();
            byteBuffer.position(index); // 设置起始索引
        }

        public int position() {
            return byteBuffer.position();
        }

        public long ReadUInt64() {
            need(8);
            return byteBuffer.getLong();
        }

        public int ReadUInt32() {
            need(4);
            return byteBuffer.getInt();
        }

        public int ReadInt32() {
            need(4);
            return byteBuffer.getInt();
        }

        public int ReadUInt16() {
            need(2);
            return byteBuffer.getShort() & 0xFFFF;
        }

        public short ReadInt16() {
            need(2);
            return byteBuffer.getShort();
        }

        public short ReadUInt8() {
            need(1);
            return (short) (byteBuffer.get() & 0xFF);
        }

        public byte ReadInt8() {
            need(1);
            return byteBuffer.get();
        }

        public byte[] ReadByteArray(int len) {
            need(len);
            byte[] result = new byte[len];
            byteBuffer.get(result);
            return result;
        }

        public int[] ReadUInt8Array(int len) {
            need(len);
            var result = new int[len];
            for (int i = 0; i < len; ++i) result[i] = byteBuffer.get() & 0xFF;
            return result;
        }

        public int[] ReadInt16Array(int len) {
            need((long) len * 2);
            var result = new int[len];
            for (int i = 0; i < len; ++i) result[i] = byteBuffer.getShort();
            return result;
        }

        public int[] ReadUInt16Array(int len) {
            need((long) len * 2);
            var result = new int[len];
            for (int i = 0; i < len; ++i) result[i] = byteBuffer.getShort() & 0xFFFF;
            return result;
        }

        public int[] ReadInt32Array(int len) {
            need((long) len * 4);
            var result = new int[len];
            for (int i = 0; i < len; ++i) result[i] = byteBuffer.getInt();
            return result;
        }
        private void need(long bytes) {
            check();
            if (bytes < 0 || bytes > byteBuffer.remaining()) throw new IllegalArgumentException("书源字体数据不完整");
        }
    }

    private final Header fileHeader = new Header();
    private final HashMap<String, Directory> directorys = new HashMap<>();
    private final NameLayout name = new NameLayout();
    private final HeadLayout head = new HeadLayout();
    private final MaxpLayout maxp = new MaxpLayout();
    private final CmapLayout Cmap = new CmapLayout();
    private final int[][] pps = new int[][]{{3, 10}, {0, 4}, {3, 1}, {1, 0}, {0, 3}, {0, 1}};

    private void readNameTable(byte[] buffer) {
        var dataTable = directorys.get("name");
        assert dataTable != null;
        var reader = new BufferReader(buffer, dataTable.offset);
        name.format = reader.ReadUInt16();
        name.count = reader.ReadUInt16();
        name.stringOffset = reader.ReadUInt16();
        for (int i = 0; i < name.count; ++i) {
            NameRecord record = new NameRecord();
            record.platformID = reader.ReadUInt16();
            record.encodingID = reader.ReadUInt16();
            record.languageID = reader.ReadUInt16();
            record.nameID = reader.ReadUInt16();
            record.length = reader.ReadUInt16();
            record.offset = reader.ReadUInt16();
            name.records.add(record);
        }
    }

    private void readHeadTable(byte[] buffer) {
        var dataTable = directorys.get("head");
        assert dataTable != null;
        var reader = new BufferReader(buffer, dataTable.offset);
        head.majorVersion = reader.ReadUInt16();
        head.minorVersion = reader.ReadUInt16();
        head.fontRevision = reader.ReadUInt32();
        head.checkSumAdjustment = reader.ReadUInt32();
        head.magicNumber = reader.ReadUInt32();
        head.flags = reader.ReadUInt16();
        head.unitsPerEm = reader.ReadUInt16();
        head.created = reader.ReadUInt64();
        head.modified = reader.ReadUInt64();
        head.xMin = reader.ReadInt16();
        head.yMin = reader.ReadInt16();
        head.xMax = reader.ReadInt16();
        head.yMax = reader.ReadInt16();
        head.macStyle = reader.ReadUInt16();
        head.lowestRecPPEM = reader.ReadUInt16();
        head.fontDirectionHint = reader.ReadInt16();
        head.indexToLocFormat = reader.ReadInt16();
        head.glyphDataFormat = reader.ReadInt16();
    }

    private int[] loca;

    private void readLocaTable(byte[] buffer) {
        var dataTable = directorys.get("loca");
        assert dataTable != null;
        var reader = new BufferReader(buffer, dataTable.offset);
        if (head.indexToLocFormat == 0) {
            loca = reader.ReadUInt16Array(dataTable.length / 2);
            for (var i = 0; i < loca.length; i++) loca[i] *= 2;
        } else {
            loca = reader.ReadInt32Array(dataTable.length / 4);
        }
    }

    private void readCmapTable(byte[] buffer) {
        var dataTable = directorys.get("cmap");
        assert dataTable != null;
        var reader = new BufferReader(buffer, dataTable.offset);
        Cmap.version = reader.ReadUInt16();
        Cmap.numTables = reader.ReadUInt16();
        for (int i = 0; i < Cmap.numTables; ++i) {
            CmapRecord record = new CmapRecord();
            record.platformID = reader.ReadUInt16();
            record.encodingID = reader.ReadUInt16();
            record.offset = reader.ReadUInt32();
            Cmap.records.add(record);
        }

        for (var formatTable : Cmap.records) {
            int fmtOffset = formatTable.offset;
            if (Cmap.tables.containsKey(fmtOffset)) continue;
            reader.position(dataTable.offset + fmtOffset);

            CmapFormat f = new CmapFormat();
            f.format = reader.ReadUInt16();
            f.length = reader.ReadUInt16();
            f.language = reader.ReadUInt16();
            switch (f.format) {
                case 0: {
                    f.glyphIdArray = reader.ReadUInt8Array(f.length - 6);
                    int unicodeInclusive = 0;
                    int unicodeExclusive = f.glyphIdArray.length;
                    for (; unicodeInclusive < unicodeExclusive; unicodeInclusive++) {
                        if (f.glyphIdArray[unicodeInclusive] == 0) continue; // 排除轮廓索引为0的Unicode
                        unicodeToGlyphId.put(unicodeInclusive, f.glyphIdArray[unicodeInclusive]);
                    }
                    break;
                }
                case 4: {
                    f.segCountX2 = reader.ReadUInt16();
                    int segCount = f.segCountX2 / 2;
                    f.searchRange = reader.ReadUInt16();
                    f.entrySelector = reader.ReadUInt16();
                    f.rangeShift = reader.ReadUInt16();
                    f.endCode = reader.ReadUInt16Array(segCount);
                    f.reservedPad = reader.ReadUInt16();
                    f.startCode = reader.ReadUInt16Array(segCount);
                    f.idDelta = reader.ReadInt16Array(segCount);
                    f.idRangeOffsets = reader.ReadUInt16Array(segCount);
                    int glyphIdArrayLength = (f.length - 16 - (segCount * 8)) / 2;
                    f.glyphIdArray = reader.ReadUInt16Array(glyphIdArrayLength);
                    for (int segmentIndex = 0; segmentIndex < segCount; segmentIndex++) {
                        int unicodeInclusive = f.startCode[segmentIndex];
                        int unicodeExclusive = f.endCode[segmentIndex];
                        int idDelta = f.idDelta[segmentIndex];
                        int idRangeOffset = f.idRangeOffsets[segmentIndex];
                        for (int unicode = unicodeInclusive; unicode <= unicodeExclusive; unicode++) {
                            mappingStep();
                            int glyphId = 0;
                            if (idRangeOffset == 0) {
                                glyphId = (unicode + idDelta) & 0xFFFF;
                            } else {
                                int gIndex = (idRangeOffset / 2) + unicode - unicodeInclusive + segmentIndex - segCount;
                                if (gIndex >= 0 && gIndex < glyphIdArrayLength) glyphId = f.glyphIdArray[gIndex] + idDelta;
                            }
                            if (glyphId == 0) continue; // 排除轮廓索引为0的Unicode
                            unicodeToGlyphId.put(unicode, glyphId);
                        }
                    }
                    break;
                }
                case 6: {
                    f.firstCode = reader.ReadUInt16();
                    f.entryCount = reader.ReadUInt16();
                    f.glyphIdArray = reader.ReadUInt16Array(f.entryCount);
                    int unicodeIndex = f.firstCode;
                    int unicodeCount = f.entryCount;
                    for (int gIndex = 0; gIndex < unicodeCount; gIndex++) {
                        unicodeToGlyphId.put(unicodeIndex, f.glyphIdArray[gIndex]);
                        unicodeIndex++;
                    }
                    break;
                }
                default:
                    break;
            }
            Cmap.tables.put(fmtOffset, f);
        }
    }

    private void readMaxpTable(byte[] buffer) {
        var dataTable = directorys.get("maxp");
        assert dataTable != null;
        var reader = new BufferReader(buffer, dataTable.offset);
        maxp.version = reader.ReadUInt32();
        maxp.numGlyphs = reader.ReadUInt16();
        maxp.maxPoints = reader.ReadUInt16();
        maxp.maxContours = reader.ReadUInt16();
        maxp.maxCompositePoints = reader.ReadUInt16();
        maxp.maxCompositeContours = reader.ReadUInt16();
        maxp.maxZones = reader.ReadUInt16();
        maxp.maxTwilightPoints = reader.ReadUInt16();
        maxp.maxStorage = reader.ReadUInt16();
        maxp.maxFunctionDefs = reader.ReadUInt16();
        maxp.maxInstructionDefs = reader.ReadUInt16();
        maxp.maxStackElements = reader.ReadUInt16();
        maxp.maxSizeOfInstructions = reader.ReadUInt16();
        maxp.maxComponentElements = reader.ReadUInt16();
        maxp.maxComponentDepth = reader.ReadUInt16();
    }

    private GlyfLayout[] glyfArray;

    private void readGlyfTable(byte[] buffer) {
        var dataTable = directorys.get("glyf");
        assert dataTable != null;
        int glyfCount = maxp.numGlyphs;
        if (loca.length < glyfCount + 1) throw new IllegalArgumentException("书源字体缺少字形位置");
        glyfArray = new GlyfLayout[glyfCount];  // 创建字形容器

        var reader = new BufferReader(buffer, 0);
        for (int index = 0; index < glyfCount; index++) {
            check();
            if (loca[index] < 0 || loca[index + 1] < loca[index] || loca[index + 1] > dataTable.length)
                throw new IllegalArgumentException("书源字体字形位置无效");
            if (loca[index] == loca[index + 1]) continue;   // 当前loca与下一个loca相同，表示这个字形不存在
            int offset = dataTable.offset + loca[index];
            var glyph = new GlyfLayout();
            reader.position(offset);
            glyph.numberOfContours = reader.ReadInt16();
            if (glyph.numberOfContours > maxp.maxContours) continue; // 如果字形轮廓数大于非复合字形中包含的最大轮廓数，则说明该字形无效。
            glyph.xMin = reader.ReadInt16();
            glyph.yMin = reader.ReadInt16();
            glyph.xMax = reader.ReadInt16();
            glyph.yMax = reader.ReadInt16();
            if (glyph.numberOfContours == 0) continue;
            if (glyph.numberOfContours > 0) {
                glyph.glyphSimple = new GlyphTableBySimple();
                glyph.glyphSimple.endPtsOfContours = reader.ReadUInt16Array(glyph.numberOfContours);
                glyph.glyphSimple.instructionLength = reader.ReadUInt16();
                glyph.glyphSimple.instructions = reader.ReadUInt8Array(glyph.glyphSimple.instructionLength);
                int flagLength = glyph.glyphSimple.endPtsOfContours[glyph.glyphSimple.endPtsOfContours.length - 1] + 1;
                pointCount += flagLength;
                if (pointCount > 2_000_000) throw new IllegalArgumentException("书源字体轮廓过大");
                glyph.glyphSimple.flags = new int[flagLength];
                for (int n = 0; n < flagLength; ++n) {
                    var glyphSimpleFlag = reader.ReadUInt8();
                    glyph.glyphSimple.flags[n] = glyphSimpleFlag;
                    if ((glyphSimpleFlag & 0x08) == 0x08) {
                        for (int m = reader.ReadUInt8(); m > 0; --m) {
                            if (n + 1 >= flagLength) throw new IllegalArgumentException("书源字体轮廓标志无效");
                            glyph.glyphSimple.flags[++n] = glyphSimpleFlag;
                        }
                    }
                }
                glyph.glyphSimple.xCoordinates = new int[flagLength];
                for (int n = 0; n < flagLength; ++n) {
                    switch (glyph.glyphSimple.flags[n] & 0x12) {
                        case 0x02:
                            glyph.glyphSimple.xCoordinates[n] = -1 * reader.ReadUInt8();
                            break;
                        case 0x12:
                            glyph.glyphSimple.xCoordinates[n] = reader.ReadUInt8();
                            break;
                        case 0x10:
                            glyph.glyphSimple.xCoordinates[n] = 0;  // 点位数据重复上一次数据，那么相对数据变化量就是0
                            break;
                        case 0x00:
                            glyph.glyphSimple.xCoordinates[n] = reader.ReadInt16();
                            break;
                    }
                }
                glyph.glyphSimple.yCoordinates = new int[flagLength];
                for (int n = 0; n < flagLength; ++n) {
                    switch (glyph.glyphSimple.flags[n] & 0x24) {
                        case 0x04:
                            glyph.glyphSimple.yCoordinates[n] = -1 * reader.ReadUInt8();
                            break;
                        case 0x24:
                            glyph.glyphSimple.yCoordinates[n] = reader.ReadUInt8();
                            break;
                        case 0x20:
                            glyph.glyphSimple.yCoordinates[n] = 0;  // 点位数据重复上一次数据，那么相对数据变化量就是0
                            break;
                        case 0x00:
                            glyph.glyphSimple.yCoordinates[n] = reader.ReadInt16();
                            break;
                    }
                }
            } else {
                glyph.glyphComponent = new LinkedList<>();
                while (true) {
                    var glyphTableComponent = new GlyphTableComponent();
                    glyphTableComponent.flags = reader.ReadUInt16();
                    glyphTableComponent.glyphIndex = reader.ReadUInt16();
                    switch (glyphTableComponent.flags & 0b11) {
                        case 0b00:
                            glyphTableComponent.argument1 = reader.ReadUInt8();
                            glyphTableComponent.argument2 = reader.ReadUInt8();
                            break;
                        case 0b10:
                            glyphTableComponent.argument1 = reader.ReadInt8();
                            glyphTableComponent.argument2 = reader.ReadInt8();
                            break;
                        case 0b01:
                            glyphTableComponent.argument1 = reader.ReadUInt16();
                            glyphTableComponent.argument2 = reader.ReadUInt16();
                            break;
                        case 0b11:
                            glyphTableComponent.argument1 = reader.ReadInt16();
                            glyphTableComponent.argument2 = reader.ReadInt16();
                            break;
                    }
                    switch (glyphTableComponent.flags & 0b11001000) {
                        case 0b00001000:
                            glyphTableComponent.yScale = glyphTableComponent.xScale = ((float) reader.ReadUInt16()) / 16384.0f;
                            break;
                        case 0b01000000:
                            glyphTableComponent.xScale = ((float) reader.ReadUInt16()) / 16384.0f;
                            glyphTableComponent.yScale = ((float) reader.ReadUInt16()) / 16384.0f;
                            break;
                        case 0b10000000:
                            glyphTableComponent.xScale = ((float) reader.ReadUInt16()) / 16384.0f;
                            glyphTableComponent.scale01 = ((float) reader.ReadUInt16()) / 16384.0f;
                            glyphTableComponent.scale10 = ((float) reader.ReadUInt16()) / 16384.0f;
                            glyphTableComponent.yScale = ((float) reader.ReadUInt16()) / 16384.0f;
                            break;
                    }
                    glyph.glyphComponent.add(glyphTableComponent);
                    if ((glyphTableComponent.flags & 0x20) == 0) break;
                }
            }
            glyfArray[index] = glyph;
        }
    }

    public String getGlyfById(int glyfId) {
        check();
        if (glyfId < 0 || glyfId >= glyfArray.length) return null;
        if (signatures.containsKey(glyfId)) return signatures.get(glyfId);
        var glyph = glyfArray[glyfId];
        if (glyph == null) return null;    // 过滤不存在的字体轮廓
        String glyphString;
        if (glyph.numberOfContours >= 0) {
            int dataCount = glyph.glyphSimple.flags.length;
            String[] coordinateArray = new String[dataCount];
            for (int i = 0; i < dataCount; i++) {
                coordinateArray[i] = glyph.glyphSimple.xCoordinates[i] + "," + glyph.glyphSimple.yCoordinates[i];
            }
            glyphString = String.join("|", coordinateArray);
        } else {
            LinkedList<String> glyphIdList = new LinkedList<>();
            for (var g : glyph.glyphComponent) {
                glyphIdList.add("{" +
                        "flags:" + g.flags + "," +
                        "glyphIndex:" + g.glyphIndex + "," +
                        "arg1:" + g.argument1 + "," +
                        "arg2:" + g.argument2 + "," +
                        "xScale:" + g.xScale + "," +
                        "scale01:" + g.scale01 + "," +
                        "scale10:" + g.scale10 + "," +
                        "yScale:" + g.yScale + "}");
            }
            glyphString = "[" + String.join(",", glyphIdList) + "]";
        }
        signatureChars += glyphString.length();
        if (signatureChars > 16 * 1024 * 1024) throw new IllegalArgumentException("书源字体轮廓文本过大");
        signatures.put(glyfId, glyphString);
        return glyphString;
    }

    public QueryTTF(final byte[] buffer) {
        this(buffer, () -> {});
    }

    public QueryTTF(final byte[] buffer, Runnable budget) {
        this.budget = budget;
        try { parse(buffer); }
        finally { this.budget = () -> {}; } // Cached fonts must not retain a completed run.
    }

    private void parse(final byte[] buffer) {
        check();
        if (buffer.length < 12 || buffer.length > 8 * 1024 * 1024)
            throw new IllegalArgumentException("书源字体需要在 8 MiB 以内且为有效 TTF");
        var fontReader = new BufferReader(buffer, 0);
        fileHeader.sfntVersion = fontReader.ReadUInt32();
        fileHeader.numTables = fontReader.ReadUInt16();
        fileHeader.searchRange = fontReader.ReadUInt16();
        fileHeader.entrySelector = fontReader.ReadUInt16();
        fileHeader.rangeShift = fontReader.ReadUInt16();
        for (int i = 0; i < fileHeader.numTables; ++i) {
            Directory d = new Directory();
            d.tableTag = new String(fontReader.ReadByteArray(4), StandardCharsets.US_ASCII);
            d.checkSum = fontReader.ReadUInt32();
            d.offset = fontReader.ReadUInt32();
            d.length = fontReader.ReadUInt32();
            if (d.offset < 0 || d.length < 0 || (long) d.offset + d.length > buffer.length)
                throw new IllegalArgumentException("书源字体数据表越界");
            directorys.put(d.tableTag, d);
        }

        for (String table : new String[]{"name", "head", "cmap", "loca", "maxp", "glyf"})
            if (!directorys.containsKey(table)) throw new IllegalArgumentException("书源字体不是支持的 TrueType 轮廓字体");
        readNameTable(buffer);
        readHeadTable(buffer);
        readCmapTable(buffer);
        readLocaTable(buffer);
        readMaxpTable(buffer);
        readGlyfTable(buffer);
        int glyfArrayLength = glyfArray.length;
        for (var item : unicodeToGlyphId.entrySet()) {
            check();
            int key = item.getKey();
            int val = item.getValue();
            if (val < 0 || val >= glyfArrayLength) continue;
            String glyfString = getGlyfById(val);
            unicodeToGlyph.put(key, glyfString);
            if (glyfString == null) continue;   // null 不能用作hashmap的key
            glyphToUnicode.put(glyfString, key);
        }
    }

    public final HashMap<Integer, String> unicodeToGlyph = new HashMap<>();
    public final HashMap<String, Integer> glyphToUnicode = new HashMap<>();
    public final HashMap<Integer, Integer> unicodeToGlyphId = new HashMap<>();

    public long estimatedBytes() {
        return pointCount * 16 + signatureChars * 2 + unicodeToGlyphId.size() * 128L + glyfArray.length * 128L;
    }

    public int getGlyfIdByUnicode(int unicode) {
        var result = unicodeToGlyphId.get(unicode);
        if (result == null) return 0; // 如果找不到Unicode对应的轮廓索引，就返回默认值0
        return result;
    }

    public String getGlyfByUnicode(int unicode) {
        return unicodeToGlyph.get(unicode);
    }

    public int getUnicodeByGlyf(String glyph) {
        var result = glyphToUnicode.get(glyph);
        if (result == null) return 0; // 如果轮廓数据找不到对应的Unicode，就返回默认值0
        return result;
    }

    public boolean isBlankUnicode(int unicode) {
        return switch (unicode) {
            case 0x0009,    // 水平制表符 (Horizontal Tab)
                    0x0020,    // 空格 (Space)
                    0x00A0,    // 不中断空格 (No-Break Space)
                    0x2002,    // En空格 (En Space)
                    0x2003,    // Em空格 (Em Space)
                    0x2007,    // 刚性空格 (Figure Space)
                    0x200A,    // 发音修饰字母的连字符 (Hair Space)
                    0x200B,    // 零宽空格 (Zero Width Space)
                    0x200C,    // 零宽不连字 (Zero Width Non-Joiner)
                    0x200D,    // 零宽连字 (Zero Width Joiner)
                    0x202F,    // 狭窄不中断空格 (Narrow No-Break Space)
                    0x205F     // 中等数学空格 (Medium Mathematical Space)
                    -> true;
            default -> false;
        };
    }
}
