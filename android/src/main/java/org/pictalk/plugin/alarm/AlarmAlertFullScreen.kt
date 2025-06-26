package org.pictalk.plugin.alarm

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.FragmentActivity
import com.getcapacitor.Logger
import kotlinx.serialization.json.Json
import org.pictalk.plugin.alarm.alarm.AlarmService
import org.pictalk.plugin.alarm.models.AlarmSettings
import java.io.InputStream
import java.text.SimpleDateFormat
import java.util.*

/**
 * Alarm Clock alarm alert: pops visible indicator and plays alarm tone. This activity is the full
 * screen version which shows over the lock screen with the wallpaper as the background.
 *
 * Adapted from the AlarmClock reference implementation for the Capacitor alarm plugin.
 */
class AlarmAlertFullScreen : FragmentActivity() {
    companion object {
        private const val TAG = "AlarmAlertFullScreen"
        const val EXTRA_ALARM_ID = "alarm_id"
        const val EXTRA_ALARM_SETTINGS = "alarm_settings"
    }

    private var alarmId: Int = -1
    private var alarmSettings: AlarmSettings? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set orientation based on device type
        requestedOrientation = if (isTablet()) {
            // Preserve initial rotation and disable rotation change on tablets
            if (resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT) {
                ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            } else {
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
        } else {
            // Portrait on smartphone
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }

        // Get alarm data from intent
        alarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        val alarmSettingsJson = intent.getStringExtra(EXTRA_ALARM_SETTINGS)

        if (alarmId == -1 || alarmSettingsJson == null) {
            Logger.info(TAG, "Missing alarm ID or settings")
            finish()
            return
        }

        try {
            alarmSettings = Json.decodeFromString<AlarmSettings>(alarmSettingsJson)
        } catch (e: Exception) {
            Logger.error(TAG, "Failed to parse alarm settings", e)
            finish()
            return
        }

        turnScreenOn()
        updateLayout()
    }

    private fun isTablet(): Boolean {
        return resources.getBoolean(R.bool.isTablet)
    }

