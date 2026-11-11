# flutter_local_notifications serialises scheduled notifications with Gson.
# R8 strips the generic signatures Gson needs, so in release builds scheduled
# notifications fail to (de)serialise and never fire.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.dexterous.** { *; }

# workmanager background isolate entry point
-keep class be.tramckrijte.workmanager.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# home_widget receivers / our widget classes are referenced from the manifest
-keep class es.antonborri.home_widget.** { *; }
-keep class com.naviwix.roadmapx.** { *; }

# Flutter deferred components / Play Core classes that may be referenced
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
