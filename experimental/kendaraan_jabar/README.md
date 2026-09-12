# Eksperimen Cek Kendaraan Jawa Barat

**Status: digantikan oleh modul native pada 12 September 2026.**

Prototipe WebView sebelumnya dihentikan karena alamat halaman yang diuji,
`https://sambara-v2.bapenda.jabarprov.go.id/`, mengembalikan **HTTP 404** baik
melalui permintaan langsung maupun WebView Linux. Karena halaman sumber tidak
tersedia, form, captcha, dan hasil tidak bisa diverifikasi secara end-to-end.

Modul aktif sekarang ada di `lib/kendaraan/`. Modul tersebut memanggil endpoint
PKB yang masih dipakai bundle React pada snapshot BAPENDA, dengan format nomor
polisi `F WAK6286` dan hasil kartu native agar tetap tersedia di Android,
Windows, dan Linux.

Layanan web sumber menggunakan Google reCAPTCHA, tetapi bundle yang dikirim
halaman tersebut tidak menyertakan token captcha dalam request data PKB. Modul
native mengikuti request data itu dan tidak mengirim ulang token captcha. Untuk
verifikasi visual Google, gunakan tombol halaman resmi pada layar kendaraan.

Untuk pengembangan lanjutan modul ini:

1. Temukan dan uji manual halaman atau API resmi yang sedang aktif.
2. Pastikan alur lengkap berjalan: pengisian plat, reCAPTCHA oleh pengguna, dan
   hasil informasi kendaraan.
3. Tambahkan integrasi kembali hanya setelah uji tersebut berhasil di Android,
   Windows, dan Linux.

Rujukan historis Bapenda Jawa Barat menjelaskan pengecekan melalui `infopkb`
dan captcha, tetapi rujukan itu bukan bukti bahwa endpoint saat ini masih aktif:
https://bapenda.jabarprov.go.id/2023/03/13/cara-cek-pajak-kendaraan-bermotor-jawa-barat-dengan-mudah/
