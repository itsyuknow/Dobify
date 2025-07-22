# Razorpay SDK keep rules
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Google Sign-In and Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Firebase Authentication
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Supabase SDK
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Flutter plugins
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }

# Network libraries
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**

# JSON serialization
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Basic attributes
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod