import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum LegalDocumentType {
  privacyPolicy,
  termsOfService,
}

/// Layar terpadu untuk menampilkan Kebijakan Privasi dan Syarat & Ketentuan Layanan.
/// Dapat dibaca secara offline di dalam aplikasi dan dilengkapi tombol untuk membuka versi web resmi.
class LegalDocumentScreen extends StatefulWidget {
  final LegalDocumentType initialType;

  const LegalDocumentScreen({
    super.key,
    this.initialType = LegalDocumentType.privacyPolicy,
  });

  static const String privacyPolicyUrl =
      'https://ikbalgumilar.github.io/Cek-PBB-Cianjur/privacy.html';
  static const String termsOfServiceUrl =
      'https://ikbalgumilar.github.io/Cek-PBB-Cianjur/terms.html';
  static const String githubRepoUrl =
      'https://github.com/IkbalGumilar/Cek-PBB-Cianjur';

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialType == LegalDocumentType.privacyPolicy ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openWebUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak dapat membuka browser: $url')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka tautan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Informasi Hukum & Privasi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_outlined),
            tooltip: 'Buka Dokumen Resmi di Web',
            onPressed: () {
              final activeUrl = _tabController.index == 0
                  ? LegalDocumentScreen.privacyPolicyUrl
                  : LegalDocumentScreen.termsOfServiceUrl;
              _openWebUrl(activeUrl);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.privacy_tip_outlined),
              text: 'Kebijakan Privasi',
            ),
            Tab(
              icon: Icon(Icons.gavel_outlined),
              text: 'Syarat & Ketentuan',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrivacyPolicyView(isDark),
          _buildTermsOfServiceView(isDark),
        ],
      ),
    );
  }

  Widget _buildPrivacyPolicyView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderBadge(
                title: 'Kebijakan Privasi (Privacy Policy)',
                subtitle:
                    'Terakhir Diperbarui: 24 Oktober 2026 • Berlaku Efektif: 24 Oktober 2026',
                icon: Icons.shield_outlined,
                color: Colors.teal,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Selamat datang di Cek PBB Cianjur. Kebijakan Privasi ini menjelaskan bagaimana aplikasi kami mengumpulkan, menggunakan, menyimpan, dan melindungi informasi Anda saat menggunakan aplikasi Cek PBB Cianjur di perangkat Android dan Desktop.',
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aplikasi ini dirancang dengan prinsip arsitektur offline-first, di mana seluruh data operasional disimpan langsung di perangkat pengguna secara lokal tanpa perantara server komersial pihak ketiga.',
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('1. Informasi yang Diproses Aplikasi'),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildSubHeading('A. Data Pajak & Catatan Kolektor (Lokal)'),
                  const Text(
                    'Aplikasi memproses Nomor Objek Pajak (NOP), nama wajib pajak, alamat objek pajak, ketetapan tagihan, serta status pembayaran (lunas / titip bayar) dari berkas DHKP resmi desa atau portal publik PBB Bapenda Cianjur. Seluruh data ini disimpan di penyimpanan lokal perangkat dalam basis data terenkripsi dan TIDAK PERNAH dikirim ke server pihak ketiga mana pun.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const Divider(height: 24),
                  _buildSubHeading('B. Informasi Akun Google (Otentikasi Sukarela)'),
                  const Text(
                    'Jika Anda secara sukarela menautkan akun Google untuk sinkronisasi cadangan DHKP, aplikasi hanya menerima data profil dasar: alamat email, nama tampilan profil, dan URL foto profil. Data ini semata-mata digunakan untuk menampilkan identitas akun aktif dan memvalidasi kepemilikan cadangan data.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('2. Penggunaan Izin Google Drive (Least-Privilege)'),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildCalloutBox(
                    title: 'Prinsip Akses Minimum Terisolasi:',
                    body:
                        'Aplikasi HANYA meminta izin "drive.file" (akses terbatas per-berkas) dan "drive.appdata". Aplikasi DIBATASI SECARA SISTEM dan TIDAK MEMILIKI AKSES TEKNIS untuk membaca, mengunduh, melihat, atau memodifikasi dokumen, foto, atau folder pribadi lainnya di Google Drive Anda.',
                    color: Colors.green,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aplikasi hanya berinteraksi dengan:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  _buildBulletItem(
                    'Folder khusus bernama "Cek PBB Cianjur" yang dibuat di Google Drive Anda.',
                  ),
                  _buildBulletItem(
                    'Berkas paket cadangan DHKP (.dkhp atau .zip) yang dibuat oleh aplikasi ini sendiri.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('3. Kepatuhan Kebijakan Data Pengguna Google API'),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Penggunaan data dari Google APIs oleh Cek PBB Cianjur sepenuhnya mematuhi Google API Services User Data Policy, termasuk klausul Penggunaan Terbatas (Limited Use):',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  _buildBulletItem('TIDAK PERNAH menjual atau membagikan data ke pihak ketiga.'),
                  _buildBulletItem('TIDAK MENGGUNAKAN data untuk periklanan atau penargetan iklan.'),
                  _buildBulletItem('TIDAK ADA manusia yang membaca berkas cadangan Anda; seluruh proses transfer data dilakukan terenkripsi mesin.'),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('4. Keamanan Informasi & Enkripsi Berkas'),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildBulletItem(
                    'Enkripsi Berkas DHKP: Berkas cadangan yang diunggah dilindungi enkripsi standar industri AES-256 (CBC/GCM) dengan PBKDF2-HMAC-SHA256.',
                  ),
                  _buildBulletItem(
                    'Penyimpanan Kredensial Aman: Token Google OAuth disimpan dalam Android Keystore / Flutter Secure Storage.',
                  ),
                  _buildBulletItem(
                    'Kunci Biometrik: Dilengkapi fitur autentikasi sidik jari / wajah (Fingerprint / Face ID) bawaan perangkat.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('5. Kontrol Pengguna'),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildBulletItem(
                    'Anda dapat melepas tautan akun Google kapan saja via menu Pengaturan > Lepas Akun Google.',
                  ),
                  _buildBulletItem(
                    'Anda dapat mencabut izin aplikasi kapan saja melalui Google Account Permissions (myaccount.google.com/permissions).',
                  ),
                  _buildBulletItem(
                    'Anda dapat menghapus berkas cadangan langsung dari Google Drive Anda atau dari menu aplikasi.',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildWebButton(
                url: LegalDocumentScreen.privacyPolicyUrl,
                label: 'Buka Kebijakan Privasi Resmi di Web',
                icon: Icons.open_in_new,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsOfServiceView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeaderBadge(
                title: 'Syarat & Ketentuan Layanan',
                subtitle:
                    'Terms of Service • Terakhir Diperbarui: 24 Oktober 2026',
                icon: Icons.gavel_outlined,
                color: Colors.indigo,
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Dengan mengunduh, memasang, atau menggunakan aplikasi Cek PBB Cianjur, Anda menyatakan setuju untuk terikat oleh Syarat dan Ketentuan berikut. Jika Anda tidak menyetujui ketentuan ini, mohon untuk tidak menggunakan aplikasi ini.',
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('1. Deskripsi Layanan'),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Aplikasi Cek PBB Cianjur adalah perangkat lunak utilitas bantu yang ditujukan bagi kolektor pajak tingkat desa/kelurahan dan wajib pajak di wilayah Kabupaten Cianjur untuk memeriksa informasi tagihan PBB-P2, mengelola pembagian blok penagihan, serta mencetak tanda terima pembayaran sementara secara cepat dan offline-first.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('2. Penggunaan yang Diizinkan'),
              _buildCard(
                isDark: isDark,
                children: [
                  _buildBulletItem(
                    'Pengguna setuju untuk menggunakan aplikasi sesuai dengan peraturan perundang-undangan yang berlaku dan tujuan kedinasan/operasional yang sah.',
                  ),
                  _buildBulletItem(
                    'Dilarang menyalahgunakan Nomor Objek Pajak (NOP) atau data wajib pajak untuk tindakan yang melanggar hukum.',
                  ),
                  _buildBulletItem(
                    'Dilarang merekayasa balik (reverse engineer) atau merusak integritas keamanan aplikasi.',
                  ),
                  _buildBulletItem(
                    'Pengguna bertanggung jawab penuh menjaga kerahasiaan kata sandi enkripsi berkas DHKP dan keamanan perangkat masing-masing.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('3. Integrasi Cloud (Google Drive)'),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Fitur pencadangan Google Drive disediakan sebagai sarana pencadangan mandiri antarperangkat. Pengguna bertanggung jawab menjaga keamanan akun Google yang ditautkan. Penggunaan fitur ini tunduk pada Kebijakan Privasi serta Kebijakan Layanan Google API.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('4. Penafian Tanggung Jawab (Disclaimer)'),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Data tagihan PBB bersumber dari portal informasi resmi yang dapat diakses publik atau berkas DHKP desa. Pengembang berusaha memastikan keakuratan informasi, namun tidak bertanggung jawab atas keterlambatan sinkronisasi data dari pihak server instansi terkait atau kehilangan data akibat kelalaian perangkat fisik pengguna.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSectionTitle('5. Hubungi Pengembang & Repositori'),
              _buildCard(
                isDark: isDark,
                children: [
                  const Text(
                    'Proyek ini dikembangkan secara terbuka untuk mendukung efisiensi pelayanan pajak daerah.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const FaIcon(FontAwesomeIcons.github, size: 24),
                    title: const Text('IkbalGumilar/Cek-PBB-Cianjur'),
                    subtitle: const Text('github.com/IkbalGumilar/Cek-PBB-Cianjur'),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => _openWebUrl(LegalDocumentScreen.githubRepoUrl),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildWebButton(
                url: LegalDocumentScreen.termsOfServiceUrl,
                label: 'Buka Syarat & Ketentuan di Web',
                icon: Icons.open_in_new,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBadge({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.2),
            foregroundColor: color,
            radius: 24,
            child: Icon(icon, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildSubHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCard({
    required List<Widget> children,
    required bool isDark,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildBulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalloutBox({
    required String title,
    required String body,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildWebButton({
    required String url,
    required String label,
    required IconData icon,
  }) {
    return OutlinedButton.icon(
      onPressed: () => _openWebUrl(url),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
