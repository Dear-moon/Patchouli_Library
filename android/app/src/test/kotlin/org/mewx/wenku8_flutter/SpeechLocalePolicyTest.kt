package org.mewx.wenku8_flutter

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeechLocalePolicyTest {
    @Test fun isoLanguageIsChinese() {
        assertEquals("zh-CN", SpeechLocalePolicy.chineseTag(Locale("chi")))
        assertEquals("zh-CN", SpeechLocalePolicy.chineseTag(Locale("zho")))
    }

    @Test fun standardScriptAndRegionRemainIntact() {
        assertEquals("zh-Hant-HK", SpeechLocalePolicy.chineseTag(Locale.forLanguageTag("zh-Hant-HK")))
        assertEquals("zh-TW", SpeechLocalePolicy.chineseTag(Locale("chi", "TW")))
        assertEquals("zh-CN", SpeechLocalePolicy.chineseTag(Locale.SIMPLIFIED_CHINESE))
    }

    @Test fun vendorAliasesAndOtherLanguagesAreNotChinese() {
        assertNull(SpeechLocalePolicy.chineseTag(Locale("chn")))
        assertNull(SpeechLocalePolicy.chineseTag(Locale("usa")))
        assertNull(SpeechLocalePolicy.chineseTag(Locale.US))
        assertNull(SpeechLocalePolicy.chineseTag(Locale.JAPANESE))
        assertNull(SpeechLocalePolicy.chineseTag(Locale.ROOT))
    }

    @Test fun publicTtsPackageNamesAndDefaultAreAllowedButInvalidNamesAreRejected() {
        for (engine in listOf("", null, "../engine", "package;command", "https://engine", "invalid name"))
            assertFalse(SpeechLocalePolicy.supportsEngine(engine))
        for (engine in listOf("@default", "org.example.tts", "com.oplus.ttsaccessibilityengine", "com.oppo.tts", "com.heytap.speech"))
            assertTrue(SpeechLocalePolicy.supportsEngine(engine))
    }

    @Test fun matchingNeverSubstitutesAnotherLanguage() {
        assertTrue(SpeechLocalePolicy.matches(Locale.forLanguageTag("ja-JP"), Locale("jpn")))
        assertTrue(SpeechLocalePolicy.matches(Locale.forLanguageTag("zh-TW"), Locale("chi", "CN")))
        assertFalse(SpeechLocalePolicy.matches(Locale.JAPANESE, Locale.SIMPLIFIED_CHINESE))
        assertFalse(SpeechLocalePolicy.matches(Locale.US, Locale.JAPANESE))
    }

    @Test fun invalidRequestedLocalesAreNotSilentlyDefaulted() {
        assertEquals(Locale.JAPAN, SpeechLocalePolicy.requestedLocale("ja-JP"))
        assertNull(SpeechLocalePolicy.requestedLocale(""))
        assertNull(SpeechLocalePolicy.requestedLocale("und"))
        assertNull(SpeechLocalePolicy.requestedLocale("ja-JP\"/text"))
    }
}
