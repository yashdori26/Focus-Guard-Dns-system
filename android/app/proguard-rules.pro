# Suppress warnings for annotations missing in compile-time libraries
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn javax.annotation.concurrent.**
-dontwarn org.checkerframework.**

# Keep Tink and AndroidX Security crypto classes
-keep class com.google.crypto.tink.** { *; }
-keep class androidx.security.crypto.** { *; }
