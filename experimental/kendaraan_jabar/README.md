# Eksperimen Cek Kendaraan Jawa Barat

**Status: ditunda pada 12 September 2026. Modul ini tidak termasuk aplikasi Cek PBB.**

Prototipe sebelumnya dihentikan karena alamat yang diuji,
`https://sambara-v2.bapenda.jabarprov.go.id/`, mengembalikan **HTTP 404** baik
melalui permintaan langsung maupun WebView Linux. Karena halaman sumber tidak
tersedia, form, captcha, dan hasil tidak bisa diverifikasi secara end-to-end.

Layanan sumber menggunakan Google reCAPTCHA. Apabila eksperimen dilanjutkan,
reCAPTCHA dan permintaan informasi harus tetap dikerjakan halaman resmi di
browser/WebView pengguna. Jangan mengirim ulang permintaan, token captcha, atau
kredensial melalui Dio maupun menyimpannya di aplikasi.

Sebelum mengaktifkan kembali fitur ini:

1. Temukan dan uji manual halaman atau API resmi yang sedang aktif.
2. Pastikan alur lengkap berjalan: pengisian plat, reCAPTCHA oleh pengguna, dan
   hasil informasi kendaraan.
3. Tambahkan integrasi kembali hanya setelah uji tersebut berhasil di Android,
   Windows, dan Linux.

Rujukan historis Bapenda Jawa Barat menjelaskan pengecekan melalui `infopkb`
dan captcha, tetapi rujukan itu bukan bukti bahwa endpoint saat ini masih aktif:
https://bapenda.jabarprov.go.id/2023/03/13/cara-cek-pajak-kendaraan-bermotor-jawa-barat-dengan-mudah/
