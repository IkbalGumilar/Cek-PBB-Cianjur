import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Model data untuk kata-kata pengingat dan motivasi petugas PBB
class PetugasQuote {
  final String text;
  final String category;
  final IconData icon;

  const PetugasQuote({
    required this.text,
    this.category = 'Pengingat Petugas',
    this.icon = Icons.format_quote_rounded,
  });
}

/// Daftar 100 kata-kata pepeling, heureuy lapangan, jeung panyumangat patugas PBB
class PetugasQuoteRepository {
  static const List<PetugasQuote> quotes = [
    PetugasQuote(text: "Duit titipan rahayat teh amanah. Setorkeun pas waktu, ngarah barokah keur kulawarga di bumi."),
    PetugasQuote(text: "Target 60% kudu kahontal memeh 30 September. Ulah nungguan dek labuh tempo kakara gegebegan!"),
    PetugasQuote(text: "Inget, 30 September teh wates labuh tempo PBB. Amankeun heula saeutikna 60% ti ayeuna keneh."),
    PetugasQuote(text: "Cicil tagihan ti ayeuna, ulah nungguan tungtung bulan. Target 60% samemeh 30 September teh kawajiban!"),
    PetugasQuote(text: "Kompak jeung sasama patugas. Babarengan mah udagan target 60% teh moal karasa beurat."),
    PetugasQuote(text: "Ulah era silih taroskeun data objek sesah ka baturna. Koordinasi nu rapih matak target gancang beres."),
    PetugasQuote(text: "Unggal lengkah suku ti imah ka imah poe ieu nyaeta kesang nyata pikeun ngawangun lembur urang."),
    PetugasQuote(text: "Sanajan panas ngentrung, inget 30 September geus ngadagoan. Semangat ngejar target!"),
    PetugasQuote(text: "Satu SPPT nu katarima ku warga kalayan bener nyaeta lengkah nyata ngamajukeun Cianjur."),
    PetugasQuote(text: "Ulah lali pariksa deui NOP jeung nami Wajib Pajak memeh nyatet lunas, taliti teh konci utama."),
    PetugasQuote(text: "Duit PBB nu kakumpul baris balik deui ka warga jadi jalan lecir, irigasi, jeung kamajuan desa."),
    PetugasQuote(text: "Target luhur kahontal ti ketukan panto mimiti di isuk-isuk. Bismillah, gusti nu maparin rezeki."),
    PetugasQuote(text: "Beja ti korlap: amankeun heula 60% memeh 30 September, ngarah engke sararea tibra sare."),
    PetugasQuote(text: "Ulah leumpang sorangan-sorangan, rempug jukung babarengan ngudag target di tiap blok."),
    PetugasQuote(text: "Amanah rahayat ulah dikurangan sasen oge. Gawe jujur, hate tenang, rezeki barokah."),
    PetugasQuote(text: "30 September geus beuki deukeut. Cing mariksa deui, geus sabaraha persen blok urang poe ieu?"),
    PetugasQuote(text: "Samemeh 30 September, kabeh titipan kudu beres. Nu kungsi kapake keur darurat wajib geus digantian lunas!"),
    PetugasQuote(text: "Ketukan panto isuk-isuk mawa harepan, setoran pasosore mawa katentreman."),
    PetugasQuote(text: "Tong eleh ku rasa hoream. Target labuh tempo 30 September moal bisa diundur-undur deui."),
    PetugasQuote(text: "Silih bejaan, silih rojong sasama kolektor. Mun hiji meunang, sararea oge ngiring reueus."),
    PetugasQuote(text: "Sing someah, darehdeh, tur hade gogobrog ka Wajib Pajak. Eta konci pikeun ngalemeskeun hate warga."),
    PetugasQuote(text: "Warga loba pamenta aneh-aneh? Seuri weh sing manis, dangukeun sing sabar, terus sodorkeun SPPT-na."),
    PetugasQuote(text: "Warga keur aral atawa kuraweud? Ulah dibales ambek, bales ku imut jeung basa nu lemes."),
    PetugasQuote(text: "Pajak mah kawajiban, tapi palayanan mah kahadean hate patugas. Sing sabar mayunan rupa-rupa adat warga."),
    PetugasQuote(text: "Sanajan disalahkeun perkawis jalan ruksak, tetep jelaskeun mangpaat PBB kalayan tenang jeung wijaksana."),
    PetugasQuote(text: "Wajib Pajak nawar PBB jiga nawar bonteng di pasar? Tarik napas jero-jero, seuri, jelaskeun aturan resmina."),
    PetugasQuote(text: "Lamun warga mimiti curhat masalah pribadi, dangukeun sakeudeung, teras lebetkeun perkawis tagihan."),
    PetugasQuote(text: "Kolektor sejati: dicarekan warga tetep someah, balik mawa duit titipan bari ngedalkeun hatur nuhun."),
    PetugasQuote(text: "Teu aya panto nu teu muka mun diketok ku basa nu hade jeung paroman nu marahmay."),
    PetugasQuote(text: "Warga nanyakeun kunaon pajetna naek? Jelaskeun kalayan sopan yen tanah jeung wangunan geus mekar."),
    PetugasQuote(text: "Lamun panggih jeung warga nu langsung mayar harita keneh tanpa loba alesan, langsung duakeun sing barokah!"),
    PetugasQuote(text: "Disuguhan cai haneut jeung kulub sampeu ku warga, tampi kalayan bungah, eta tanda kanyaah rahayat."),
    PetugasQuote(text: "Tatakeuna sopan santun urang Sunda: punten, hatur nuhun, jeung hampura ulah tepi ka tinggaleun."),
    PetugasQuote(text: "Sabar teh lain eleh, tapi cara patugas ngajaga komara pamarentah desa di hapeupeun warga."),
    PetugasQuote(text: "Lamun warga keur teu boga artos, ulah dipaksa teuing. Catet, titip pesen sing sae, isuk jaganing geto disampeur deui."),
    PetugasQuote(text: "Senyum patugas di panto imah warga nyaeta ubar kacape nu pang ampuhna."),
    PetugasQuote(text: "Nyanghareupan warga mah kudu boga stok sabar sagegedong, bisi beak di jalan!"),
    PetugasQuote(text: "Warga menta kuitansi dicap opat warna? Layanan weh, nu penting mah duitna lunas lebet ka kas."),
    PetugasQuote(text: "Lemes basa, teuneung ludeung, jembar panalar. Eta pakarang utama patugas di lapangan."),
    PetugasQuote(text: "Tong pondok pangharepan mun ditarolak warga. Sugan isuk mah geus meunang rezeki teras ngalunasan."),
    PetugasQuote(text: "Nu di kantor niis handapeun AC, urang di lapangan kahaneutan ku panonpoe. Tapi soal mental, urang juarana!"),
    PetugasQuote(text: "Gaji mah enya pang saeutikna, tapi mun kolektor lapangan mogok sapoe, kantor desa bisa bingung!"),
    PetugasQuote(text: "Kulit hideung lestreng kahalodoan teu nanaon, nu penting rezeki halal keur murangkalih di bumi."),
    PetugasQuote(text: "Nu di kantor nyepeng laptop bari nyuruput kopi, urang nyepeng map SPPT bari lumpat diudag anjing!"),
    PetugasQuote(text: "Gaji ipis lain alesan gawe kendor. Kesang patugas lapangan nyaeta pondasi wangunan di lembur."),
    PetugasQuote(text: "Insentif eleh ku nu calik dina korsi empuk, tapi ganjaran silaturahmi urang insya Allah ngalimpah."),
    PetugasQuote(text: "Ujung tombak penagihan, ulah tepi ka jadi ujung tombok operasional! Bensin rek beak, semangat ulah pareum."),
    PetugasQuote(text: "Calik di kantor matak nundutan, leumpang mapay gang matak langsing alami. Aya hikmahna lur!"),
    PetugasQuote(text: "Gaji saeutik asal berkah matak nengtremkeun, tibatan loba tapi matak geumpeur jeung tagiwur."),
    PetugasQuote(text: "Nu di kantor lieur ku rumus Excel, urang di lapangan lieur neangan imah nu cenah 'palireun tangkal jengkol'."),
    PetugasQuote(text: "Dompet meureun kempes, tapi kawani jeung tanggung jawab patugas lapangan salawasna kandel!"),
    PetugasQuote(text: "Kolektor lapangan mah kuat sagala: kuat halodo, kuat hujan, jeung kuat ningali struk gajina sorangan!"),
    PetugasQuote(text: "Nu di kantor seungit parfum mewah, urang mah seungit minyak kayu putih jeung haseup knalpot. Sarua muliana!"),
    PetugasQuote(text: "Gaji minimalis, tapi tapak lacak perjuangan urang di saban pelosok lembur kualitasna maksimalis."),
    PetugasQuote(text: "Tong leutik hate pedah gajih saeutik. Sabulir kesang urang jadi amal jariah keur kamajuan Cianjur."),
    PetugasQuote(text: "Pejuang lapangan: sandal jepit geus ipis, motor butut ngadat, tapi target 60% samemeh 30 September tetep kahontal!"),
    PetugasQuote(text: "Duit PBB lain duit saku pribadi! Haram dipake nilep hak rahayat, setorkeun kabeh kalayan jujur."),
    PetugasQuote(text: "Duit pajak lain kasbon! Mun kaayaan darurat kapaksa kapake, WAJIB digantian harita keneh samemeh setoran."),
    PetugasQuote(text: "Ulah ngabiasakeun 'nginjeum' duit setoran. Mun kapake darurat, buru-buru tutup deui bisi jadi urusan hukum!"),
    PetugasQuote(text: "Sanajan dompet ipis siga kurupuk, tapak gawe urang di lapangan tembus tepi ka langit!"),
    PetugasQuote(text: "Sandal aya lima pasang dina teras, motor tilu ngajajar, pas diketok ngawaler: 'Nu gaduhna nuju ka luar kota, Pa!'"),
    PetugasQuote(text: "Imah agreng tingkat tilu mobil aya di garasi, giliran mayar PBB Rp 35.000 menta dicicil tilu kali!"),
    PetugasQuote(text: "Akal patugas mun warga api-api sare: ketok pantona bari ngambeu-ngambeu bala-bala haneut."),
    PetugasQuote(text: "Ngetok panto isuk-isuk harepan panggih jeung nu boga imah, ari pek nu kaluar anjing galak. Uji nyali dimulai!"),
    PetugasQuote(text: "Waktu ditagih pokna: 'Ke antos panen', ari geus panen pokna deui: 'Aduh artosna parantos kangge DP motor!'"),
    PetugasQuote(text: "Patugas lapangan mah kudu apal: aya sora gohekan ti jero imah hartina jalmana aya di kamar!"),
    PetugasQuote(text: "Ngakuna nuju teu nyepeng artos pisan, ari pas patugas rek pamit kurir paket COD datang!"),
    PetugasQuote(text: "PBB mah sataun sakali, tapi dramana leuwih panjang tibatan sandiwara radio."),
    PetugasQuote(text: "Warga nyungkeun bukti mayar dipotoan tina saban juru. Layanan weh, nu penting mah artosna katampi."),
    PetugasQuote(text: "Disuguhan kopi tiis jeung rengginang dina kaleng biskuit Kong Guan. Tong ditolak, eta ciri bageurna warga!"),
    PetugasQuote(text: "Kolektor senior mah geus apal bedana sora imah kosong jeung sora warga nu keur nyumput di kolong ranjang."),
    PetugasQuote(text: "Dina SPPT alamatna 'Blok Sawah Tonggoh', pas disampeurkeun geus robah jadi balong lauk nila. Catet dina katerangan!"),
    PetugasQuote(text: "Warga protes: 'Naha pajak abdi naek, Pa?' Padahal baheula kebon eurih, ayeuna geus ngadeg ruko tilu panto."),
    PetugasQuote(text: "Geus ngurilingan lima blok neangan imah Pa RT, ari pek imahna nu tadi kaliwatan mimiti pisan."),
    PetugasQuote(text: "Gogoda pang beuratna kolektor lain panas atawa hujan, tapi ningali bel-bel awi di teras warga matak tunduh."),
    PetugasQuote(text: "Warga ambek-ambekan jalan gararejul, padahal pajetna nunggak lima taun. Balas ku imut bari sodorkeun SPPT-na."),
    PetugasQuote(text: "Gaji saeutik ulah matak ngurangan harga diri. Duit titipan warga kudu utuh nepi ka kas daerah tanpa kakurangan sasen!"),
    PetugasQuote(text: "Kolektor teh intel desa: apal saha nu kakara ngajual tanah, apal saha nu kakara ngajual cengkeh."),
    PetugasQuote(text: "Inget, duit pajak nu kapake tapi teu digantian baris jadi hisab beurat di aherat jeung matak nyilakakeun kulawarga."),
    PetugasQuote(text: "Kopi hideung geus lekasan tilu gelas, tapi SPPT can aya nu lunas hiji-hiji acan. Hayu nginum deui, tarekah deui!"),
    PetugasQuote(text: "Panas ngentrung ulah poho mawa botol cai bodas. Ginjal sehat, nagih lancar tepi ka burit."),
    PetugasQuote(text: "Dahar beurang ulah ditunda-tunda. Niatna ngudag target, ulah tepi ka maag nu meunang."),
    PetugasQuote(text: "Jas hujan kudu sayaga dina jok motor. Usum pancaroba, ulah tepi ka katirisan memeh 30 September."),
    PetugasQuote(text: "Mun awak geus mimiti muriang jeung punduk karasa beurat, ngaleueut tolak angin teras reureuh heula. Awak anjeun berharga!"),
    PetugasQuote(text: "Jalanan lembur loba batu jeung leueur. Lalaunan weh nyetirna, target penting tapi nyawa tetep nomer hiji."),
    PetugasQuote(text: "Kurangan kopi gelas kaopat poe ieu, lobakeun cai herang ngarah sirah teu nyanyautan kahalodoan."),
    PetugasQuote(text: "Anggo helm standar tur pariksa rem motor samemeh ngabring. Kasalametan anjeun dianti-anti ku kulawarga di bumi."),
    PetugasQuote(text: "Koyo dina tonggong lain tanda lemah, eta lambang perjuangan kolektor lapangan nu sajati!"),
    PetugasQuote(text: "Sapatu baseuh kahujanan gancang ganti, ulah dipaksa sapoe jeput ngarah dampal suku teu rorombeheun."),
    PetugasQuote(text: "Ulah nahan kahampangan di jalan. Ngarandeg heula ka bale desa atawa ka tajug terdekat."),
    PetugasQuote(text: "Mulih dines kumbah beungeut jeung reureuhkeun suku dina cai haneut. Pulihkeun tanaga keur isuk pageto."),
    PetugasQuote(text: "Gorengan di warung ulah dihanca kabeh. Tikoro serak matak hese ngawangkong ka Wajib Pajak."),
    PetugasQuote(text: "Awak jagjag waringkas matak imut patugas tetep manis sanajan dibebelekek ku warga."),
    PetugasQuote(text: "Inget, murangkalih jeung geureuha ngadagoan anjeun mulang kalayan salamet tur seuri, lain ngadenge anjeun asup puskesmas."),
    PetugasQuote(text: "Mun poe ieu loba ditarolak, jadikeun pangalaman. Kesang anjeun moal mubadir di payuneun Gusti."),
    PetugasQuote(text: "Jalan satapak nu pinuh ku leutak moal bisa ngeureunkeun tekad patugas nu boga wawanen."),
    PetugasQuote(text: "Bismillah dina ketukan panto mimiti, Alhamdulillah waktu nyetorkeun titipan panungtung."),
    PetugasQuote(text: "Lengkahan suku anjeun poe ieu mangrupakeun saksi nyata yen lembur urang terus ngalengkah maju."),
    PetugasQuote(text: "Kompak jeung batur salembur, someah ka sakumna warga, jujur ka nagara. Eta kahormatan sajati urang!"),
    PetugasQuote(text: "Tutup poe ieu ku rasa syukur. Isuk panonpoe medal deui, mawa sumanget anyar ngahontal 100%!"),
  ];

