package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceCheckInStepsTest {
    private fun rules(script: String = "function coins(){return {success:true,message:'Coins +5'}}") = mapOf<String, Any?>(
        "bookSourceUrl" to "https://account.example.invalid", "mainJs" to script,
        "ruleAccount" to mapOf("checkIn" to mapOf("url" to "https://account.example.invalid/points", "success" to "$.success"),
            "checkInLabel" to "Points", "checkInRevision" to "combined-v1",
            "checkInExtras" to listOf(mapOf("id" to "coins", "label" to "Coins", "js" to "coins"))))

    @Test fun partialFailureRetriesOnlyTheUnfinishedStep() {
        var points = 0
        var coins = 0
        val state = SourceState()
        val source = rules("function coins(){var value=JSON.parse(java.ajax('https://account.example.invalid/coins'));return {success:value.success}}")
        val run = SourceRun(state=state, fetch={ url, _, _, _ ->
            val success = if (url.endsWith("/points")) { points++; true } else { ++coins > 1 }
            SourceReply(url, "{\"success\":$success}")
        })
        val engine = BookSourceEngine(source, run)
        assertEquals(false, (engine.execute("accountCheckIn") as Map<*, *>)["complete"])
        assertEquals(false, SourceAccountState.view(source, state, false)["checkedInToday"])
        val restored = SourceState().apply { restore(state.snapshot()) }
        assertEquals(2, SourceAccountState.checkInReport(restored, "combined-v1").size)
        assertEquals(true, (engine.execute("accountCheckIn") as Map<*, *>)["complete"])
        assertEquals(true, SourceAccountState.view(source, state, false)["checkedInToday"])
        engine.execute("accountCheckIn")
        assertEquals(1, points); assertEquals(2, coins)
    }

    @Test fun legacyPrimaryCompletionDoesNotSkipTheNewCoinsStep() {
        val state = SourceState()
        SourceAccountState.checkedIn(state)
        val source = rules()
        assertEquals(false, SourceAccountState.view(source, state, false)["checkedInToday"])
        val result = BookSourceEngine(source, SourceRun(state=state, fetch={ _, _, _, _ -> error("Primary must stay completed") }))
            .execute("accountCheckIn") as Map<*, *>
        assertEquals(true, result["complete"])
        val steps = result["steps"] as List<*>
        assertEquals(true, (steps.first() as Map<*, *>)["already"])
        assertEquals(false, (steps.last() as Map<*, *>)["already"])
        SourceAccountState.submitted(state)
        assertFalse(SourceAccountState.completedToday(state, "combined-v1"))
        assertTrue(SourceAccountState.checkInReport(state, "combined-v1").isEmpty())
    }

    @Test fun expiredAuthenticationPropagatesWithoutClaimingCompletion() {
        val state = SourceState()
        val source = rules("function coins(){throw new Error('SOURCE_AUTH_EXPIRED:expired')}")
        val failure = assertThrows(Exception::class.java) {
            BookSourceEngine(source, SourceRun(state=state, fetch={ url, _, _, _ -> SourceReply(url, "{\"success\":true}") }))
                .execute("accountCheckIn")
        }
        assertTrue(SourceAccountState.authenticationRejected(failure))
        assertFalse(SourceAccountState.completedToday(state, "combined-v1"))
    }
}
