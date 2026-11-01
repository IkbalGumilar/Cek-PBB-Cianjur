import 'package:flutter/material.dart';

enum GuideCategory {
  all('Semua', Icons.apps_rounded, Color(0xFF2E7D32)),
  publik('Layanan Publik', Icons.receipt_long_rounded, Color(0xFF1976D2)),
  dhkp('Catatan DHKP', Icons.table_chart_rounded, Color(0xFF00838F)),
  staf('Portal Petugas', Icons.admin_panel_settings_rounded, Color(0xFFE65100)),
  pengaturan('Pengaturan & Info', Icons.tune_rounded, Color(0xFF6A1B9A)),
  faq('Tanya Jawab', Icons.quiz_rounded, Color(0xFFC62828));

  final String label;
  final IconData icon;
  final Color color;

  const GuideCategory(this.label, this.icon, this.color);
}

class GuidePin {
  final int number;
  final String title;
  final String description;
  final String? tip;

  /// Koordinat titik nomor pada kanvas referensi 1080 x 2246
  final Offset dotPos;

  /// Koordinat ujung panah pada kanvas referensi 1080 x 2246
  final Offset targetPos;

  const GuidePin({
    required this.number,
    required this.title,
    required this.description,
    required this.dotPos,
    required this.targetPos,
    this.tip,
  });

  static const List<Color> palette = [
    Color(0xFF1976D2), // 1: Blue
    Color(0xFF2E7D32), // 2: Green
    Color(0xFFE65100), // 3: Orange
    Color(0xFF7B1FA2), // 4: Purple
    Color(0xFF00838F), // 5: Teal
    Color(0xFFC62828), // 6: Red
    Color(0xFF283593), // 7: Indigo
    Color(0xFFAD1457), // 8: Pink
  ];

  Color get color => palette[(number - 1) % palette.length];
}

class GuideTopic {
  final String id;
  final GuideCategory category;
  final String chapterBadge;
  final String title;
  final String subtitle;
  final String summary;
  final IconData icon;
  final String imageAsset;
  final List<GuidePin> pins;
  final String? warningNote;

  const GuideTopic({
    required this.id,
    required this.category,
    required this.chapterBadge,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.icon,
    required this.imageAsset,
    required this.pins,
    this.warningNote,
  });
}

class GuideFaqItem {
  final String question;
  final String answer;
  final IconData icon;
  final GuideCategory category;

  const GuideFaqItem({
    required this.question,
    required this.answer,
    required this.icon,
    required this.category,
  });
}

class UserGuideRepository {
  static const Size referenceCanvasSize = Size(1080, 2246);

