package org.mewx.wenku8_flutter

import android.view.HapticFeedbackConstants
import org.junit.Assert.*
import org.junit.Test

class AppHapticPolicyTest {
    @Test fun strengthScalesTransientsWithoutExtendingOrRepeatingTheCue() {
        for (cue in listOf("shelfStep", "detent", "selection", "pageTurn", "action", "longPress", "boundary", "success", "warning", "error")) {
            val light = AppHapticPolicy.pulses(cue, "light")
            val strong = AppHapticPolicy.pulses(cue, "strong")
            assertEquals(light.size, strong.size)
            assertEquals(light.map { it.delayMs }, strong.map { it.delayMs })
            for ((a, b) in light.zip(strong)) {
                assertTrue(a.scale > 0 && a.scale < b.scale && b.scale <= 1)
            }
        }
        assertEquals(1, AppHapticPolicy.pulses("shelfStep", "strong").size)
        assertEquals("standard", AppHapticPolicy.strength(null))
        assertEquals("light", AppHapticPolicy.strength("light"))
        assertNull(AppHapticPolicy.strength("unknown"))
    }

    @Test fun modernDevicesUseSemanticTicksAndDistinctOutcomes() {
        for (cue in listOf("detent", "shelfStep", "selection", "pageTurn", "action")) {
            assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback(cue, 37))
        }
        assertEquals(HapticFeedbackConstants.CONFIRM, AppHapticPolicy.feedback("success", 37))
        assertEquals(HapticFeedbackConstants.CONFIRM, AppHapticPolicy.feedback("warning", 37))
        assertEquals(HapticFeedbackConstants.REJECT, AppHapticPolicy.feedback("error", 37))
        assertEquals(HapticFeedbackConstants.LONG_PRESS, AppHapticPolicy.feedback("longPress", 37))
        assertEquals(HapticFeedbackConstants.CONTEXT_CLICK, AppHapticPolicy.feedback("boundary", 37))
    }
    @Test fun olderAndroidUsesAvailablePresetsNotArbitraryWaveforms() {
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback("selection", 24))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback("detent", 33))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback("shelfStep", 33))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback("pageTurn", 24))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AppHapticPolicy.feedback("pageTurn", 29))
        assertEquals(HapticFeedbackConstants.VIRTUAL_KEY, AppHapticPolicy.feedback("success", 29))
        assertEquals(HapticFeedbackConstants.VIRTUAL_KEY, AppHapticPolicy.feedback("warning", 29))
        assertEquals(HapticFeedbackConstants.VIRTUAL_KEY, AppHapticPolicy.feedback("error", 29))
        assertEquals(HapticFeedbackConstants.LONG_PRESS, AppHapticPolicy.feedback("longPress", 24))
        assertEquals(HapticFeedbackConstants.CONTEXT_CLICK, AppHapticPolicy.feedback("boundary", 24))
        assertNull(AppHapticPolicy.feedback("unknown", 37))
    }
}
