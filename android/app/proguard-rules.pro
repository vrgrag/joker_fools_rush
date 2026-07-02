-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.appsflyer.** { *; }
-keep class com.google.android.gms.** { *; }
-keepclassmembers class * {
    @com.google.firebase.messaging.FirebaseMessagingService <methods>;
}
-dontwarn com.google.**
-dontwarn com.appsflyer.**
-dontwarn org.slf4j.**
