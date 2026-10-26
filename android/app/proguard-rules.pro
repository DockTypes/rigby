# Păstrează toate clasele Flutter (reflecție internă)
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Păstrează clasele noastre native
-keep class com.rigby.app.** { *; }

# speech_to_text folosește reflecție
-keep class com.csdcorp.speechtotext.** { *; }

# flutter_tts
-keep class com.tundralabs.fluttertts.** { *; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# flutter_overlay_window
-keep class net.dexef.overlay.** { *; }

# workmanager (proactive background engine)
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class androidx.work.** { *; }

# Evită warning-uri pentru librării opționale
-dontwarn com.google.**
-dontwarn javax.**
