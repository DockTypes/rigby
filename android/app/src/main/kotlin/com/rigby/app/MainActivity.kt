package com.rigby.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        requestBatteryOptimizationExemption()
    }

    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    startActivity(Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName")
                    ))
                    Log.d("RigbyMain", "Battery optimization exemption requested")
                } catch (e: Exception) {
                    Log.e("RigbyMain", "Could not request battery optimization exemption: ${e.message}")
                }
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION,
                )
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            Log.d("RigbyMain", "POST_NOTIFICATIONS permission: ${if (granted) "GRANTED" else "DENIED"}")
            // If denied, the foreground service notification won't show on Android 13+.
            // The app continues to function; wake word still works, just without visible notification.
        }
    }

    private fun startRigbyService() {
        try {
            val intent = Intent(this, RigbyListeningService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.d("RigbyMain", "✅ RigbyListeningService started")
        } catch (e: Exception) {
            Log.e("RigbyMain", "❌ startRigbyService failed: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun stopRigbyService() {
        try {
            stopService(Intent(this, RigbyListeningService::class.java))
            Log.d("RigbyMain", "✅ RigbyListeningService stopped")
        } catch (e: Exception) {
            Log.e("RigbyMain", "❌ stopRigbyService failed: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rigby.app/foreground_service",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> { startRigbyService(); result.success(null) }
                "stop"  -> { stopRigbyService();  result.success(null) }
                else    -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rigby.app/audio_control",
        ).setMethodCallHandler { call, result ->
            val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
            when (call.method) {
                "muteBeep" -> {
                    try {
                        val mVol = am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
                        val nVol = am.getStreamVolume(android.media.AudioManager.STREAM_NOTIFICATION)
                        val sVol = am.getStreamVolume(android.media.AudioManager.STREAM_SYSTEM)

                        if (!isMuted) {
                            // Save current volume only when not already muted to avoid saving 0
                            savedMusicVolume = mVol
                            savedNotifVolume = nVol
                            savedSystemVolume = sVol
                        }

                        // Mute audio streams that might play Google STT prompt beeps
                        am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, 0, 0)
                        try { am.setStreamVolume(android.media.AudioManager.STREAM_NOTIFICATION, 0, 0) } catch (_: Exception) {}
                        try { am.setStreamVolume(android.media.AudioManager.STREAM_SYSTEM, 0, 0) } catch (_: Exception) {}
                        isMuted = true

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("RigbyAudio", "muteBeep failed: ${e.message}")
                        result.success(false)
                    }
                }
                "unmuteBeep" -> {
                    try {
                        if (isMuted) {
                            am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, savedMusicVolume, 0)
                            try { am.setStreamVolume(android.media.AudioManager.STREAM_NOTIFICATION, savedNotifVolume, 0) } catch (_: Exception) {}
                            try { am.setStreamVolume(android.media.AudioManager.STREAM_SYSTEM, savedSystemVolume, 0) } catch (_: Exception) {}
                            isMuted = false
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e("RigbyAudio", "unmuteBeep failed: ${e.message}")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rigby.app/system_control",
        ).setMethodCallHandler { call, result ->
            val nm = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            when (call.method) {
                "enableDnd" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (nm.isNotificationPolicyAccessGranted) {
                            // PRIORITY allows user alarms and timers to sound while suppressing disruptive notifications
                            nm.setInterruptionFilter(android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                            result.success(true)
                        } else {
                            val intent = Intent(android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "disableDnd" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        if (nm.isNotificationPolicyAccessGranted) {
                            nm.setInterruptionFilter(android.app.NotificationManager.INTERRUPTION_FILTER_ALL)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
        // Streams real-time audio RMS amplitude and FFT formant data from hardware output to Flutter
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rigby.app/audio_visualizer",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                if (events == null) return
                startVisualizer(events)
            }
            override fun onCancel(arguments: Any?) {
                stopVisualizer()
            }
        })
    }

    private var visualizer: Visualizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var lastAmp = 0.0

    private fun startVisualizer(events: EventChannel.EventSink) {
        stopVisualizer()
        try {
            // Session 0 targets the global audio output mix
            val viz = Visualizer(0)
            viz.captureSize = 128
            viz.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        visualizer: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (waveform == null) return
                        var sumSquares = 0.0
                        for (b in waveform) {
                            val sample = (b.toInt() and 0xFF) - 128
                            sumSquares += sample * sample
                        }
                        val rms = sqrt(sumSquares / waveform.size)
                        lastAmp = (rms / 50.0).coerceIn(0.0, 1.0)
                    }
                    
                    override fun onFftDataCapture(
                        visualizer: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int,
                    ) {
                        if (fft == null) return
                        var lowEnergy = 0.0
                        var highEnergy = 0.0
                        
                        val numBins = fft.size / 2
                        // fft[0] is DC, fft[1] is Nyquist. Bins start at i=1 (fft[2], fft[3]).
                        for (i in 1 until numBins) {
                            val real = fft[i * 2].toDouble()
                            val imag = fft[i * 2 + 1].toDouble()
                            val mag = sqrt(real * real + imag * imag)
                            
                            // Lower bins (~300-1000 Hz) represent rounded vowels (O, U); higher bins correspond to open vowels (E, I) and consonants (S, T).
                            if (i <= 3) {
                                lowEnergy += mag
                            } else {
                                highEnergy += mag
                            }
                        }
                        
                        val total = lowEnergy + highEnergy
                        // Ratio: 1.0 = rounded vowels (O/U), 0.0 = wide vowels/consonants (S/E/I)
                        val formantRatio = if (total > 5.0) {
                            (lowEnergy / (total)).coerceIn(0.0, 1.0)
                        } else {
                            0.5 // Neutral fallback when silent
                        }
                        
                        mainHandler.post {
                            try {
                                events.success(mapOf("amp" to lastAmp, "formant" to formantRatio))
                            } catch (_: Exception) {}
                        }
                    }
                },
                Visualizer.getMaxCaptureRate(), 
                true,  // waveform ON
                true,  // FFT ON
            )
            viz.enabled = true
            visualizer = viz
            Log.d("RigbyViz", "✅ Visualizer started (capture size: ${viz.captureSize})")
        } catch (e: Exception) {
            Log.e("RigbyViz", "❌ Visualizer init failed: ${e.message}")
        }
    }

    private fun stopVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
    }

    override fun onDestroy() {
        stopVisualizer()
        super.onDestroy()
    }

    private var savedMusicVolume = 0
    private var savedNotifVolume = 0
    private var savedSystemVolume = 0
    private var isMuted = false

    companion object {
        private const val REQUEST_NOTIFICATION_PERMISSION = 1001
    }
}