  static const List<GuideTopic> topics = [
    // =========================================================================
    // 1. LAYANAN PUBLIK
    // =========================================================================
    GuideTopic(
      id: 'cek_tagihan',
      category: GuideCategory.publik,
      chapterBadge: 'Bab 1.1',
      title: 'Cek Tagihan PBB',
      subtitle: 'Periksa rincian tunggakan PBB-P2 & bayar lewat QRIS atau VA',
      summary:
          'Halaman utama bagi wajib pajak dan kolektor desa untuk memeriksa pokok ketetapan, denda berjalan, tahun pajak yang belum terbayar, serta melakukan pembayaran langsung melalui QRIS atau Virtual Account.',
      icon: Icons.receipt_long_rounded,
      imageAsset: 'assets/guide/01_cek_tagihan.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Baris Menu Fitur (Cek Tagihan)',
          description:
              'Geser baris tombol di bagian atas ke kiri atau kanan untuk berpindah antarfitur: Cek Tagihan, Cek Status Bayar, Monitoring, Cek Kendaraan, dan Cek Desil.',
          dotPos: Offset(214, 390),
          targetPos: Offset(214, 335),
        ),
        GuidePin(
          number: 2,
          title: 'Kolom Blok',
          description:
              'Masukkan nomor blok tempat objek pajak berada tanpa angka nol di depan.',
          tip: 'Contoh: Bila blok pada SPPT tertulis 003, cukup ketik 3.',
          dotPos: Offset(42, 778),
          targetPos: Offset(102, 778),
        ),
        GuidePin(
          number: 3,
          title: 'Kolom Nomor Wilayah',
          description:
              'Masukkan nomor urut objek pajak dari lembar SPPT Anda tanpa angka nol di depan.',
          tip: 'Contoh: Bila nomor urut tertulis 0142, cukup ketik 142.',
          dotPos: Offset(652, 640),
          targetPos: Offset(652, 702),
        ),
        GuidePin(
          number: 4,
          title: 'Tombol Pindai SPPT (Kamera OCR)',
          description:
              'Gunakan kamera ponsel untuk memotret lembar SPPT fisik. Aplikasi akan membaca dan mengisi nomor Blok serta Nomor Wilayah secara otomatis.',
          dotPos: Offset(1035, 770),
          targetPos: Offset(968, 770),
        ),
        GuidePin(
          number: 5,
          title: 'Gambar Kode Keamanan (Captcha)',
          description:
              'Kode huruf/angka dari server resmi Bapenda. Jika gambar kurang jelas, ketuk tombol "Ganti Kode Gambar" di bawahnya.',
          dotPos: Offset(210, 1112),
          targetPos: Offset(286, 1112),
        ),
        GuidePin(
          number: 6,
          title: 'Kolom Kode Verifikasi',
          description:
              'Ketik kembali huruf atau angka sesuai yang terlihat pada gambar kode di atasnya.',
          dotPos: Offset(42, 1462),
          targetPos: Offset(102, 1462),
        ),
        GuidePin(
          number: 7,
          title: 'Tombol Cek',
          description:
              'Mengambil data tagihan terbaru dari server Bapenda dan menampilkan nama wajib pajak, rincian tunggakan, serta opsi bayar QRIS / Virtual Account.',
          dotPos: Offset(42, 1648),
          targetPos: Offset(102, 1648),
        ),
        GuidePin(
          number: 8,
          title: 'Tombol Mengambang DHKP',
          description:
              'Tombol pintas cepat di pojok kanan bawah untuk membuka Buku Catatan DHKP Digital desa.',
          dotPos: Offset(680, 2130),
          targetPos: Offset(758, 2130),
        ),
      ],
    ),
    GuideTopic(
      id: 'cek_status_bayar',
      category: GuideCategory.publik,
      chapterBadge: 'Bab 1.2',
      title: 'Cek Status Bayar PBB',
      subtitle: 'Periksa bukti lunas pembayaran PBB per tahun pajak',
      summary:
          'Memastikan apakah SPPT wajib pajak pada tahun tertentu sudah tercatat lunas di kas daerah Bapenda atau masih belum dibayar.',
      icon: Icons.verified_outlined,
      imageAsset: 'assets/guide/02_cek_status_bayar.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tab Cek Status Bayar',
          description:
              'Menampilkan formulir pemeriksaan status pelunasan PBB berdasarkan tahun pajak.',
          dotPos: Offset(530, 390),
          targetPos: Offset(530, 335),
        ),
        GuidePin(
          number: 2,
          title: 'Blok, Nomor, Scan SPPT & Cek Banyak Data',
          description:
              'Masukkan Blok dan Nomor urut SPPT, pindai kertas SPPT lewat kamera, atau ketuk ikon berkas panah di kanan untuk memeriksa banyak NOP sekaligus.',
          dotPos: Offset(42, 738),
          targetPos: Offset(98, 738),
        ),
        GuidePin(
          number: 3,
          title: 'Kolom Tahun Pajak',
          description:
              'Tentukan tahun pajak yang ingin diperiksa status pembayarannya (misalnya 2026 atau tahun sebelumnya).',
          dotPos: Offset(42, 1018),
          targetPos: Offset(98, 1018),
        ),
        GuidePin(
          number: 4,
          title: 'Gambar Kode Captcha',
          description:
              'Gambar verifikasi keamanan dari server Bapenda. Ketuk "Ganti Kode Gambar" bila sulit terbaca.',
          dotPos: Offset(200, 1255),
          targetPos: Offset(265, 1255),
        ),
        GuidePin(
          number: 5,
          title: 'Kolom Kode Verifikasi',
          description:
              'Ketik kode huruf/angka sesuai gambar captcha yang tampil.',
          dotPos: Offset(42, 1602),
          targetPos: Offset(98, 1602),
        ),
        GuidePin(
          number: 6,
          title: 'Tombol Cek',
          description:
              'Menampilkan status pembayaran (Lunas / Belum Bayar) beserta tanggal lunas dan rincian objek pajak.',
          dotPos: Offset(42, 1788),
          targetPos: Offset(98, 1788),
        ),
      ],
    ),
    GuideTopic(
      id: 'cek_banyak_nop',
      category: GuideCategory.publik,
      chapterBadge: 'Bab 1.3',
      title: 'Periksa Banyak Data NOP (Massal)',
      subtitle: 'Cek puluhan hingga ratusan NOP warga secara otomatis',
      summary:
          'Memudahkan perangkat desa, ketua RT/RW, dan kolektor untuk memeriksa daftar NOP warga sekaligus dari file Excel/CSV atau ketikan langsung tanpa harus mengetik captcha berulang-ulang.',
      icon: Icons.playlist_add_check_circle_outlined,
      imageAsset: 'assets/guide/03_cek_banyak_nop.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tombol Pilih File',
          description:
              'Muat daftar NOP warga langsung dari berkas Excel (.xlsx/.xls), CSV, atau TXT di penyimpanan ponsel.',
          dotPos: Offset(42, 582),
          targetPos: Offset(98, 582),
        ),
        GuidePin(
          number: 2,
          title: 'Kotak Input Daftar NOP',
          description:
              'Ketik atau tempel (paste) banyak nomor pajak sekaligus, satu NOP per baris atau dipisahkan koma.',
          tip: 'Mendukung 18 digit NOP lengkap maupun kode singkat blok+nomor (contoh: 17154).',
          dotPos: Offset(42, 1150),
          targetPos: Offset(98, 1150),
        ),
        GuidePin(
          number: 3,
          title: 'Tombol Simpan, Scan & Hapus Semua',
          description:
              'Simpan daftar NOP agar tidak hilang, tambahkan NOP dengan memindai SPPT berurutan lewat kamera, atau kosongkan daftar.',
          dotPos: Offset(42, 1578),
          targetPos: Offset(98, 1578),
        ),
        GuidePin(
          number: 4,
          title: 'Kolom Tahun Pajak',
          description:
              'Tahun pajak yang akan digunakan serentak untuk seluruh NOP yang ada di dalam daftar.',
          dotPos: Offset(42, 1912),
          targetPos: Offset(98, 1912),
        ),
        GuidePin(
          number: 5,
          title: 'Tombol Mulai Cek',
          description:
              'Memulai pemeriksaan otomatis secara berurutan dan menampilkan rekap hasilnya.',
          dotPos: Offset(42, 2090),
          targetPos: Offset(98, 2090),
        ),
      ],
    ),
    GuideTopic(
      id: 'cek_kendaraan',
      category: GuideCategory.publik,
      chapterBadge: 'Bab 1.4',
      title: 'Cek Pajak Kendaraan Bermotor',
      subtitle: 'Informasi PKB & SWDKLLJ wilayah Jawa Barat',
      summary:
          'Layanan bantu bagi warga untuk memeriksa informasi pajak kendaraan bermotor Jawa Barat menggunakan nomor polisi atau pindaian foto plat nomor.',
      icon: Icons.directions_car_filled_outlined,
      imageAsset: 'assets/guide/04_cek_kendaraan.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tab Cek Kendaraan',
          description:
              'Membuka halaman pencarian informasi Pajak Kendaraan Bermotor (PKB) Jawa Barat.',
          dotPos: Offset(625, 390),
          targetPos: Offset(625, 335),
        ),
        GuidePin(
          number: 2,
          title: 'Kolom Nomor Polisi (XX | XXXX | XXX)',
          description:
              'Masukkan kode huruf depan wilayah (contoh: F), angka nomor polisi, dan huruf seri belakang.',
          dotPos: Offset(42, 705),
          targetPos: Offset(100, 760),
        ),
        GuidePin(
          number: 3,
          title: 'Tombol Foto / Scan Plat Nomor',
          description:
              'Arahkan kamera ke plat nomor kendaraan untuk mengisi kolom nomor polisi secara otomatis.',
          dotPos: Offset(695, 1060),
          targetPos: Offset(618, 1060),
        ),
        GuidePin(
          number: 4,
          title: 'Pilihan Warna Plat Nomor',
          description:
              'Pilih warna plat kendaraan: Hitam / Putih (Pribadi), Merah (Dinas Pemerintah), atau Kuning (Angkutan Umum).',
          dotPos: Offset(935, 1288),
          targetPos: Offset(862, 1288),
        ),
        GuidePin(
          number: 5,
          title: 'Tombol Lihat Info',
          description:
              'Menampilkan merek, tipe kendaraan, masa berlaku STNK/PKB, serta rincian tagihan pajak kendaraan.',
          dotPos: Offset(42, 1630),
          targetPos: Offset(100, 1688),
        ),
        GuidePin(
          number: 6,
          title: 'Tautan Buka Layanan Resmi Jabar',
          description:
              'Membuka halaman web resmi Bapenda Jawa Barat di peramban jika layanan utama sedang sibuk.',
          dotPos: Offset(210, 1898),
          targetPos: Offset(285, 1898),
        ),
      ],
    ),
    GuideTopic(
      id: 'cek_desil',
      category: GuideCategory.publik,
      chapterBadge: 'Bab 1.5',
      title: 'Cek Desil & Bantuan Sosial',
      subtitle: 'Periksa status desil kesejahteraan & bansos Kemensos berdasarkan NIK',
      summary:
          'Memeriksa status kepesertaan bantuan sosial dan kelompok desil kesejahteraan warga melalui layanan resmi Kemensos menggunakan 16 digit NIK KTP.',
      icon: Icons.family_restroom_rounded,
      imageAsset: 'assets/guide/05_cek_desil.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tab Cek Desil',
          description:
              'Membuka layanan pengecekan Desil & Bantuan Sosial berdasarkan NIK KTP.',
          dotPos: Offset(850, 390),
          targetPos: Offset(850, 335),
        ),
        GuidePin(
          number: 2,
          title: 'Kolom NIK (16 Digit)',
          description:
              'Masukkan 16 angka Nomor Induk Kependudukan sesuai yang tertera pada KTP atau Kartu Keluarga.',
          dotPos: Offset(42, 852),
          targetPos: Offset(98, 852),
        ),
        GuidePin(
          number: 3,
          title: 'Tombol Scan KTP / KK',
          description:
              'Pindai foto KTP atau KK menggunakan kamera agar 16 digit NIK terisi otomatis.',
          dotPos: Offset(1035, 842),
          targetPos: Offset(968, 842),
        ),
        GuidePin(
          number: 4,
          title: 'Gambar Huruf Kode (Captcha Kemensos)',
          description:
              'Gambar kode verifikasi dari layanan Kemensos. Ketuk "Ganti Kode Gambar" bila huruf buram.',
          dotPos: Offset(75, 1228),
          targetPos: Offset(138, 1228),
        ),
        GuidePin(
          number: 5,
          title: 'Kolom Huruf Kode',
          description:
              'Ketik huruf/angka sesuai gambar captcha yang tampil di atasnya.',
          dotPos: Offset(42, 1542),
          targetPos: Offset(98, 1542),
        ),
        GuidePin(
          number: 6,
          title: 'Tombol Cari Data',
          description:
              'Menampilkan informasi desil kesejahteraan dan status kepesertaan bantuan sosial warga.',
          dotPos: Offset(42, 1792),
          targetPos: Offset(98, 1792),
        ),
      ],
    ),

    // =========================================================================
    // 2. CATATAN DHKP DESA
    // =========================================================================
    GuideTopic(
      id: 'dhkp_catatan',
      category: GuideCategory.dhkp,
      chapterBadge: 'Bab 2.1',
      title: 'Buku Catatan DHKP Digital',
      subtitle: 'Kelola tabel DHKP, grafik capaian blok, ekspor Excel & sinkronisasi',
      summary:
          'Buku kerja digital bagi perangkat desa dan kolektor untuk memuat berkas DHKP, menandai status pelunasan warga di lapangan, melampirkan foto bukti bayar, melihat grafik capaian per blok, hingga mengekspor laporan Excel/PDF.',
      icon: Icons.table_chart_rounded,
      imageAsset: 'assets/guide/06_dhkp_catatan.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Ikon Grafik Ringkasan',
          description:
              'Berpindah antara tampilan tabel daftar wajib pajak dan tampilan grafik visualisasi capaian penerimaan per blok.',
          dotPos: Offset(512, 265),
          targetPos: Offset(512, 195),
        ),
        GuidePin(
          number: 2,
          title: 'Ikon Unggah Data DHKP',
          description:
              'Memuat berkas daftar pajak DHKP (.xlsx, .xls, .csv, atau paket .dkhp) dari memori ponsel ke dalam aplikasi.',
          dotPos: Offset(632, 265),
          targetPos: Offset(632, 195),
        ),
        GuidePin(
          number: 3,
          title: 'Ikon Unduh / Ekspor Laporan',
          description:
              'Mengekspor hasil pencatatan lapangan kembali menjadi berkas Excel atau laporan PDF siap cetak.',
          dotPos: Offset(748, 265),
          targetPos: Offset(748, 195),
        ),
        GuidePin(
          number: 4,
          title: 'Ikon Sinkronisasi Cadangan',
          description:
              'Menyinkronkan perubahan catatan DHKP dengan penyimpanan lokal atau folder Google Drive.',
          dotPos: Offset(865, 265),
          targetPos: Offset(865, 195),
        ),
        GuidePin(
          number: 5,
          title: 'Ikon Panduan (?)',
          description:
              'Menampilkan tur panduan interaktif untuk mengenal fungsi tombol-tombol pada halaman Data DHKP.',
          dotPos: Offset(980, 265),
          targetPos: Offset(980, 195),
        ),
      ],
    ),

    // =========================================================================
    // 3. PORTAL PETUGAS & KOLEKTIF
    // =========================================================================
    GuideTopic(
      id: 'login_portal_staf',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.1',
      title: 'Login Portal Staf Bapenda',
      subtitle: 'Masuk menggunakan akun resmi staf desa / kolektor',
      summary:
          'Pintu masuk khusus bagi perangkat desa dan kolektor yang memiliki akun resmi Portal Staf untuk mengakses laporan penerimaan wilayah dan pembayaran kolektif.',
      icon: Icons.login_rounded,
      imageAsset: 'assets/guide/07_login_portal_staf.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Kolom Username',
          description:
              'Masukkan nama pengguna (username) akun staf desa/kelurahan yang terdaftar di Bapenda.',
          dotPos: Offset(760, 348),
          targetPos: Offset(650, 348),
        ),
        GuidePin(
          number: 2,
          title: 'Kolom Password',
          description:
              'Masukkan kata sandi akun staf Anda. Ketuk ikon mata di sebelah kanan untuk memeriksa ketikan.',
          dotPos: Offset(760, 528),
          targetPos: Offset(650, 528),
        ),
        GuidePin(
          number: 3,
          title: 'Gambar Captcha & Ganti Captcha',
          description:
              'Gambar kode keamanan login. Ketuk "Ganti Captcha" bila teks pada gambar kurang terbaca.',
          dotPos: Offset(105, 756),
          targetPos: Offset(178, 756),
        ),
        GuidePin(
          number: 4,
          title: 'Kolom Kode Verifikasi',
          description:
              'Masukkan huruf/angka sesuai gambar captcha yang tampil di atasnya.',
          dotPos: Offset(760, 1110),
          targetPos: Offset(650, 1110),
        ),
        GuidePin(
          number: 5,
          title: 'Tombol Login',
          description:
              'Memvalidasi kredensial staf dan melanjutkan ke halaman verifikasi keamanan dua langkah (MFA).',
          dotPos: Offset(760, 1288),
          targetPos: Offset(650, 1288),
        ),
      ],
    ),
    GuideTopic(
      id: 'verifikasi_mfa',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.2',
      title: 'Verifikasi Keamanan MFA',
      subtitle: 'Masukkan 6 digit kode OTP dari Google Authenticator',
      summary:
          'Pengamanan berlapis menggunakan kode OTP 6 digit dari aplikasi Google Authenticator untuk memastikan hanya petugas berwenang yang dapat mengakses data desa.',
      icon: Icons.phonelink_lock_rounded,
      imageAsset: 'assets/guide/08_verifikasi_mfa.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Kolom Kode Verifikasi (6 Digit)',
          description:
              'Masukkan 6 angka kode sementara yang tampil pada aplikasi Google Authenticator Anda.',
          dotPos: Offset(760, 502),
          targetPos: Offset(650, 502),
        ),
        GuidePin(
          number: 2,
          title: 'Tombol Verifikasi',
          description:
              'Mengonfirmasi kode 6 digit untuk membuka sesi Menu Petugas Desa.',
          dotPos: Offset(760, 688),
          targetPos: Offset(650, 688),
        ),
        GuidePin(
          number: 3,
          title: 'Panduan Google Authenticator',
          description:
              'Ketuk tautan ini jika Anda memerlukan panduan cara menghubungkan dan melihat kode di Google Authenticator.',
          dotPos: Offset(960, 878),
          targetPos: Offset(860, 878),
        ),
      ],
    ),
    GuideTopic(
      id: 'hub_petugas',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.3',
      title: 'Menu Utama Petugas Desa',
      subtitle: 'Pusat navigasi Pantauan Wilayah & Pembayaran Kolektif',
      summary:
          'Halaman utama Portal Staf setelah berhasil login, menyediakan akses ke 7 laporan pantauan wilayah desa dan manajemen grup pembayaran kolektif.',
      icon: Icons.dashboard_customize_rounded,
      imageAsset: 'assets/guide/09_hub_petugas.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Kartu Pantauan Wilayah Desa',
          description:
              'Membuka 7 laporan penerimaan desa: Sudah Bayar, Belum Bayar, Realisasi, Piutang, Sudah/Belum Bayar Kolektif, dan Rangking Realisasi.',
          dotPos: Offset(42, 417),
          targetPos: Offset(100, 417),
        ),
        GuidePin(
          number: 2,
          title: 'Kartu Pembayaran Kolektif (Rombongan)',
          description:
              'Membuka manajemen grup pembayaran rombongan warga, daftar anggota NOP, dan pencetakan surat pengantar.',
          dotPos: Offset(42, 763),
          targetPos: Offset(100, 763),
        ),
      ],
    ),
    GuideTopic(
      id: 'pantauan_wilayah',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.4',
      title: 'Pantauan Wilayah Desa (7 Laporan)',
      subtitle: 'Filter transaksi Sudah Bayar, Belum Bayar, Realisasi & Piutang',
      summary:
          'Memantau data pembayaran pajak warga di wilayah desa/kelurahan secara real-time lengkap dengan filter tanggal, tahun pajak, buku, bank, dan pencarian NOP/nama.',
      icon: Icons.analytics_outlined,
      imageAsset: 'assets/guide/10_pantauan_wilayah.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Baris 7 Tab Laporan',
          description:
              'Geser tab di bagian atas untuk memilih laporan: Sudah Bayar, Belum Bayar, Realisasi, Piutang, Sudah Bayar Kolektif, Belum Bayar Kolektif, atau Rangking Realisasi.',
          dotPos: Offset(55, 296),
          targetPos: Offset(130, 296),
        ),
        GuidePin(
          number: 2,
          title: 'Filter Tanggal Pembayaran (Awal & Akhir)',
          description:
              'Pilih rentang tanggal transaksi pembayaran yang ingin ditampilkan.',
          dotPos: Offset(500, 550),
          targetPos: Offset(400, 550),
        ),
        GuidePin(
          number: 3,
          title: 'Filter Tahun Pajak (Opsional)',
          description:
              'Saring data berdasarkan tahun ketetapan pajak awal dan akhir.',
          dotPos: Offset(360, 905),
          targetPos: Offset(240, 905),
        ),
        GuidePin(
          number: 4,
          title: 'Filter Buku & Bank',
          description:
              'Saring laporan berdasarkan golongan Buku pajak (Buku 1–5) atau kanal bank penerima.',
          dotPos: Offset(540, 1146),
          targetPos: Offset(420, 1146),
        ),
        GuidePin(
          number: 5,
          title: 'Kolom Pencarian NOP / Nama WP / Petugas',
          description:
              'Cari data spesifik berdasarkan NOP, Nama Wajib Pajak, Petugas Pembayaran, Kode Bayar, VA, atau QRIS.',
          dotPos: Offset(540, 1500),
          targetPos: Offset(420, 1500),
        ),
      ],
    ),
    GuideTopic(
      id: 'pantauan_ranking',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.5',
      title: 'Rangking Realisasi Capaian',
      subtitle: 'Evaluasi peringkat dan persentase realisasi PBB wilayah',
      summary:
          'Menampilkan tabel peringkat capaian realisasi PBB berdasarkan periode tanggal pembayaran, tanggal cutoff belum bayar, serta kategori buku.',
      icon: Icons.leaderboard_rounded,
      imageAsset: 'assets/guide/11_pantauan_ranking.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tab Rangking Realisasi',
          description:
              'Tab laporan khusus untuk melihat peringkat persentase capaian realisasi pajak.',
          dotPos: Offset(860, 395),
          targetPos: Offset(860, 340),
        ),
        GuidePin(
          number: 2,
          title: 'Filter Tanggal Pembayaran & Cutoff',
          description:
              'Tentukan periode tanggal pembayaran yang dihitung beserta tanggal cutoff tunggakan.',
          dotPos: Offset(500, 550),
          targetPos: Offset(400, 550),
        ),
        GuidePin(
          number: 3,
          title: 'Filter Buku & Bank',
          description:
              'Saring perhitungan peringkat untuk kategori buku pajak atau bank tertentu.',
          dotPos: Offset(540, 1388),
          targetPos: Offset(420, 1388),
        ),
        GuidePin(
          number: 4,
          title: 'Tombol Tampilkan',
          description:
              'Memuat daftar peringkat realisasi sesuai filter yang telah dipilih.',
          dotPos: Offset(760, 1934),
          targetPos: Offset(650, 1934),
        ),
      ],
    ),
    GuideTopic(
      id: 'pembayaran_kolektif',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.6',
      title: 'Pembayaran Kolektif (Rombongan)',
      subtitle: 'Kelola daftar grup pembayaran rombongan warga',
      summary:
          'Memudahkan perangkat desa dan kolektor menggabungkan puluhan NOP warga ke dalam satu grup rombongan bayar agar proses penyetoran lebih praktis dan terorganisir.',
      icon: Icons.groups_rounded,
      imageAsset: 'assets/guide/12_pembayaran_kolektif.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tombol Buat Grup Rombongan Baru',
          description:
              'Membuka formulir pembuatan grup rombongan baru untuk wilayah desa/kelurahan Anda.',
          dotPos: Offset(130, 769),
          targetPos: Offset(230, 769),
        ),
        GuidePin(
          number: 2,
          title: 'Filter Bulan, Status & Tanggal',
          description:
              'Saring daftar grup rombongan berdasarkan bulan, status grup (Draft / Sudah Di Bayar), tahun, atau tanggal.',
          dotPos: Offset(330, 947),
          targetPos: Offset(240, 947),
        ),
        GuidePin(
          number: 3,
          title: 'Tombol Tampilkan',
          description:
              'Memuat ulang tabel daftar grup rombongan sesuai filter yang dipilih.',
          dotPos: Offset(760, 1483),
          targetPos: Offset(650, 1483),
        ),
        GuidePin(
          number: 4,
          title: 'Daftar Baris Grup Rombongan',
          description:
              'Ketuk salah satu baris grup pada tabel untuk membuka menu Kelola Anggota, Cetak Surat Pengantar, atau Hapus Grup.',
          dotPos: Offset(42, 1863),
          targetPos: Offset(98, 1863),
        ),
      ],
    ),
    GuideTopic(
      id: 'kolektif_aksi_menu',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.7',
      title: 'Menu Aksi Grup & Surat Pengantar',
      subtitle: 'Kelola anggota NOP, cetak surat pengantar resmi, atau hapus draf',
      summary:
          'Panel aksi yang muncul ketika Anda mengetuk salah satu baris grup rombongan pada halaman Pembayaran Kolektif.',
      icon: Icons.description_outlined,
      imageAsset: 'assets/guide/13_kolektif_aksi_menu.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Menu Kelola Anggota',
          description:
              'Membuka daftar anggota NOP di dalam grup. Selama berstatus Draft, Anda dapat menambah/mengeluarkan NOP warga. Jika sudah dibayar, daftar anggota tetap dapat dilihat.',
          dotPos: Offset(700, 1705),
          targetPos: Offset(480, 1705),
        ),
        GuidePin(
          number: 2,
          title: 'Menu Cetak Surat Pengantar',
          description:
              'Membuka dan mengunduh dokumen surat pengantar resmi untuk grup rombongan tersebut.',
          dotPos: Offset(780, 1880),
          targetPos: Offset(600, 1880),
        ),
        GuidePin(
          number: 3,
          title: 'Menu Hapus Grup',
          description:
              'Menghapus grup rombongan (hanya aktif apabila grup masih berstatus Draft dan belum dikunci atau dibayar).',
          dotPos: Offset(700, 2080),
          targetPos: Offset(420, 2080),
        ),
      ],
    ),
    GuideTopic(
      id: 'tambah_group_kolektif',
      category: GuideCategory.staf,
      chapterBadge: 'Bab 3.8',
      title: 'Formulir Tambah Group Baru',
      subtitle: 'Buat wadah grup rombongan bayar baru untuk kolektor',
      summary:
          'Formulir pembuatan grup rombongan baru yang mencatat nama grup, keterangan, nama kolektor, serta nomor HP kolektor.',
      warningNote:
          'Pembuatan grup bersifat permanen di server. Pastikan data sudah benar sebelum menekan Lanjut, atau ketuk Kembali Ke Group untuk membatalkan.',
      icon: Icons.group_add_rounded,
      imageAsset: 'assets/guide/14_tambah_group.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Kolom Nama Group',
          description:
              'Masukkan nama identifikasi grup rombongan (contoh: nama kadus/kolektor dan nomor urutan grup).',
          dotPos: Offset(145, 652),
          targetPos: Offset(232, 652),
        ),
        GuidePin(
          number: 2,
          title: 'Kolom Keterangan',
          description:
              'Tambahkan catatan singkat mengenai wilayah RT/RW atau keterangan rombongan.',
          dotPos: Offset(145, 862),
          targetPos: Offset(232, 862),
        ),
        GuidePin(
          number: 3,
          title: 'Kolom Kolektor & No HP Kolektor',
          description:
              'Isi nama lengkap petugas kolektor penanggung jawab beserta nomor telepon aktifnya.',
          dotPos: Offset(145, 1072),
          targetPos: Offset(232, 1072),
        ),
        GuidePin(
          number: 4,
          title: 'Kecamatan & Kelurahan Otomatis',
          description:
              'Terisi secara otomatis mengikuti wilayah akun staf desa/kelurahan yang sedang login.',
          dotPos: Offset(145, 1432),
          targetPos: Offset(232, 1432),
        ),
        GuidePin(
          number: 5,
          title: 'Tombol Kembali Ke Group & Lanjut',
          description:
              'Ketuk "Kembali Ke Group" untuk membatalkan, atau ketuk "Lanjut" untuk menyimpan grup dan mulai menambahkan NOP anggota.',
          dotPos: Offset(145, 1815),
          targetPos: Offset(245, 1815),
        ),
      ],
    ),

    // =========================================================================
    // 4. PENGATURAN & PERSONALISASI
    // =========================================================================
    GuideTopic(
      id: 'pengaturan_utama',
      category: GuideCategory.pengaturan,
      chapterBadge: 'Bab 4.1',
      title: 'Menu Pengaturan Aplikasi',
      subtitle: 'Pusat pengaturan tema, keamanan, cadangan data & informasi aplikasi',
      summary:
          'Mengatur tampilan aplikasi, penguncian keamanan, pencadangan data DHKP, panduan penggunaan, serta informasi aplikasi dan pengembang.',
      icon: Icons.settings_outlined,
      imageAsset: 'assets/guide/15_pengaturan_utama.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Menu Tema & Tampilan',
          description:
              'Mengubah mode tampilan (Ikuti Sistem / Terang / Gelap) serta mengatur warna aplikasi.',
          dotPos: Offset(42, 385),
          targetPos: Offset(95, 385),
        ),
        GuidePin(
          number: 2,
          title: 'Menu Keamanan Aplikasi',
          description:
              'Mengaktifkan kunci pengaman Sidik Jari, PIN, atau Kata Sandi saat membuka aplikasi.',
          dotPos: Offset(42, 665),
          targetPos: Offset(95, 665),
        ),
        GuidePin(
          number: 3,
          title: 'Menu Pencadangan Data',
          description:
              'Menyimpan cadangan catatan DHKP ke penyimpanan ponsel maupun Google Drive.',
          dotPos: Offset(42, 960),
          targetPos: Offset(95, 960),
        ),
        GuidePin(
          number: 4,
          title: 'Menu Panduan Penggunaan Aplikasi',
          description:
              'Membuka Buku Panduan & Pusat Bantuan interaktif serta mengatur ulang tur panduan layar.',
          dotPos: Offset(42, 1255),
          targetPos: Offset(95, 1255),
        ),
        GuidePin(
          number: 5,
          title: 'Menu Tentang & Bagikan Aplikasi',
          description:
              'Membagikan file APK, melihat profil pengembang, membuka tautan GitHub & Saweria, serta memeriksa pembaruan.',
          dotPos: Offset(42, 1550),
          targetPos: Offset(95, 1550),
        ),
        GuidePin(
          number: 6,
          title: 'Kebijakan Privasi & Syarat Ketentuan',
          description:
              'Membaca dokumen resmi perlindungan data privasi dan ketentuan penggunaan aplikasi.',
          dotPos: Offset(42, 1890),
          targetPos: Offset(95, 1890),
        ),
      ],
    ),
    GuideTopic(
      id: 'pengaturan_tema',
      category: GuideCategory.pengaturan,
      chapterBadge: 'Bab 4.2',
      title: 'Tema & Tampilan Aplikasi',
      subtitle: 'Atur mode Terang/Gelap, warna wallpaper, dan kustomisasi warna RGB',
      summary:
          'Sesuaikan kenyamanan mata saat bertugas di lapangan maupun malam hari dengan mode tema dan pilihan warna aksen aplikasi.',
      icon: Icons.palette_outlined,
      imageAsset: 'assets/guide/16_pengaturan_tema.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Pilihan Mode Tema (Tampilan Layar)',
          description:
              'Pilih antara Ikuti Sistem, Mode Terang (jelas di bawah sinar matahari), atau Mode Gelap (nyaman di malam hari).',
          dotPos: Offset(42, 545),
          targetPos: Offset(95, 545),
        ),
        GuidePin(
          number: 2,
          title: 'Sakelar Ikuti Warna Wallpaper',
          description:
              'Menyesuaikan warna aplikasi secara otomatis mengikuti palet warna gambar latar (wallpaper) ponsel Anda.',
          dotPos: Offset(760, 865),
          targetPos: Offset(835, 915),
        ),
        GuidePin(
          number: 3,
          title: 'Palet Pilihan Warna Cepat',
          description:
              'Pilih warna tema aplikasi secara instan dari 8 warna pilihan yang tersedia.',
          dotPos: Offset(42, 1200),
          targetPos: Offset(95, 1200),
        ),
        GuidePin(
          number: 4,
          title: 'Slider Atur Warna Sendiri (RGB)',
          description:
              'Geser pengatur Merah, Hijau, dan Biru untuk meracik warna khusus sesuai keinginan Anda.',
          dotPos: Offset(42, 1730),
          targetPos: Offset(95, 1730),
        ),
      ],
    ),
    GuideTopic(
      id: 'pengaturan_keamanan',
      category: GuideCategory.pengaturan,
      chapterBadge: 'Bab 4.3',
      title: 'Keamanan & Kunci Aplikasi',
      subtitle: 'Lindungi data pajak warga dengan Sidik Jari, PIN, atau Sandi',
      summary:
          'Mencegah akses tanpa izin ke catatan DHKP dan fitur aplikasi dengan mengaktifkan penguncian layar saat aplikasi dibuka.',
      icon: Icons.lock_outline_rounded,
      imageAsset: 'assets/guide/17_pengaturan_keamanan.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Sakelar Kunci Pengaman Aplikasi',
          description:
              'Aktifkan sakelar ini untuk memilih metode penguncian: Kunci Perangkat (Sidik Jari / Wajah / Pola HP), PIN 6 Angka, atau Kata Sandi.',
          dotPos: Offset(760, 540),
          targetPos: Offset(835, 595),
        ),
      ],
    ),
    GuideTopic(
      id: 'pengaturan_pencadangan',
      category: GuideCategory.pengaturan,
      chapterBadge: 'Bab 4.4',
      title: 'Pencadangan & Pemulihan Data',
      subtitle: 'Simpan cadangan DHKP otomatis ke memori HP atau Google Drive',
      summary:
          'Menjaga agar seluruh catatan pembayaran dan dokumentasi DHKP tetap aman meskipun Anda berganti perangkat ponsel.',
      icon: Icons.cloud_sync_outlined,
      imageAsset: 'assets/guide/18_pengaturan_pencadangan.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tombol Cadangkan Sekarang',
          description:
              'Membuat salinan cadangan data perubahan DHKP secara langsung saat itu juga.',
          dotPos: Offset(55, 860),
          targetPos: Offset(125, 860),
        ),
        GuidePin(
          number: 2,
          title: 'Tombol Pulihkan / Muat Berkas DHKP',
          description:
              'Memulihkan catatan DHKP dari berkas cadangan yang pernah disimpan di HP atau Google Drive.',
          dotPos: Offset(55, 1010),
          targetPos: Offset(125, 1010),
        ),
        GuidePin(
          number: 3,
          title: 'Jadwal Cadangkan Otomatis',
          description:
              'Atur frekuensi pencadangan otomatis (misalnya Harian setiap pukul 02.00 pagi).',
          dotPos: Offset(42, 1325),
          targetPos: Offset(95, 1325),
        ),
        GuidePin(
          number: 4,
          title: 'Sakelar Hanya Data DHKP Saja',
          description:
              'Jika aktif, cadangan hanya menyimpan tabel data tanpa foto dokumentasi agar ukuran berkas lebih hemat.',
          dotPos: Offset(42, 1530),
          targetPos: Offset(95, 1530),
        ),
        GuidePin(
          number: 5,
          title: 'Pilihan Jaringan (Cadangkan Lewat)',
          description:
              'Pilih apakah pencadangan otomatis berjalan hanya saat terhubung Wi-Fi atau boleh menggunakan kuota seluler.',
          dotPos: Offset(42, 1735),
          targetPos: Offset(95, 1735),
        ),
        GuidePin(
          number: 6,
          title: 'Akun Google (Google Drive)',
          description:
              'Hubungkan akun Google Anda untuk menyimpan cadangan secara otomatis di folder "Cek PBB Cianjur" pada Google Drive.',
          dotPos: Offset(42, 2020),
          targetPos: Offset(95, 2020),
        ),
      ],
    ),
    GuideTopic(
      id: 'pengaturan_tentang',
      category: GuideCategory.pengaturan,
      chapterBadge: 'Bab 4.5',
      title: 'Tentang & Bagikan Aplikasi',
      subtitle: 'Bagikan file APK, profil pengembang, GitHub, Saweria & pembaruan',
      summary:
          'Memuat informasi versi aplikasi, tombol berbagi file instalasi APK ke sesama perangkat desa, profil pengembang Ikbal (@IkbalGumilar), tautan GitHub & Saweria, serta pemeriksa pembaruan.',
      icon: Icons.info_outline_rounded,
      imageAsset: 'assets/guide/20_pengaturan_tentang.webp',
      pins: [
        GuidePin(
          number: 1,
          title: 'Tombol Bagikan File Aplikasi',
          description:
              'Kirim file instalasi aplikasi (.apk) langsung ke rekan kolektor atau warga lewat WhatsApp, Bluetooth, atau Quick Share tanpa kuota unduh ulang.',
          dotPos: Offset(42, 911),
          targetPos: Offset(102, 911),
        ),
        GuidePin(
          number: 2,
          title: 'Profil Pengembang (Ikbal • @IkbalGumilar)',
          description:
              'Menampilkan foto profil, nama pengembang (Ikbal), handle (@IkbalGumilar), dan bio singkat pengembang aplikasi.',
          dotPos: Offset(650, 1265),
          targetPos: Offset(420, 1265),
        ),
        GuidePin(
          number: 3,
          title: 'Tombol Tautan GitHub',
          description:
              'Membuka halaman profil dan repositori GitHub resmi pengembang (@IkbalGumilar) untuk melihat informasi kode sumber dan rilis proyek.',
          dotPos: Offset(42, 1478),
          targetPos: Offset(93, 1478),
        ),
        GuidePin(
          number: 4,
          title: 'Tombol Tautan Saweria',
          description:
              'Membuka halaman Saweria resmi pengembang bagi pengguna yang ingin memberikan apresiasi atau dukungan donasi sukarela.',
          dotPos: Offset(1038, 1478),
          targetPos: Offset(988, 1478),
        ),
        GuidePin(
          number: 5,
          title: 'Menu Periksa Pembaruan',
          description:
              'Mengecek secara langsung apakah tersedia rilis versi aplikasi Cek PBB Cianjur yang lebih baru.',
          dotPos: Offset(42, 1756),
          targetPos: Offset(93, 1756),
        ),
        GuidePin(
          number: 6,
          title: 'Menu Kebijakan Privasi',
          description:
              'Membuka dokumen resmi mengenai keamanan data lokal dan perlindungan privasi pengguna.',
          dotPos: Offset(42, 1947),
          targetPos: Offset(93, 1947),
        ),
        GuidePin(
          number: 7,
          title: 'Menu Syarat & Ketentuan',
          description:
              'Membuka dokumen ketentuan penggunaan aplikasi secara lengkap.',
          dotPos: Offset(42, 2139),
          targetPos: Offset(93, 2139),
        ),
      ],
    ),
  ];

  static const List<GuideFaqItem> faqs = [
    GuideFaqItem(
      question:
          'Mengapa saat mengecek tagihan muncul pesan "Kode Verifikasi Salah"?',
      answer:
          'Pastikan huruf atau angka yang diketik pada kolom Kode Verifikasi sama persis dengan gambar Captcha yang tampil. Bila gambar kurang jelas, ketuk tombol "Ganti Kode Gambar" terlebih dahulu.',
      icon: Icons.password_rounded,
      category: GuideCategory.publik,
    ),
    GuideFaqItem(
      question:
          'Bagaimana cara mengetik Blok dan Nomor Wilayah yang memiliki angka nol di depan?',
      answer:
          'Cukup ketik angkanya saja tanpa angka nol di depan. Contohnya: jika di SPPT tertulis Blok 002 dan Nomor 0085, cukup ketik Blok 2 dan Nomor 85.',
      icon: Icons.pin_outlined,
      category: GuideCategory.publik,
    ),
    GuideFaqItem(
      question:
          'Bagaimana cara membagikan aplikasi ini ke HP kolektor atau perangkat desa lain?',
      answer:
          'Buka menu Pengaturan > Tentang & Bagikan Aplikasi, lalu ketuk tombol hijau "Bagikan File Aplikasi". Anda bisa langsung mengirim file APK lewat WhatsApp, Bluetooth, atau Quick Share.',
      icon: Icons.share_rounded,
      category: GuideCategory.pengaturan,
    ),
    GuideFaqItem(
      question:
          'Apakah catatan pembayaran DHKP saya aman jika berganti HP baru?',
      answer:
          'Sangat aman. Buka menu Pengaturan > Pencadangan Data, hubungkan Akun Google (Google Drive), lalu ketuk "Cadangkan Sekarang". Di HP baru, cukup pilih "Pulihkan / Muat Berkas DHKP".',
      icon: Icons.cloud_done_outlined,
      category: GuideCategory.dhkp,
    ),
    GuideFaqItem(
      question:
          'Apa yang harus diperhatikan sebelum membuat grup baru di Pembayaran Kolektif?',
      answer:
          'Pembuatan grup rombongan baru pada Portal Staf bersifat permanen di server. Pastikan Nama Group, Keterangan, dan Nama Kolektor sudah benar sebelum menekan tombol Lanjut.',
      icon: Icons.warning_amber_rounded,
      category: GuideCategory.staf,
    ),
    GuideFaqItem(
      question:
          'Bagaimana jika saya ingin menampilkan kembali popup tur petunjuk di setiap layar?',
      answer:
          'Anda dapat mengetuk tombol "Aktifkan Ulang Tur Layar" di bagian atas halaman Pusat Panduan ini, atau mengetuk ikon tanda tanya (?) di pojok kanan atas masing-masing halaman.',
      icon: Icons.help_outline_rounded,
      category: GuideCategory.pengaturan,
    ),
  ];
}