  static final Random _random = Random();

  /// Mengambil kutipan acak
  static PetugasQuote getRandomQuote({int? excludeIndex}) {
    if (quotes.length <= 1) return quotes.first;
    int nextIndex;
    do {
      nextIndex = _random.nextInt(quotes.length);
    } while (nextIndex == excludeIndex);
    return quotes[nextIndex];
  }
}

/// Kartu Banner Motivasi Petugas di Bawah Header dengan animasi muncul,
/// efek ketik per-huruf (typewriter), bertahan 12 detik, lalu menghilang halus.
class PetugasQuoteBanner extends StatefulWidget {
  final int triggerNonce;
  final bool visible;
  final Duration dwellDuration;
  final Duration typewriterSpeed;
  final VoidCallback? onDismiss;

  const PetugasQuoteBanner({
    super.key,
    this.triggerNonce = 0,
    this.visible = true,
    this.dwellDuration = const Duration(seconds: 12),
    this.typewriterSpeed = const Duration(milliseconds: 20),
    this.onDismiss,
  });

  @override
  State<PetugasQuoteBanner> createState() => _PetugasQuoteBannerState();
}

class _PetugasQuoteBannerState extends State<PetugasQuoteBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _panelController;
  late final Animation<double> _panelCurve;
  late final Animation<Offset> _panelSlide;

  late PetugasQuote _currentQuote;
  int _currentIndex = 0;
  int _displayedCharCount = 0;
  bool _isTyping = false;

  Timer? _typewriterTimer;
  Timer? _dwellTimer;

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 380),
    );

    _panelCurve = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _panelSlide = Tween<Offset>(
      begin: const Offset(0, -0.45),
      end: Offset.zero,
    ).animate(_panelCurve);

    _currentQuote = PetugasQuoteRepository.getRandomQuote();
    _currentIndex = PetugasQuoteRepository.quotes.indexOf(_currentQuote);

    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startQuoteCycle();
      });
    }
  }

  @override
  void didUpdateWidget(PetugasQuoteBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _cancelTimers();
      _panelController.reverse();
      return;
    }

    if (widget.triggerNonce != oldWidget.triggerNonce ||
        (widget.visible && !oldWidget.visible)) {
      _startQuoteCycle();
    }
  }

  @override
  void dispose() {
    _cancelTimers();
    _panelController.dispose();
    super.dispose();
  }

  void _cancelTimers() {
    _typewriterTimer?.cancel();
    _typewriterTimer = null;
    _dwellTimer?.cancel();
    _dwellTimer = null;
  }

  void _startQuoteCycle() {
    _cancelTimers();

    _currentQuote = PetugasQuoteRepository.getRandomQuote(
      excludeIndex: _currentIndex,
    );
    _currentIndex = PetugasQuoteRepository.quotes.indexOf(_currentQuote);

    setState(() {
      _displayedCharCount = 0;
      _isTyping = true;
    });

    _panelController.forward().then((_) {
      if (!mounted) return;
      _runTypewriter();
    });
  }

  void _runTypewriter() {
    _typewriterTimer?.cancel();
    final fullText = _currentQuote.text;

    _typewriterTimer = Timer.periodic(widget.typewriterSpeed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_displayedCharCount < fullText.length) {
        setState(() {
          _displayedCharCount++;
        });
      } else {
        timer.cancel();
        setState(() {
          _isTyping = false;
        });

        // Teks selesai diketik utuh -> Bertahan selama 12 detik lalu menghilang
        _dwellTimer?.cancel();
        _dwellTimer = Timer(widget.dwellDuration, () {
          if (mounted) {
            _panelController.reverse();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final fullText = _currentQuote.text;
    final safeCount = _displayedCharCount.clamp(0, fullText.length);
    final visibleText = fullText.substring(0, safeCount);

    return AnimatedBuilder(
      animation: _panelCurve,
      builder: (context, _) {
        if (_panelCurve.value == 0.0) {
          return const SizedBox.shrink();
        }
        return SizeTransition(
          sizeFactor: _panelCurve,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _panelCurve,
            child: SlideTransition(
              position: _panelSlide,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Container(
                  key: const ValueKey('petugas_quote_card'),
                  decoration: BoxDecoration(
                    color: isDark
                        ? colorScheme.surfaceContainerHigh.withValues(alpha: 0.6)
                        : colorScheme.primaryContainer.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                          : colorScheme.primary.withValues(alpha: 0.25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      // Watermark ornamen kutipan di sudut kanan bawah yang halus
                      Positioned(
                        right: -4,
                        bottom: -10,
                        child: IgnorePointer(
                          child: Icon(
                            Icons.format_quote_rounded,
                            size: 64,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.035)
                                : colorScheme.primary.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                        child: Center(
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                                fontSize: 13.5,
                                color: isDark ? Colors.white.withValues(alpha: 0.92) : Colors.black87,
                              ),
                              children: [
                                const TextSpan(text: '"'),
                                TextSpan(text: visibleText),
                                if (_isTyping)
                                  TextSpan(
                                    text: '▏',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontStyle: FontStyle.normal,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                const TextSpan(text: '"'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);
}
}
