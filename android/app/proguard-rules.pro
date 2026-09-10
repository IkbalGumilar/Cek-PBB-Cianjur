# Catatan dari pengalaman pahit: R8 (default aktif di build release Flutter)
# pernah mengacak nama field sebuah data class Kotlin yang diserialisasi
# lewat Gson (media_store_plus, sudah dilepas dari proyek ini), sehingga JSON
# yang dihasilkan berubah bentuk dan parsing manual di sisi Dart gagal diam-
# diam — hanya muncul di build release, tidak di build debug. Baris di bawah
# ini pencegahan umum kalau suatu saat ada dependency lain yang juga pakai
# Gson/reflection untuk (de)serialisasi.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep class com.google.gson.** { *; }
-keep class * implements java.io.Serializable { *; }

# ====================================================================
# ATURAN BARU UNTUK GOOGLE ML KIT (Mengatasi Crash MissingDependency)
# ====================================================================

# 1. Menjaga SELURUH ekosistem ML Kit (bukan cuma Text Recognition)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# 2. Menjaga komponen Firebase yang digunakan oleh ML Kit untuk Inisiasi
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.provider.** { *; }

# 3. Mencegah error terkait antarmuka builder (Missing class ... Builder)
-keepclassmembers class com.google.mlkit.** {
    public <init>(...);
}

# 4. Mengabaikan peringatan bahasa yang tidak terpakai
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**