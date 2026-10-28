package org.mewx.wenku8_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle

/**
 * Permanent compatibility entry for launchers and existing explicit intents.
 *
 * A switchable alias must never identify the task containing the Flutter UI:
 * Android can remove an alias-root task even with DONT_KILL_APP. The distinct
 * ReaderActivity component also prevents reuse of tasks from older releases.
 */
class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        forward(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        forward(intent)
    }

    private fun forward(source: Intent) {
        try {
            startActivity(stableReaderIntent(this, source))
        } finally {
            // Theme.NoDisplay requires completion before onResume. No URI is
            // opened here; its grants/ClipData are transferred to the reader.
            finish()
        }
    }
}

/** Copies the full incoming contract, including file grants and stream extras. */
internal fun stableReaderIntent(context: Context, source: Intent): Intent =
    Intent(source).setClass(context, ReaderActivity::class.java).addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP,
    )
