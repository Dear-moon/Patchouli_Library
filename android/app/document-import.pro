# PDFBox's JPX codec is an optional JCenter-only dependency. The importer
# rejects JPX images explicitly before decoding; other PDF filters stay live.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder

# POI HWPF reads binary Word text/raster bytes only. Java2D metafile geometry
# and GenericRecord JSON/debug rendering are desktop-only, not reader paths.
-dontwarn java.awt.**
# Log4j's optional OSGi discovery and compile-time annotations are not an
# Android logging backend; the API falls back to its built-in simple logger.
-dontwarn org.osgi.framework.**
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**
