import 'dart:convert';
import 'dart:math' as math;
import '../currency_format.dart';

/// Hasil kalkulasi target capaian realisasi PBB.
class PbbTargetSimulationResult {
  final int totalKetetapan;
  final int realisasiSaatIni;
  final double targetPersen;
  final int targetNominal;
  final int kekuranganNominal;
  final double persenSaatIni;
  final int estimasiNopDibutuhkan;
  final bool targetSudahTercapai;
  final int kelebihanNominal;

  const PbbTargetSimulationResult({
    required this.totalKetetapan,
    required this.realisasiSaatIni,
    required this.targetPersen,
    required this.targetNominal,
    required this.kekuranganNominal,
    required this.persenSaatIni,
    required this.estimasiNopDibutuhkan,
    required this.targetSudahTercapai,
    required this.kelebihanNominal,
  });
}

/// Hasil kalkulasi kecepatan penagihan (pacing) menuju jatuh tempo.
class PbbPacingResult {
  final int sisaNominal;
  final int sisaHari;
  final int targetHarian;
  final int targetMingguan;
  final bool sudahLewatJatuhTempo;

  const PbbPacingResult({
    required this.sisaNominal,
    required this.sisaHari,
    required this.targetHarian,
    required this.targetMingguan,
    required this.sudahLewatJatuhTempo,
  });
}

/// Hasil kalkulasi denda keterlambatan PBB-P2.
class PbbDendaResult {
  final int pokokPbb;
  final DateTime jatuhTempo;
  final DateTime rencanaBayar;
  final double tarifBungaPerBulan;
  final int bulanKeterlambatan;
  final double totalPersenDenda;
  final int nominalDenda;
  final int totalBayar;
  final bool tepatWaktu;

  const PbbDendaResult({
    required this.pokokPbb,
    required this.jatuhTempo,
    required this.rencanaBayar,
    required this.tarifBungaPerBulan,
    required this.bulanKeterlambatan,
    required this.totalPersenDenda,
    required this.nominalDenda,
    required this.totalBayar,
    required this.tepatWaktu,
  });
}

/// Hasil kalkulasi rencana cicilan / tabungan PBB warga.
class PbbCicilanResult {
  final int totalTagihan;
  final String frekuensi; // 'Mingguan', 'Bulanan', 'Harian'
  final int jumlahKaliSetoran;
  final int nominalPerSetoran;

  const PbbCicilanResult({
    required this.totalTagihan,
    required this.frekuensi,
    required this.jumlahKaliSetoran,
    required this.nominalPerSetoran,
  });
}

/// Hasil kalkulasi Akta Jual Beli (AJB) & Simulasi NJOP.
/// Rumus:
///   total = njop * luas
///   pph = total * 2.5%
///   ppn = total * 2.5%
///   jika total >= 80.000.000 maka bphtb = total * 5%
class PbbAjbSimulationResult {
  final double luas;
  final int njopPerM2;
  final int totalNilai;
  final int pph;
  final int ppn;
  final bool kenaBphtb;
  final int bphtb;
  final int totalBiayaPajak;

  const PbbAjbSimulationResult({
    required this.luas,
    required this.njopPerM2,
    required this.totalNilai,
    required this.pph,
    required this.ppn,
    required this.kenaBphtb,
    required this.bphtb,
    required this.totalBiayaPajak,
  });
}

/// Kumpulan fungsi perhitungan murni PBB-P2 & AJB.
class PbbCalculatorHelper {
  PbbCalculatorHelper._();

  /// Batas nilai minimal transaksi yang dikenakan BPHTB (80 Juta).
  static const int batasMinimalBphtb = 80000000;

