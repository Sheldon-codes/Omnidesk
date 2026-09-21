package com.bigbrainzsolutions.omnidesk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.view.View
import android.widget.LinearLayout
import android.widget.Space
import android.widget.TextView

/**
 * Native ringing-only surface. Android self-managed Telecom provides call
 * integration and CallStyle, but not a complete full-screen dialer UI; this
 * activity is intentionally the single native ringing surface.
 */
class OmniDeskIncomingCallActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.statusBarColor = screenBackground
        window.navigationBarColor = screenBackground
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR

        val callId = intent.getStringExtra(extraCallId).orEmpty()
        if (callId.isBlank()) { finish(); return }
        when (intent.action) {
            answerAction -> { OmniDeskTelecomManager.answer(applicationContext, callId); finish(); return }
            declineAction -> { OmniDeskTelecomManager.decline(applicationContext, callId); finish(); return }
        }
        val name = intent.getStringExtra(extraCallerName).orEmpty()
        val number = intent.getStringExtra(extraCallerNumber).orEmpty()
        setContentView(content(name.ifBlank { number }, number, callId))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        recreate()
    }

    private fun content(name: String, number: String, callId: String): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(28), dp(44), dp(28), dp(36))
            setBackgroundColor(screenBackground)
            addView(label("OmniDesk", 15f, muted, Typeface.BOLD).apply { gravity = Gravity.CENTER_HORIZONTAL })
            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
            addView(initialAvatar(name))
            addView(label(name, 30f, primary, Typeface.BOLD).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, dp(24), 0, dp(8))
            })
            addView(label(number, 18f, muted, Typeface.NORMAL).apply { gravity = Gravity.CENTER_HORIZONTAL })
            addView(label("Incoming OmniDesk call", 16f, muted, Typeface.NORMAL).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, dp(14), 0, 0)
            })
            addView(Space(context), LinearLayout.LayoutParams(1, 0, 1f))
            addView(LinearLayout(context).apply {
                gravity = Gravity.CENTER
                orientation = LinearLayout.HORIZONTAL
                addView(action("Decline", dangerSurface, dangerText) { OmniDeskTelecomManager.decline(applicationContext, callId); finish() }, actionParams())
                addView(Space(context), LinearLayout.LayoutParams(dp(16), 1))
                addView(action("Answer", accent, Color.WHITE) { OmniDeskTelecomManager.answer(applicationContext, callId); finish() }, actionParams())
            })
            addView(label("Use the device controls to silence or dismiss this call.", 12f, muted, Typeface.NORMAL).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(0, dp(24), 0, 0)
            })
        }

    private fun initialAvatar(name: String): TextView = label(
        name.trim().take(1).uppercase().ifBlank { "?" }, 44f, accent, Typeface.NORMAL
    ).apply {
        gravity = Gravity.CENTER
        background = rounded(accentSurface, dp(72))
    }.also { view -> view.layoutParams = LinearLayout.LayoutParams(dp(120), dp(120)) }

    private fun action(text: String, surface: Int, textColor: Int, onClick: () -> Unit) =
        label(text, 16f, textColor, Typeface.BOLD).apply {
            gravity = Gravity.CENTER
            minHeight = dp(56)
            background = rounded(surface, dp(28))
            isClickable = true
            isFocusable = true
            setOnClickListener { onClick() }
        }

    private fun actionParams() = LinearLayout.LayoutParams(0, dp(56), 1f)
    private fun label(text: String, size: Float, color: Int, style: Int) = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        typeface = Typeface.create("sans", style)
    }
    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val answerAction = "com.bigbrainzsolutions.omnidesk.ANSWER_CALL"
        const val declineAction = "com.bigbrainzsolutions.omnidesk.DECLINE_CALL"
        private const val extraCallId = OmniDeskTelecomManager.extraCallId
        private const val extraCallerName = OmniDeskTelecomManager.extraCallerName
        private const val extraCallerNumber = OmniDeskTelecomManager.extraCallerNumber
        private const val screenBackground = 0xfffcfbff.toInt()
        private const val primary = 0xff181525.toInt()
        private const val muted = 0xff787287.toInt()
        private const val accent = 0xffec3f93.toInt()
        private const val accentSurface = 0xffffecf6.toInt()
        private const val dangerSurface = 0xffffeaec.toInt()
        private const val dangerText = 0xffb42336.toInt()

        fun intent(context: Context, values: Map<String, String>, action: String? = null): Intent =
            Intent(context, OmniDeskIncomingCallActivity::class.java).apply {
                this.action = action
                putExtra(extraCallId, values["callId"])
                putExtra(extraCallerName, values["callerName"])
                putExtra(extraCallerNumber, values["callerNumber"])
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
    }
}
