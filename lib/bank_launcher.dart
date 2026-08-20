import 'dart:io';

import 'package:flutter/services.dart';

class BankApp {
  final String label;
  final String packageName;

  const BankApp(this.label, this.packageName);
}

/// Daftar kandidat aplikasi m-banking/e-wallet yang umum dipakai warga
/// Cianjur untuk bayar Virtual Account. Ini cuma kandidat — package name yang
/// salah/tidak terpasang otomatis tersaring di [installedApps], jadi aman
/// walau belum semua package name terverifikasi 100% akurat (butuh
/// pengecekan langsung di HP yang aplikasinya benar-benar terpasang).
const _candidateBankApps = [
  // Bank penerbit VA (BJB) diletakkan paling atas.
  BankApp('BJB DIGI', 'com.bjb.digi'),
  // Bank besar lain (untuk kanal VA antar bank / kode bank 910200).
  BankApp('BCA mobile', 'com.bca.mybca'),
  BankApp('BCA mobile (lama)', 'com.bca.bca'),
  BankApp('BRImo', 'id.co.bri.brimo'),
  BankApp('Livin\' by Mandiri', 'com.bankmandiri.livin'),
  BankApp('BNI Mobile Banking', 'src.co.bni.mobile'),
  BankApp('BSI Mobile', 'com.bsm.activity2'),
  BankApp('CIMB Niaga OCTO Mobile', 'com.cimbniaga.octomobile'),
  BankApp('Danamon D-Bank PRO', 'com.danamon.ib.mb'),
  BankApp('PermataMobile X', 'com.permatabank.mobile'),
  BankApp('SeaBank', 'com.seabank.mobile'),
  BankApp('Jenius', 'com.btpn.jenius'),
  BankApp('digibank by DBS', 'com.dbs.digibank'),
  BankApp('Bank Jago', 'com.jago.digitalBanking'),
  BankApp('Blu by BCA Digital', 'id.bluebca.mobile'),
  // E-wallet.
  BankApp('DANA', 'id.dana'),
  BankApp('GoPay', 'com.gojek.gopay'),
  BankApp('Gojek', 'com.gojek.app'),
  BankApp('OVO', 'com.ovo.mobile'),
  BankApp('ShopeePay (Shopee)', 'com.shopee.id'),
  BankApp('LinkAja', 'id.linkaja'),
  BankApp('i.saku', 'id.co.indomaret.isaku'),
];

class BankLauncher {
  static const _channel = MethodChannel('id.cianjur.cekpbb.cek_pbb_app/bank');

  /// Cek dari [_candidateBankApps] mana saja yang benar-benar terpasang di
  /// perangkat ini.
  static Future<List<BankApp>> installedApps() async {
    // Channel-nya cuma diimplementasikan di sisi Kotlin (Android); di
    // Windows/Linux tidak ada handler-nya sama sekali (VA hanya tersedia di
    // Android, lihat CheckFormView), jadi keluar duluan di sini.
    if (!Platform.isAndroid) return [];
    try {
      final packageNames = _candidateBankApps.map((a) => a.packageName).toList();
      final installed = await _channel.invokeMethod<List<Object?>>('checkInstalledApps', {
        'packageNames': packageNames,
      });
      final installedSet = (installed ?? []).map((e) => e.toString()).toSet();
      return _candidateBankApps.where((a) => installedSet.contains(a.packageName)).toList();
    } on PlatformException {
      return [];
    }
  }

  /// Buka aplikasi bank/e-wallet [app] ke layar utamanya. Tidak bisa mengisi
  /// otomatis nomor VA di dalam aplikasi pihak ketiga (tidak ada standar
  /// untuk itu) — nomor VA disalin manual lewat tombol "Salin Kode VA".
  static Future<bool> launch(BankApp app) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('launchApp', {'packageName': app.packageName});
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Ambil ikon asli aplikasi [packageName] langsung dari sistem (bukan aset
  /// logo yang dibundel sendiri), null kalau gagal.
  static Future<Uint8List?> getAppIcon(String packageName) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});
    } on PlatformException {
      return null;
    }
  }
}