  /// Menghitung simulasi target capaian.
  static PbbTargetSimulationResult calculateTarget({
    required int totalKetetapan,
    required int realisasiSaatIni,
    required double targetPersen,
    int rataRataNominalPerNop = 50000,
  }) {
    if (totalKetetapan <= 0) {
      return const PbbTargetSimulationResult(
        totalKetetapan: 0,
        realisasiSaatIni: 0,
        targetPersen: 0,
        targetNominal: 0,
        kekuranganNominal: 0,
        persenSaatIni: 0,
        estimasiNopDibutuhkan: 0,
        targetSudahTercapai: true,
        kelebihanNominal: 0,
      );
    }

    final targetNominal = (totalKetetapan * (targetPersen / 100)).round();
    final persenSaatIni = (realisasiSaatIni / totalKetetapan) * 100;
    final sudahTercapai = realisasiSaatIni >= targetNominal;
    final kekurangan = sudahTercapai ? 0 : (targetNominal - realisasiSaatIni);
    final kelebihan = sudahTercapai ? (realisasiSaatIni - targetNominal) : 0;

    final effectiveRata = rataRataNominalPerNop > 0 ? rataRataNominalPerNop : 50000;
    final estimasiNop = kekurangan > 0 ? (kekurangan / effectiveRata).ceil() : 0;

    return PbbTargetSimulationResult(
      totalKetetapan: totalKetetapan,
      realisasiSaatIni: realisasiSaatIni,
      targetPersen: targetPersen,
      targetNominal: targetNominal,
      kekuranganNominal: kekurangan,
      persenSaatIni: persenSaatIni,
      estimasiNopDibutuhkan: estimasiNop,
      targetSudahTercapai: sudahTercapai,
      kelebihanNominal: kelebihan,
    );
  }

  /// Menghitung pacing kecepatan harian dan mingguan menuju jatuh tempo.
  static PbbPacingResult calculatePacing({
    required int sisaNominal,
    required DateTime jatuhTempo,
    DateTime? tanggalMulai,
  }) {
    final start = tanggalMulai ?? DateTime.now();
    final d1 = DateTime(start.year, start.month, start.day);
    final d2 = DateTime(jatuhTempo.year, jatuhTempo.month, jatuhTempo.day);
    final sisaHari = d2.difference(d1).inDays;

    if (sisaHari <= 0) {
      return PbbPacingResult(
        sisaNominal: sisaNominal,
        sisaHari: sisaHari,
        targetHarian: sisaNominal,
        targetMingguan: sisaNominal,
        sudahLewatJatuhTempo: true,
      );
    }

    final harian = (sisaNominal / sisaHari).ceil();
    final mingguan = harian * 7;

    return PbbPacingResult(
      sisaNominal: sisaNominal,
      sisaHari: sisaHari,
      targetHarian: harian,
      targetMingguan: mingguan,
      sudahLewatJatuhTempo: false,
    );
  }

  /// Menghitung denda keterlambatan PBB-P2.
  /// 1% per bulan (UU HKPD No. 1/2022) atau 2% per bulan (aturan lama/Perda), maksimal 24 bulan.
  static PbbDendaResult calculateDenda({
    required int pokokPbb,
    required DateTime jatuhTempo,
    required DateTime rencanaBayar,
    double tarifBungaPerBulan = 1.0,
    int maxBulan = 24,
  }) {
    final tglJatuhTempo = DateTime(jatuhTempo.year, jatuhTempo.month, jatuhTempo.day);
    final tglBayar = DateTime(rencanaBayar.year, rencanaBayar.month, rencanaBayar.day);

    if (!tglBayar.isAfter(tglJatuhTempo)) {
      return PbbDendaResult(
        pokokPbb: pokokPbb,
        jatuhTempo: jatuhTempo,
        rencanaBayar: rencanaBayar,
        tarifBungaPerBulan: tarifBungaPerBulan,
        bulanKeterlambatan: 0,
        totalPersenDenda: 0.0,
        nominalDenda: 0,
        totalBayar: pokokPbb,
        tepatWaktu: true,
      );
    }

    var months = (tglBayar.year - tglJatuhTempo.year) * 12 + (tglBayar.month - tglJatuhTempo.month);
    if (tglBayar.day > tglJatuhTempo.day) {
      months += 1;
    }
    if (months <= 0) {
      months = 1;
    }

    final bulanTerhitung = math.min(months, maxBulan);
    final totalPersen = bulanTerhitung * tarifBungaPerBulan;
    final nominalDenda = (pokokPbb * (totalPersen / 100)).round();

    return PbbDendaResult(
      pokokPbb: pokokPbb,
      jatuhTempo: jatuhTempo,
      rencanaBayar: rencanaBayar,
      tarifBungaPerBulan: tarifBungaPerBulan,
      bulanKeterlambatan: bulanTerhitung,
      totalPersenDenda: totalPersen,
      nominalDenda: nominalDenda,
      totalBayar: pokokPbb + nominalDenda,
      tepatWaktu: false,
    );
  }

