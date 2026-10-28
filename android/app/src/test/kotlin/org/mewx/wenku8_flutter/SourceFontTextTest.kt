package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceFontTextTest {
    @Test fun ttfAndWoff2RemoveOnlyEmptyZeroAdvanceCharacters() {
        val input = "A\uE001\uD83D\uDE00B \u0301\uDB80\uDC01"
        for (name in listOf("source.ttf", "source.woff2", "source-hmtx.woff2", "source-untransformed.woff2")) {
            val bytes = javaClass.getResourceAsStream("/source-fonts/$name")!!.use { it.readBytes() }
            assertEquals(name, "A😀B \u0301", SourceFontText.clean(input, bytes))
        }
    }
}