    /**
     * Turns the screen on and shows over the lock screen.
     *
     * Based on the reference implementation, handling different API levels properly.
     */
    private fun turnScreenOn() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        // Deprecated flags are required on some devices, even with API>=27
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )
    }

    private fun updateLayout() {
        setContentView(R.layout.activity_alarm_alert_fullscreen)

        // Set up dismiss button
        findViewById<Button>(R.id.dismiss_button)?.apply {
            setOnClickListener {
                dismissAlarm()
            }
            text = "STOP"
            alarmSettings?.let { settings ->
                text = settings.notificationSettings.stopButton
            }
        }
        // Update alarm information
        updateAlarmInfo()
    }

    private fun updateAlarmInfo() {
        alarmSettings?.let { settings ->
            // Set alarm label - use a default if not provided
            val label = settings.notificationSettings.title
            findViewById<TextView>(R.id.alarm_label)?.text = label
            updateTimeDisplay()
            Logger.debug(TAG, "Alarm label: $label")
            loadAlarmImage(settings.notificationSettings.image)
            Logger.debug(TAG, "Alarm image: ${settings.notificationSettings.image}")
        }
    }

    private fun loadAlarmImage(imagePath: String?) {
        Logger.debug(TAG, "Loading alarm image: $imagePath")
        val imageView = findViewById<ImageView>(R.id.alarm_icon)

        if (imagePath.isNullOrBlank()) {
            // Use default alarm icon if no image specified
            imageView?.setImageResource(R.drawable.ic_alarm_on)
            return
        }

        try {
            Logger.info(TAG, "Loading alarm image: $imagePath")
            when {
                imagePath.startsWith("assets/") || (!imagePath.startsWith("/") && !imagePath.contains("://")) -> {
                    loadImageFromAssets(imageView, imagePath.removePrefix("assets/"))
                }
                imagePath.startsWith("content://") -> {
                    loadImageFromContentUri(imageView, imagePath)
                }
                imagePath.startsWith("file://") || imagePath.startsWith("/") -> {
                    loadImageFromFile(imageView, imagePath.removePrefix("file://"))
                }
                imagePath.startsWith("http://") || imagePath.startsWith("https://") -> {
                    Logger.warn(TAG, "Network images not supported in this implementation")
                    imageView?.setImageResource(R.drawable.ic_alarm_on)
                }
                else -> {
                    if (!loadImageFromAssets(imageView, imagePath)) {
                        imageView?.setImageResource(R.drawable.ic_alarm_on)
                    }
                }
            }
        } catch (e: Exception) {
            Logger.error(TAG, "Failed to load alarm image: $imagePath", e)
            imageView?.setImageResource(R.drawable.ic_alarm_on)
        }
    }

    private fun loadImageFromAssets(imageView: ImageView?, assetPath: String): Boolean {
        Logger.info(TAG, "Loading image from assets: $assetPath")
        return try {
            val inputStream: InputStream = assets.open(assetPath)
            val bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream.close()

            if (bitmap != null) {
                imageView?.setImageBitmap(Bitmap.createScaledBitmap(bitmap, 512, 512, true))
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Logger.error(TAG, "Failed to load image from assets: $assetPath", e)
            false
        }
    }

    private fun loadImageFromContentUri(imageView: ImageView?, uriString: String) {
        Logger.info(TAG, "Loading image from content URI: $uriString")
        try {
            val uri = Uri.parse(uriString)
            val inputStream = contentResolver.openInputStream(uri)
            val bitmap = BitmapFactory.decodeStream(inputStream)
            inputStream?.close()

            if (bitmap != null) {
                imageView?.setImageBitmap(Bitmap.createScaledBitmap(bitmap, 512, 512, true))
            } else {
                imageView?.setImageResource(R.drawable.ic_alarm_on)
            }
        } catch (e: Exception) {
            Logger.error(TAG, "Failed to load image from content URI: $uriString", e)
            imageView?.setImageResource(R.drawable.ic_alarm_on)
        }
    }

    private fun loadImageFromFile(imageView: ImageView?, filePath: String) {
        Logger.info(TAG, "Loading image from file: $filePath")
        try {
            val bitmap = BitmapFactory.decodeFile(filePath)
            if (bitmap != null) {
                imageView?.setImageBitmap(Bitmap.createScaledBitmap(bitmap, 512, 512, true))
            } else {
                imageView?.setImageResource(R.drawable.ic_alarm_on)
            }
        } catch (e: Exception) {
            Logger.error(TAG, "Failed to load image from file: $filePath", e)
            imageView?.setImageResource(R.drawable.ic_alarm_on)
        }
    }

    private fun updateTimeDisplay() {
        findViewById<TextView>(R.id.alarm_time)?.let { timeView ->
            val calendar = Calendar.getInstance()
            val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
            timeView.text = timeFormat.format(calendar.time)
        }
    }

    private fun dismissAlarm() {
        Logger.debug(TAG, "Dismissing alarm $alarmId")

        // Stop the alarm service
        AlarmService.instance?.handleStopAlarmCommand(alarmId)

        // Notify the plugin
        AlarmPlugin.instance?.notifyAlarmStopped(alarmId)

        finish()
    }

    /**
     * Handle new alarm when this activity is already running
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Logger.debug(TAG, "AlarmAlertFullScreen.onNewIntent()")

        val newAlarmId = intent.getIntExtra(EXTRA_ALARM_ID, -1)
        val alarmSettingsJson = intent.getStringExtra(EXTRA_ALARM_SETTINGS)

        if (newAlarmId != -1 && alarmSettingsJson != null) {
            alarmId = newAlarmId
            try {
                alarmSettings = Json.decodeFromString<AlarmSettings>(alarmSettingsJson)
                updateAlarmInfo()
            } catch (e: Exception) {
                Logger.error(TAG, "Failed to parse new alarm settings", e)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Update time display when resuming
        updateTimeDisplay()
    }

    @SuppressLint("MissingSuperCall")
    override fun onBackPressed() {
        // Don't allow back button to dismiss the alarm
        // User must explicitly dismiss or snooze
    }

    override fun onDestroy() {
        super.onDestroy()
        Logger.debug(TAG, "AlarmAlertFullScreen destroyed")
    }
}