  /// Menghitung simulasi cicilan / tabungan warga.
  static PbbCicilanResult calculateCicilan({
    required int totalTagihan,
    required String frekuensi, // 'Mingguan', 'Bulanan', 'Harian'
    required int durasiBulan,
  }) {
    final effectiveDurasi = math.max(1, durasiBulan);
    int kaliSetoran = effectiveDurasi;

    if (frekuensi == 'Harian') {
      kaliSetoran = effectiveDurasi * 30;
    } else if (frekuensi == 'Mingguan') {
      kaliSetoran = effectiveDurasi * 4;
    } else {
      kaliSetoran = effectiveDurasi;
    }

    kaliSetoran = math.max(1, kaliSetoran);
    final nominalPerSetoran = (totalTagihan / kaliSetoran).ceil();

    return PbbCicilanResult(
      totalTagihan: totalTagihan,
      frekuensi: frekuensi,
      jumlahKaliSetoran: kaliSetoran,
      nominalPerSetoran: nominalPerSetoran,
    );
  }

  /// Menghitung simulasi Akta Jual Beli (AJB) & Pajak Transaksi.
  /// Rumus:
  ///   totalNilai = luas * njopPerM2
  ///   pph = totalNilai * 2.5%
  ///   ppn = totalNilai * 2.5%
  ///   bphtb = (totalNilai >= 80.000.000) ? totalNilai * 5% : 0
  static PbbAjbSimulationResult calculateAjb({
    required double luas,
    required int njopPerM2,
  }) {
    final totalNilai = (luas * njopPerM2).round();
    final pph = (totalNilai * 0.025).round();
    final ppn = (totalNilai * 0.025).round();
    final kenaBphtb = totalNilai >= batasMinimalBphtb;
    final bphtb = kenaBphtb ? (totalNilai * 0.05).round() : 0;
    final totalBiayaPajak = pph + ppn + bphtb;

    return PbbAjbSimulationResult(
      luas: luas,
      njopPerM2: njopPerM2,
      totalNilai: totalNilai,
      pph: pph,
      ppn: ppn,
      kenaBphtb: kenaBphtb,
      bphtb: bphtb,
      totalBiayaPajak: totalBiayaPajak,
    );
  }

