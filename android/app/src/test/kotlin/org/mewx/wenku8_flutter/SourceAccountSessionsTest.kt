package org.mewx.wenku8_flutter

import com.google.gson.Gson
import org.junit.Assert.*
import org.junit.Test

class SourceAccountSessionsTest {
    private val gson = Gson()
    private val address = "https://auth.example.invalid/"
    private fun cookie(age: Long, saved: Long = System.currentTimeMillis(), domain: String? = null) = gson.toJson(listOf(
        mapOf("name" to "session", "value" to "fixture-session", "domain" to domain, "path" to "/",
            "secure" to true, "version" to 0, "maxAge" to age, "savedAt" to saved, "origin" to address)))

    @Test fun sessionCookieAndHostOriginSurviveAProcessRoundTrip() {
        val original = SourceNetwork()
        original.restore("one", cookie(-1))
        val restored = SourceNetwork()
        restored.restore("one", original.session("one"))
        assertEquals("session=fixture-session", restored.cookie("one", address))
        assertEquals("", restored.cookie("other", address))
        assertTrue(restored.hasCookies("one"))
    }

    @Test fun expiredPersistentCookiesStayExpired() {
        val network = SourceNetwork()
        network.restore("one", cookie(1, System.currentTimeMillis() - 10_000))
        assertFalse(network.hasCookies("one"))
    }

    @Test fun cookieDeletionIsNotRestored() {
        val network = SourceNetwork()
        network.restore("one", cookie(0))
        assertFalse(network.hasCookies("one"))
    }

    private fun rules(script: String) = mapOf<String, Any?>(
        "bookSourceUrl" to "https://account.example.invalid", "mainJs" to script,
        "ruleAccount" to mapOf("verify" to mapOf("js" to "getAccount"), "checkIn" to mapOf("js" to "checkIn")))
    private fun state() = SourceState().apply { put("login", "header", "{\"Authorization\":\"Bearer fixture\"}") }

    @Test fun verifiedProfilesRoundTripWithoutExposingTokens() {
        val state = state()
        val source = rules("function getAccount(){return {loggedIn:true,id:'7',displayName:'Reader',avatarUrl:'https://cdn.example.invalid/avatar.png',token:'must-stay-private'}}")
        assertEquals(true, BookSourceEngine(source, SourceRun(state=state, fetch={ _, _, _, _ -> error("Unexpected network request") })).execute("accountVerify"))
        val restored = SourceState().apply { restore(state.snapshot()) }
        SourceAccountState.changed(restored)
        val view = SourceAccountState.view(source, restored, false)
        assertEquals("saved", view["status"])
        val profile = view["profile"] as Map<*, *>
        assertEquals("Reader", profile["displayName"])
        assertFalse(profile.containsKey("token"))
        assertEquals(state.get("login", "header"), restored.get("login", "header"))
    }

    @Test fun authenticationFailureDiffersFromTransportFailureWithoutDeletingSession() {
        val state = state()
        val expired = rules("function getAccount(){throw new Error('SOURCE_AUTH_EXPIRED:expired')}")
        assertEquals(false, BookSourceEngine(expired, SourceRun(state=state, fetch={ _, _, _, _ -> error("Unexpected network request") })).execute("accountVerify"))
        assertEquals("signedOut", SourceAccountState.view(expired, state, false)["status"])
        val unavailable = rules("function getAccount(){throw new Error('HTTP 503')}")
        try { BookSourceEngine(unavailable, SourceRun(state=state, fetch={ _, _, _, _ -> error("Unexpected network request") })).execute("accountVerify"); fail() }
        catch (_: Exception) { assertEquals("error", SourceAccountState.view(unavailable, state, false)["status"]) }
        assertTrue(state.get("login", "header").contains("Bearer fixture"))
    }

    @Test fun signalRFailuresExposeOnlyTheirStageAndHttpStatus() {
        try {
            SourceSignalR.invoke(address, "fixture-private-token", "GetMyInfo", emptyMap(),
                SourceRun(fetch={ _, _, _, _ -> error("Unexpected nested request") })) { url, _, _, _ ->
                SourceReply(url, "fixture-private-response", 403)
            }
            fail()
        } catch (failure: Exception) {
            val message = sourceRuleFailureMessage(failure)!!
            assertTrue(message.contains("HTTP 403"))
            assertTrue(message.contains("连接协商"))
            assertFalse(message.contains("fixture-private"))
            assertTrue(sourceFailureDiagnostic(failure).contains("http 403"))
        }
    }

    @Test fun verificationRetainsSafeHttpFailureDetailsAndClearsThemOnSuccess() {
        val state = state()
        val source = rules("function getAccount(){java.get('https://account.example.invalid/?token=fixture-private',{});return {loggedIn:true}}")
        try {
            BookSourceEngine(source, SourceRun(state=state, fetch={ url, _, _, _ -> SourceReply(url, "fixture-private-body", 503) })).execute("accountVerify")
            fail()
        } catch (_: Exception) {
            val view = SourceAccountState.view(source, state, false)
            assertEquals("error", view["status"])
            val message = view["validationError"] as String
            assertTrue(message.contains("HTTP 503"))
            assertFalse(message.contains("fixture-private"))
        }
        SourceAccountState.verified(state, true)
        assertEquals("", SourceAccountState.view(source, state, false)["validationError"])
    }

    @Test fun checkInDoesNotRepeatAndTokenRotationKeepsTodaysResult() {
        val state = state()
        val source = rules("function checkIn(){source.putVariable(String(Number(source.getVariable()||0)+1));return {success:true}}")
        val first = BookSourceEngine(source, SourceRun(state=state, fetch={ _, _, _, _ -> error("Unexpected network request") })).execute("accountCheckIn") as Map<*, *>
        state.put("login", "header", "{\"Authorization\":\"Bearer refreshed\"}")
        val second = BookSourceEngine(source, SourceRun(state=state, fetch={ _, _, _, _ -> error("Unexpected network request") })).execute("accountCheckIn") as Map<*, *>
        assertEquals(false, first["already"])
        assertEquals(true, second["already"])
        assertEquals("1", state.get("source", "__variable"))
        SourceAccountState.submitted(state)
        assertFalse(SourceAccountState.checkedInToday(state))
    }
}
