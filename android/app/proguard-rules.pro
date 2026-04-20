# Keep Flutter embedding classes accessed via JNI (e.g. path_provider_android uses jni package)
-keep class io.flutter.** { *; }
# Flutter engine references Play Core for deferred components, but we don't use it
-dontwarn com.google.android.play.core.**