  /// Format teks WhatsApp untuk Target & Pacing.
  static String formatWhatsAppTarget({
    required String namaWilayah,
    required PbbTargetSimulationResult targetResult,
    PbbPacingResult? pacingResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📢 *INFO TARGET CAPAIAN PBB-P2*');
    if (namaWilayah.isNotEmpty) {
      buffer.writeln('📍 *Wilayah:* $namaWilayah');
    }
    buffer.writeln('-----------------------------------');
    buffer.writeln('• *Pagu Ketetapan:* ${formatRupiah(targetResult.totalKetetapan)}');
    buffer.writeln('• *Realisasi Terkini:* ${formatRupiah(targetResult.realisasiSaatIni)} (${targetResult.persenSaatIni.toStringAsFixed(1)}%)');
    buffer.writeln('• *Target Sasaran:* ${targetResult.targetPersen.toStringAsFixed(0)}% (${formatRupiah(targetResult.targetNominal)})');

    if (targetResult.targetSudahTercapai) {
      buffer.writeln('🎉 *Status:* Target sudah tercapai! (Surplus ${formatRupiah(targetResult.kelebihanNominal)})');
    } else {
      buffer.writeln('⚠️ *Kekurangan Target:* ${formatRupiah(targetResult.kekuranganNominal)}');
      buffer.writeln('📋 *Estimasi Kebutuhan:* ~${targetResult.estimasiNopDibutuhkan} NOP');
    }

    if (pacingResult != null && !targetResult.targetSudahTercapai) {
      buffer.writeln('-----------------------------------');
      if (pacingResult.sudahLewatJatuhTempo) {
        buffer.writeln('⏳ *Catatan:* Waktu jatuh tempo telah terlewati.');
      } else {
        buffer.writeln('⏳ *Sisa Waktu:* ${pacingResult.sisaHari} Hari menuju Jatuh Tempo');
        buffer.writeln('🚀 *Kecepatan Penagihan:*');
        buffer.writeln('   - Target Harian: ${formatRupiah(pacingResult.targetHarian)}/hari');
        buffer.writeln('   - Target Mingguan: ${formatRupiah(pacingResult.targetMingguan)}/minggu');
      }
    }

    buffer.writeln('-----------------------------------');
    buffer.writeln('Semangat terus rekan-rekan petugas & kolektor! 💪🇮🇩');
    return buffer.toString();
  }

  /// Format teks WhatsApp untuk Simulasi Denda & Pembayaran.
  static String formatWhatsAppDenda({
    required String nop,
    required String namaWp,
    required PbbDendaResult dendaResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🧾 *INFORMASI KETETAPAN & DENDA PBB-P2*');
    if (nop.isNotEmpty) buffer.writeln('• *NOP:* $nop');
    if (namaWp.isNotEmpty) buffer.writeln('• *Nama WP:* $namaWp');
    buffer.writeln('• *Pokok Pajak:* ${formatRupiah(dendaResult.pokokPbb)}');
    buffer.writeln('• *Tgl Jatuh Tempo:* ${dendaResult.jatuhTempo.day}-${dendaResult.jatuhTempo.month}-${dendaResult.jatuhTempo.year}');
    buffer.writeln('• *Rencana Bayar:* ${dendaResult.rencanaBayar.day}-${dendaResult.rencanaBayar.month}-${dendaResult.rencanaBayar.year}');

    if (dendaResult.tepatWaktu) {
      buffer.writeln('✅ *Status:* Tepat Waktu (Bebas Denda)');
      buffer.writeln('💰 *Total Bayar:* ${formatRupiah(dendaResult.pokokPbb)}');
    } else {
      buffer.writeln('⚠️ *Keterlambatan:* ${dendaResult.bulanKeterlambatan} Bulan (${dendaResult.totalPersenDenda.toStringAsFixed(1)}%)');
      buffer.writeln('💸 *Nominal Sanksi Denda:* ${formatRupiah(dendaResult.nominalDenda)}');
      buffer.writeln('💰 *Total yang Harus Dibayar:* ${formatRupiah(dendaResult.totalBayar)}');
    }

    buffer.writeln('-----------------------------------');
    buffer.writeln('*(Estimasi berdasarkan regulasi tarif bunga PBB-P2 Pemda Cianjur)*');
    return buffer.toString();
  }

  /// Format teks WhatsApp untuk Skema Cicilan Warga.
  static String formatWhatsAppCicilan({
    required String nop,
    required String namaWp,
    required PbbCicilanResult cicilanResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('💳 *SKEMA TABUNGAN / CICILAN PBB-P2*');
    if (nop.isNotEmpty) buffer.writeln('• *NOP:* $nop');
    if (namaWp.isNotEmpty) buffer.writeln('• *Nama WP:* $namaWp');
    buffer.writeln('• *Total Ketetapan:* ${formatRupiah(cicilanResult.totalTagihan)}');
    buffer.writeln('• *Frekuensi Setoran:* ${cicilanResult.frekuensi}');
    buffer.writeln('• *Jumlah Setoran:* ${cicilanResult.jumlahKaliSetoran}x Kali');
    buffer.writeln('• *Besaran per Setoran:* ${formatRupiah(cicilanResult.nominalPerSetoran)}');
    buffer.writeln('-----------------------------------');
    buffer.writeln('Dengan menabung secara rutin, pembayaran PBB menjadi ringan sebelum jatuh tempo. Terima kasih! 🙏');
    return buffer.toString();
  }

  /// Format teks WhatsApp untuk Simulasi AJB & Pajak Transaksi.
  static String formatWhatsAppAjb({
    String? nop,
    String? namaWp,
    required PbbAjbSimulationResult ajbResult,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📑 *SIMULASI BIAYA AKTA JUAL BELI (AJB) & PAJAK*');
    if (nop != null && nop.isNotEmpty) buffer.writeln('• *NOP:* $nop');
    if (namaWp != null && namaWp.isNotEmpty) buffer.writeln('• *Nama Pemilik/WP:* $namaWp');
    buffer.writeln('• *Luas Tanah:* ${ajbResult.luas.toStringAsFixed(0)} m²');
    buffer.writeln('• *NJOP / m²:* ${formatRupiah(ajbResult.njopPerM2)}');
    buffer.writeln('• *Total Nilai Transaksi / NJOP:* ${formatRupiah(ajbResult.totalNilai)}');
    buffer.writeln('-----------------------------------');
    buffer.writeln('📋 *Rincian Estimasi Pajak:*');
    buffer.writeln('• PPh (2.5%): ${formatRupiah(ajbResult.pph)}');
    buffer.writeln('• PPN (2.5%): ${formatRupiah(ajbResult.ppn)}');
    if (ajbResult.kenaBphtb) {
      buffer.writeln('• BPHTB (5% - Transaksi >= 80 Juta): ${formatRupiah(ajbResult.bphtb)}');
    } else {
      buffer.writeln('• BPHTB: Rp 0 (Nilai transaksi di bawah 80 Juta)');
    }
    buffer.writeln('-----------------------------------');
    buffer.writeln('💰 *Total Estimasi Pajak Transaksi:* ${formatRupiah(ajbResult.totalBiayaPajak)}');
    return buffer.toString();
  }
}

/// Satu riwayat transaksi setoran (+) atau penarikan (-) tabungan PBB warga.
class PbbTabunganMutasi {
  final int nominal; // positif untuk setor (+), negatif untuk tarik (-)
  final String tanggal; // e.g. "09/11/2026 19:30"
  final String keterangan; // e.g. "Setor cicilan ke-1", "Tarik kebutuhan mendesak"

  const PbbTabunganMutasi({
    required this.nominal,
    required this.tanggal,
    this.keterangan = '',
  });

  bool get isSetor => nominal >= 0;

  Map<String, dynamic> toJson() => {
        'n': nominal,
        't': tanggal,
        if (keterangan.isNotEmpty) 'k': keterangan,
      };

  factory PbbTabunganMutasi.fromJson(Map<String, dynamic> json) =>
      PbbTabunganMutasi(
        nominal: json['n'] as int? ?? 0,
        tanggal: json['t'] as String? ?? '',
        keterangan: json['k'] as String? ?? '',
      );
}

/// Model data tabungan / cicilan warga untuk satu objek pajak (NOP).
class PbbTabunganModel {
  final int saldo;
  final int target; // Pokok PBB yang harus dikumpulkan
  final String catatan; // Catatan khusus cicilan / kesepakatan warga
  final List<PbbTabunganMutasi> riwayat;

  const PbbTabunganModel({
    this.saldo = 0,
    this.target = 0,
    this.catatan = '',
    this.riwayat = const [],
  });

  bool get hasTabungan => saldo > 0 || catatan.isNotEmpty || riwayat.isNotEmpty;
  bool get isLunas => target > 0 && saldo >= target;
  int get sisaKekurangan => (target - saldo).clamp(0, target);
  double get persentase =>
      target > 0 ? ((saldo / target) * 100).clamp(0.0, 100.0) : 0.0;

  PbbTabunganModel copyWith({
    int? saldo,
    int? target,
    String? catatan,
    List<PbbTabunganMutasi>? riwayat,
  }) {
    return PbbTabunganModel(
      saldo: saldo ?? this.saldo,
      target: target ?? this.target,
      catatan: catatan ?? this.catatan,
      riwayat: riwayat ?? this.riwayat,
    );
  }

  PbbTabunganModel setor(int nominal, {PbbTabunganMutasi? mutasi}) {
    final newSaldo = saldo + nominal;
    final newRiwayat = List<PbbTabunganMutasi>.from(riwayat);
    if (mutasi != null) {
      newRiwayat.add(mutasi);
    }
    return copyWith(saldo: newSaldo, riwayat: newRiwayat);
  }

  PbbTabunganModel tarik(int nominal, {PbbTabunganMutasi? mutasi}) {
    final newSaldo = (saldo - nominal).clamp(0, saldo);
    final newRiwayat = List<PbbTabunganMutasi>.from(riwayat);
    if (mutasi != null) {
      newRiwayat.add(mutasi);
    }
    return copyWith(saldo: newSaldo, riwayat: newRiwayat);
  }

  Map<String, dynamic> toJson() => {
        'saldo': saldo,
        'target': target,
        'catatan': catatan,
        'riwayat': riwayat.map((e) => e.toJson()).toList(),
      };

  factory PbbTabunganModel.fromJson(Map<String, dynamic> json) {
    return PbbTabunganModel(
      saldo: json['saldo'] as int? ?? 0,
      target: json['target'] as int? ?? 0,
      catatan: json['catatan'] as String? ?? '',
      riwayat: (json['riwayat'] as List<dynamic>?)
              ?.map((e) =>
                  PbbTabunganMutasi.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

/// Helper untuk ekstraksi dan serialisasi data tabungan di dalam field catatan BlokRecord.
class PbbTabunganHelper {
  PbbTabunganHelper._();

  static const String _tagPrefix = '[TABUNGAN_PBB:';
  static const String _tagSuffix = ':/TABUNGAN_PBB]';

  /// Membersihkan tag tabungan dari teks catatan agar hanya menyisakan catatan teks manusia.
  static String cleanCatatan(String rawCatatan) {
    final startIdx = rawCatatan.indexOf(_tagPrefix);
    if (startIdx == -1) return rawCatatan.trim();
    final endIdx = rawCatatan.indexOf(_tagSuffix, startIdx);
    if (endIdx == -1) {
      return rawCatatan.substring(0, startIdx).trim();
    }
    final before = rawCatatan.substring(0, startIdx).trim();
    final after = rawCatatan.substring(endIdx + _tagSuffix.length).trim();
    if (before.isEmpty) return after;
    if (after.isEmpty) return before;
    return '$before\n$after'.trim();
  }

  /// Mengekstrak objek [PbbTabunganModel] dari dalam field catatan.
  static PbbTabunganModel extractTabungan(String rawCatatan,
      {int defaultTarget = 0}) {
    final startIdx = rawCatatan.indexOf(_tagPrefix);
    if (startIdx == -1) {
      return PbbTabunganModel(target: defaultTarget);
    }
    final endIdx = rawCatatan.indexOf(_tagSuffix, startIdx);
    if (endIdx == -1) {
      return PbbTabunganModel(target: defaultTarget);
    }
    final jsonStr = rawCatatan.substring(startIdx + _tagPrefix.length, endIdx);
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final model = PbbTabunganModel.fromJson(decoded);
      if (model.target <= 0 && defaultTarget > 0) {
        return model.copyWith(target: defaultTarget);
      }
      return model;
    } catch (_) {
      return PbbTabunganModel(target: defaultTarget);
    }
  }

  /// Menggabungkan catatan manusia dengan data tabungan terstruktur.
  static String encodeCatatanWithTabungan(
      String humanCatatan, PbbTabunganModel tabungan) {
    final cleanHuman = cleanCatatan(humanCatatan);
    if (!tabungan.hasTabungan) {
      return cleanHuman;
    }
    final jsonStr = jsonEncode(tabungan.toJson());
    final tag = '$_tagPrefix$jsonStr$_tagSuffix';
    if (cleanHuman.isEmpty) {
      return tag;
    }
    return '$cleanHuman\n$tag';
  }

  /// Format teks WhatsApp untuk bukti tabungan/cicilan warga.
  static String formatWhatsAppTabungan({
    required String nop,
    required String namaWp,
    required PbbTabunganModel tabungan,
    PbbTabunganMutasi? transaksiTerakhir,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🐷 *BUKTI TABUNGAN / CICILAN PBB-P2*');
    if (nop.isNotEmpty) buffer.writeln('• *NOP:* $nop');
    if (namaWp.isNotEmpty) buffer.writeln('• *Nama WP:* $namaWp');
    buffer.writeln('• *Target Ketetapan PBB:* ${formatRupiah(tabungan.target)}');
    buffer.writeln('• *Saldo Terkumpul:* ${formatRupiah(tabungan.saldo)} (${tabungan.persentase.toStringAsFixed(0)}%)');
    if (tabungan.isLunas) {
      buffer.writeln('• *Status:* ✅ *LUNAS / SIAP BAYAR*');
    } else {
      buffer.writeln('• *Sisa Kekurangan:* ${formatRupiah(tabungan.sisaKekurangan)}');
    }
    if (tabungan.catatan.isNotEmpty) {
      buffer.writeln('• *Catatan Warga:* ${tabungan.catatan}');
    }
    if (transaksiTerakhir != null) {
      buffer.writeln('-----------------------------------');
      final jenis = transaksiTerakhir.isSetor ? 'Setoran (+)' : 'Penarikan (-)';
      buffer.writeln('📋 *Mutasi Terakhir:*');
      buffer.writeln('• Jenis: $jenis ${formatRupiah(transaksiTerakhir.nominal.abs())}');
      buffer.writeln('• Waktu: ${transaksiTerakhir.tanggal}');
      if (transaksiTerakhir.keterangan.isNotEmpty) {
        buffer.writeln('• Info: ${transaksiTerakhir.keterangan}');
      }
    }
    buffer.writeln('-----------------------------------');
    if (tabungan.isLunas) {
      buffer.writeln('🎉 *Alhamdulillah, Tabungan PBB sudah cukup untuk dilunaskan!* Terima kasih atas ketaatan dan kerja samanya. 🙏');
    } else {
      buffer.writeln('Semoga tabungan PBB ini mempermudah pelunasan sebelum jatuh tempo. Terima kasih! 🙏');
    }
    return buffer.toString();
  }
}

