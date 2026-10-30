# Flutter and the plugins used here ship their own consumer rules. Add app-specific keep rules below if a
# release build crashes with ClassNotFoundException after minification.

# The text recognition plugin refers to script models this app does not ship (Chinese, Japanese, Korean).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# WorkManager (pulled in by Google Play services and ML Kit) creates its Room database by reflection;
# without these rules the release build crashes on start with "Failed to create an instance of WorkDatabase".
-keep class * extends androidx.room.RoomDatabase { <init>(...); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.WorkDatabase { *; }

# Flutter plugins that call Java through JNI (shared_preferences, path_provider, url_launcher, local_auth, image/file pickers)
# look classes and methods up by name; renaming or removing them makes every call fail in a release build.
-keep class io.flutter.plugins.** { *; }
-keep class dev.flutter.pigeon.** { *; }
-keep class com.github.dart_lang.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# The JNI bindings above refer to Kotlin types by name (for example kotlin.coroutines.Continuation in suspend functions),
# so those names must not be renamed by R8.
-keepnames class kotlin.** { *; }
-keepnames class kotlinx.coroutines.** { *; }
