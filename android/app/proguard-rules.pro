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
