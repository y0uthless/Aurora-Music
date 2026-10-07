package com.aurorasoftware.music

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Engine-scoped, not activity-scoped: the window survives leaving Aurora.
 * Playback remains owned by audio_service; this plugin never starts a player
 * or a second foreground service. No accessibility/notification access needed.
 */
class FloatingLyricsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var manager: WindowManager
    private var panel: LinearLayout? = null
    private var currentLine: TextView? = null
    private var nextLine: TextView? = null
    private var lockButton: Button? = null
    private var params: WindowManager.LayoutParams? = null
    private var locked = false
    private var controls: LinearLayout? = null
    private val handler = Handler(Looper.getMainLooper())
    private val hideControls = Runnable { controls?.visibility = View.GONE }

    private fun revealControls() {
        controls?.visibility = View.VISIBLE
        handler.removeCallbacks(hideControls)
        handler.postDelayed(hideControls, 5000L)
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        manager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        channel = MethodChannel(binding.binaryMessenger, "aurora/floating_lyrics")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        hide()
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "hasPermission" -> result.success(Settings.canDrawOverlays(context))
                "requestPermission" -> {
                    context.startActivity(Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:${context.packageName}")
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "hide" -> { hide(); result.success(null) }
                "update" -> {
                    if (!Settings.canDrawOverlays(context)) {
                        hide()
                        result.error("OVERLAY_PERMISSION", "Allow display over other apps first.", null)
                        return
                    }
                    if (panel == null) createPanel()
                    update(call)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            hide()
            result.error("OVERLAY_ERROR", e.message ?: "Unable to display lyrics.", null)
        }
    }

    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).roundToInt()
    private fun prefs() = context.getSharedPreferences("aurora_floating_window", Context.MODE_PRIVATE)

    private fun createPanel() {
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(12), dp(6), dp(12), dp(8))
        }
        val controls = LinearLayout(context).apply {
            gravity = Gravity.END
            visibility = View.GONE
        }
        this.controls = controls
        val handle = TextView(context).apply {
            text = "⋮⋮"
            contentDescription = "Drag floating lyrics"
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER_VERTICAL
        }
        controls.addView(handle, LinearLayout.LayoutParams(0, dp(36), 1f))
        lockButton = Button(context).apply {
            textSize = 12f
            minWidth = 0
            minimumWidth = 0
            setPadding(dp(4), 0, dp(4), 0)
            setOnClickListener {
                locked = !locked
                updateLock()
                revealControls()
                channel.invokeMethod("lockChanged", locked)
            }
        }
        controls.addView(lockButton, LinearLayout.LayoutParams(dp(76), dp(36)))
        controls.addView(Button(context).apply {
            text = "×"
            contentDescription = "Close floating lyrics"
            minWidth = 0
            minimumWidth = 0
            setPadding(0, 0, 0, 0)
            setOnClickListener {
                hide()
                channel.invokeMethod("closed", null)
            }
        }, LinearLayout.LayoutParams(dp(42), dp(36)))
        root.addView(controls)
        currentLine = TextView(context).apply {
            gravity = Gravity.CENTER
            setShadowLayer(dp(2).toFloat(), 0f, 0f, Color.BLACK)
            maxLines = 3
        }
        nextLine = TextView(context).apply {
            gravity = Gravity.CENTER
            setShadowLayer(dp(2).toFloat(), 0f, 0f, Color.BLACK)
            maxLines = 2
        }
        root.addView(currentLine)
        root.addView(nextLine)
        val width = (context.resources.displayMetrics.widthPixels - dp(24))
            .coerceAtMost(dp(360)).coerceAtLeast(dp(160))
        params = WindowManager.LayoutParams(
            width, WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            x = prefs().getInt("x", dp(12))
            y = prefs().getInt("y", dp(120))
        }
        root.setOnClickListener { revealControls() }
        var moved = false
        val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        val drag = View.OnTouchListener { _, event ->
            val p = params ?: return@OnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    moved = false
                    handler.removeCallbacks(hideControls)
                    startX = p.x; startY = p.y
                    touchX = event.rawX; touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (dx * dx + dy * dy > touchSlop * touchSlop) moved = true
                    if (!locked && moved) {
                        p.x = startX + dx.roundToInt()
                        p.y = startY + dy.roundToInt()
                        clampPosition(root, p)
                        manager.updateViewLayout(root, p)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) root.performClick()
                    else if (controls.visibility == View.VISIBLE) revealControls()
                    prefs().edit().putInt("x", p.x).putInt("y", p.y).apply()
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (controls.visibility == View.VISIBLE) revealControls()
                    true
                }
                else -> false
            }
        }
        handle.setOnTouchListener(drag)
        currentLine?.setOnTouchListener(drag)
        nextLine?.setOnTouchListener(drag)
        panel = root
        manager.addView(root, params)
        root.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val p = params ?: return@addOnLayoutChangeListener
            val oldX = p.x; val oldY = p.y; val oldWidth = p.width
            clampPosition(root, p)
            if (oldX != p.x || oldY != p.y || oldWidth != p.width) manager.updateViewLayout(root, p)
        }
    }

    private fun clampPosition(root: View, p: WindowManager.LayoutParams) {
        val metrics = context.resources.displayMetrics
        p.width = (metrics.widthPixels - dp(24)).coerceAtMost(dp(360))
            .coerceAtLeast(dp(160))
        p.x = p.x.coerceIn(0, (metrics.widthPixels - p.width).coerceAtLeast(0))
        p.y = p.y.coerceIn(0, (metrics.heightPixels - root.height - dp(24)).coerceAtLeast(0))
    }

    private fun updateLock() {
        lockButton?.text = if (locked) "Unlock" else "Lock"
        lockButton?.contentDescription = if (locked) "Unlock position" else "Lock position"
    }

    private fun update(call: MethodCall) {
        val opacity = (call.argument<Number>("textOpacity")?.toDouble() ?: 1.0).coerceIn(0.0, 1.0)
        val background = (call.argument<Number>("backgroundOpacity")?.toDouble() ?: 0.25).coerceIn(0.0, 1.0)
        val fontSize = (call.argument<Number>("fontSize")?.toFloat() ?: 20f).coerceIn(12f, 36f)
        val color = call.argument<Number>("textColor")?.toLong()?.toInt() ?: Color.WHITE
        val textColor = Color.rgb(Color.red(color), Color.green(color), Color.blue(color))
        locked = call.argument<Boolean>("locked") ?: false
        updateLock()
        currentLine?.apply {
            text = call.argument<String>("line") ?: ""
            textSize = fontSize
            setTextColor(textColor)
            alpha = opacity.toFloat()
        }
        nextLine?.apply {
            text = call.argument<String>("next") ?: ""
            textSize = fontSize * .85f
            setTextColor(textColor)
            alpha = opacity.toFloat()
            visibility = if (text.isEmpty()) View.GONE else View.VISIBLE
        }
        panel?.background = GradientDrawable().apply {
            cornerRadius = dp(12).toFloat()
            setColor(Color.argb((background * 255).roundToInt(), 0, 0, 0))
        }
    }

    private fun hide() {
        handler.removeCallbacks(hideControls)
        controls = null
        panel?.let { root ->
            try { manager.removeView(root) } catch (_: IllegalArgumentException) { }
        }
        panel = null
        params = null
        currentLine = null
        nextLine = null
        lockButton = null
    }
}
