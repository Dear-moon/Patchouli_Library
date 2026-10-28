package org.mewx.wenku8_flutter

import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Share successful browser verification, never captcha values/returned documents. */
internal object SourceVerification {
    private class Flight {
        val done = CountDownLatch(1)
        var users = 0
        @Volatile var error: Throwable? = null
        @Volatile var abandoned = false
    }
    private val flights = ConcurrentHashMap<String, Flight>()
    fun await(key: String?, run: SourceRun, action: () -> SourceReply): SourceReply? = run.awaitUser {
        if (key == null) return@awaitUser action()
        while (true) {
            var owner = false
            val flight = flights.compute(key) { _, current ->
                (current?.takeIf { it.done.count != 0L } ?: Flight().also { owner = true }).also { it.users++ }
            }!!
            try {
                if (owner) {
                    try { return@awaitUser action() }
                    catch (error: Throwable) {
                        if (error is CancellationException || error is InterruptedException) flight.abandoned = true else flight.error = error
                        throw error
                    } finally { flight.done.countDown() }
                }
                while (!flight.done.await(50, TimeUnit.MILLISECONDS)) run.check()
                run.check(); flight.error?.let { throw it }
                if (!flight.abandoned) return@awaitUser null
            } finally { flights.computeIfPresent(key) { _, current -> if (current !== flight) current else current.also { it.users-- }.takeIf { it.users > 0 } } }
        }
        @Suppress("UNREACHABLE_CODE") null
    }

}
