-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Firebase and Google Play services (Ads, ML Kit) ship their own R8 rules in
# their AARs; blanket -keep rules here stopped R8 obfuscating ~11k classes.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: readable stack traces (the mapping file is uploaded by the
# Crashlytics Gradle plugin and bundled into the AAB for Play).
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
