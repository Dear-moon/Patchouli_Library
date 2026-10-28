package org.mewx.wenku8_flutter

import org.junit.Assert.*
import org.junit.Test

class SourceDeclarationsTest {
    @Test fun declaredErrorsExposeOnlyTheRuleOwnedMessageAndCode() {
        val source = mapOf("bookSourceUrl" to "https://fixture.example", "bookSourceName" to "Fixture",
            "mainJs" to "function explore(){throw new Error('SOURCE_ERROR=ACCESS blocked-private-fixture');}",
            "engine" to mapOf("version" to 1, "errors" to mapOf("ACCESS" to "Please sign in")))
        val failure = assertThrows(SourceDeclaredFailure::class.java) {
            BookSourceEngine(source, SourceRun(fetch={_,_,_,_->error("No HTTP expected")})).execute("explore", "home")
        }
        assertEquals("Please sign in", sourceRuleFailureMessage(failure))
        assertTrue(sourceFailureDiagnostic(failure).contains("rule.code ACCESS"))
        assertFalse(sourceFailureDiagnostic(failure).contains("blocked-private-fixture"))
    }
    @Test fun accountVerificationPersistsTheDeclaredFailureMessage() {
        val message="Complete site verification in the account page"
        val source=mapOf("bookSourceUrl" to "https://fixture.example", "bookSourceName" to "Fixture",
            "mainJs" to "function getAccount(){throw new Error('SOURCE_ERROR=ACCESS blocked-private-fixture');}",
            "ruleAccount" to mapOf("verify" to mapOf("js" to "getAccount")),
            "engine" to mapOf("version" to 1,"errors" to mapOf("ACCESS" to message)))
        val saved="{\"username\":\"fixture-user\"}"
        val state=SourceState().apply {put("login","info",saved)}
        val failure=assertThrows(SourceDeclaredFailure::class.java) {
            BookSourceEngine(source,SourceRun(state=state,fetch={_,_,_,_->error("No HTTP expected")})).execute("accountVerify")
        }
        val view=SourceAccountState.view(source,state,false)
        assertEquals("error",view["status"])
        assertEquals(message,view["validationError"])
        assertEquals(message,sourceRuleFailureMessage(failure))
        assertEquals(saved,state.get("login","info"))
        assertFalse(sourceFailureDiagnostic(failure).contains("blocked-private-fixture"))
    }
    @Test fun formAndManualWebLoginAreSeparatelyDeclared() {
        val source = mapOf("bookSourceUrl" to "https://login.example", "bookSourceName" to "Fixture",
            "loginUrl" to "login()", "loginUi" to "[]",
            "engine" to mapOf("version" to 1, "login" to mapOf("webUrl" to "https://login.example/signin", "thirdPartyCookies" to true)))
        val engine = BookSourceEngine(source, SourceRun(fetch={_,_,_,_->error("No HTTP expected")}))
        assertEquals("https://login.example/signin", (engine.execute("loginUi") as Map<*, *>)["webUrl"])
        assertEquals("https://login.example/signin", engine.loginWebRequest().url)
        assertTrue(engine.loginWebRequest().thirdPartyCookies)
    }
    @Test fun sourceVariantsShareOnlyTheDeclaredSameOriginSession() {
        val source = mapOf("bookSourceUrl" to "https://shared.example#a", "engine" to mapOf("version" to 1,
            "session" to mapOf("id" to "fixture-shared", "members" to listOf("https://shared.example#a", "https://shared.example#b"))))
        SourceSessionIdentity.register(source)
        assertEquals("fixture-shared", SourceSessionIdentity.key("https://shared.example#b"))
        assertThrows(IllegalArgumentException::class.java) {
            SourceSessionIdentity.register(source + ("bookSourceUrl" to "https://unrelated.example#a"))
        }
    }
}
