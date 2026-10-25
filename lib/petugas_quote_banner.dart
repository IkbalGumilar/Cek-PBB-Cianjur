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

/// Daftar 100 kata-kata pépéling, heureuy lapangan, jeung panyumangat patugas PBB
class PetugasQuoteRepository {
  static const List<PetugasQuote> quotes = [
    PetugasQuote(text: "Duit titipan rahayat téh amanah. Setorkeun pas waktu, ngarah barokah keur kulawarga di bumi."),
    PetugasQuote(text: "Target 60% kudu kahontal méméh 30 Séptémber. Ulah nungguan dék labuh tempo kakara gegebegan!"),
    PetugasQuote(text: "Inget, 30 Séptémber téh wates labuh tempo PBB. Amankeun heula saeutikna 60% ti ayeuna kénéh."),
    PetugasQuote(text: "Cicil tagihan ti ayeuna, ulah nungguan tungtung bulan. Target 60% saméméh 30 Séptémber téh kawajiban!"),
    PetugasQuote(text: "Kompak jeung sasama patugas. Babarengan mah udagan target 60% téh moal karasa beurat."),
    PetugasQuote(text: "Ulah éra silih taroskeun data objek sesah ka baturna. Koordinasi nu rapih matak target gancang bérés."),
    PetugasQuote(text: "Unggal léngkah suku ti imah ka imah poé ieu nyaéta késang nyata pikeun ngawangun lembur urang."),
    PetugasQuote(text: "Sanajan panas ngentrung, inget 30 Séptémber geus ngadagoan. Semangat ngejar target!"),
    PetugasQuote(text: "Satu SPPT nu katarima ku warga kalayan bener nyaéta léngkah nyata ngamajukeun Cianjur."),
    PetugasQuote(text: "Ulah lali pariksa deui NOP jeung nami Wajib Pajak méméh nyatet lunas, taliti téh konci utama."),
    PetugasQuote(text: "Duit PBB nu kakumpul baris balik deui ka warga jadi jalan lecir, irigasi, jeung kamajuan desa."),
    PetugasQuote(text: "Target luhur kahontal ti ketukan panto mimiti di isuk-isuk. Bismillah, gusti nu maparin rezeki."),
    PetugasQuote(text: "Béja ti korlap: amankeun heula 60% méméh 30 Séptémber, ngarah engké sararéa tibra saré."),
    PetugasQuote(text: "Ulah leumpang sorangan-sorangan, rempug jukung babarengan ngudag target di tiap blok."),
    PetugasQuote(text: "Amanah rahayat ulah dikurangan sasén ogé. Gawe jujur, haté tenang, rezeki barokah."),
    PetugasQuote(text: "30 Séptémber geus beuki deukeut. Cing mariksa deui, geus sabaraha persen blok urang poé ieu?"),
    PetugasQuote(text: "Saméméh 30 Séptémber, kabéh titipan kudu bérés. Nu kungsi kapaké keur darurat wajib geus digantian lunas!"),
    PetugasQuote(text: "Ketukan panto isuk-isuk mawa harepan, setoran pasosoré mawa katentreman."),
    PetugasQuote(text: "Tong éléh ku rasa hoream. Target labuh tempo 30 Séptémber moal bisa diundur-undur deui."),
    PetugasQuote(text: "Silih béjaan, silih rojong sasama kolektor. Mun hiji meunang, sararéa ogé ngiring reueus."),
    PetugasQuote(text: "Sing soméah, daréhdéh, tur hadé gogobrog ka Wajib Pajak. Éta konci pikeun ngalemeskeun haté warga."),
    PetugasQuote(text: "Warga loba paménta anéh-anéh? Seuri wéh sing manis, dangukeun sing sabar, terus sodorkeun SPPT-na."),
    PetugasQuote(text: "Warga keur aral atawa kuraweud? Ulah dibales ambek, bales ku imut jeung basa nu lemes."),
    PetugasQuote(text: "Pajak mah kawajiban, tapi palayanan mah kahadéan haté patugas. Sing sabar mayunan rupa-rupa adat warga."),
    PetugasQuote(text: "Sanajan disalahkeun perkawis jalan ruksak, tetep jelaskeun mangpaat PBB kalayan tenang jeung wijaksana."),
    PetugasQuote(text: "Wajib Pajak nawar PBB jiga nawar bonténg di pasar? Tarik napas jero-jero, seuri, jelaskeun aturan resmina."),
    PetugasQuote(text: "Lamun warga mimiti curhat masalah pribadi, dangukeun sakeudeung, teras lebetkeun perkawis tagihan."),
    PetugasQuote(text: "Kolektor sejati: dicarékan warga tetep soméah, balik mawa duit titipan bari ngedalkeun hatur nuhun."),
    PetugasQuote(text: "Teu aya panto nu teu muka mun diketok ku basa nu hadé jeung paroman nu marahmay."),
    PetugasQuote(text: "Warga nanyakeun kunaon pajetna naek? Jelaskeun kalayan sopan yén tanah jeung wangunan geus mekar."),
    PetugasQuote(text: "Lamun panggih jeung warga nu langsung mayar harita kénéh tanpa loba alesan, langsung duakeun sing barokah!"),
    PetugasQuote(text: "Disuguhan cai haneut jeung kulub sampeu ku warga, tampi kalayan bungah, éta tanda kanyaah rahayat."),
    PetugasQuote(text: "Tatakeuna sopan santun urang Sunda: punten, hatur nuhun, jeung hampura ulah tepi ka tinggaleun."),
    PetugasQuote(text: "Sabar téh lain éléh, tapi cara patugas ngajaga komara pamaréntah desa di hapeupeun warga."),
    PetugasQuote(text: "Lamun warga keur teu boga artos, ulah dipaksa teuing. Catet, titip pesen sing saé, isuk jaganing geto disampeur deui."),
    PetugasQuote(text: "Senyum patugas di panto imah warga nyaéta ubar kacapé nu pang ampuhna."),
    PetugasQuote(text: "Nyanghareupan warga mah kudu boga stok sabar sagegedong, bisi béak di jalan!"),
    PetugasQuote(text: "Warga menta kuitansi dicap opat warna? Layanan wéh, nu penting mah duitna lunas lebet ka kas."),
    PetugasQuote(text: "Lemes basa, teuneung ludeung, jembar panalar. Éta pakarang utama patugas di lapangan."),
    PetugasQuote(text: "Tong pondok pangharepan mun ditarolak warga. Sugan isuk mah geus meunang rezeki teras ngalunasan."),
    PetugasQuote(text: "Nu di kantor niis handapeun AC, urang di lapangan kahaneutan ku panonpoé. Tapi soal mental, urang juarana!"),
    PetugasQuote(text: "Gaji mah enya pang saeutikna, tapi mun kolektor lapangan mogok sapoé, kantor desa bisa bingung!"),
    PetugasQuote(text: "Kulit hideung lestreng kahalodoan teu nanaon, nu penting rezeki halal keur murangkalih di bumi."),
    PetugasQuote(text: "Nu di kantor nyepeng laptop bari nyuruput kopi, urang nyepeng map SPPT bari lumpat diudag anjing!"),
    PetugasQuote(text: "Gaji ipis lain alesan gawe kendor. Késang patugas lapangan nyaéta pondasi wangunan di lembur."),
    PetugasQuote(text: "Inséntif eleh ku nu calik dina korsi empuk, tapi ganjaran silaturahmi urang insya Allah ngalimpah."),
    PetugasQuote(text: "Ujung tombak penagihan, ulah tepi ka jadi ujung tombok operasional! Bensin rék béak, semangat ulah pareum."),
    PetugasQuote(text: "Calik di kantor matak nundutan, leumpang mapay gang matak langsing alami. Aya hikmahna lur!"),
    PetugasQuote(text: "Gaji saeutik asal berkah matak nengtremkeun, tibatan loba tapi matak geumpeur jeung tagiwur."),
    PetugasQuote(text: "Nu di kantor lieur ku rumus Excel, urang di lapangan lieur néangan imah nu cenah 'palireun tangkal jéngkol'."),
    PetugasQuote(text: "Dompét meureun kempes, tapi kawani jeung tanggung jawab patugas lapangan salawasna kandel!"),
    PetugasQuote(text: "Kolektor lapangan mah kuat sagala: kuat halodo, kuat hujan, jeung kuat ningali struk gajina sorangan!"),
    PetugasQuote(text: "Nu di kantor seungit parfum méwah, urang mah seungit minyak kayu putih jeung haseup knalpot. Sarua muliana!"),
    PetugasQuote(text: "Gaji minimalis, tapi tapak lacak perjuangan urang di saban pelosok lembur kualitasna maksimalis."),
    PetugasQuote(text: "Tong leutik haté pedah gajih saeutik. Sabulir késang urang jadi amal jariah keur kamajuan Cianjur."),
    PetugasQuote(text: "Pejuang lapangan: sandal jepit geus ipis, motor butut ngadat, tapi target 60% saméméh 30 Séptémber tetep kahontal!"),
    PetugasQuote(text: "Duit PBB lain duit saku pribadi! Haram dipaké nilep hak rahayat, setorkeun kabéh kalayan jujur."),
    PetugasQuote(text: "Duit pajak lain kasbon! Mun kaayaan darurat kapaksa kapaké, WAJIB digantian harita kénéh saméméh setoran."),
    PetugasQuote(text: "Ulah ngabiasakeun 'nginjeum' duit setoran. Mun kapaké darurat, buru-buru tutup deui bisi jadi urusan hukum!"),
    PetugasQuote(text: "Sanajan dompet ipis siga kurupuk, tapak gawe urang di lapangan tembus tepi ka langit!"),
    PetugasQuote(text: "Sandal aya lima pasang dina teras, motor tilu ngajajar, pas diketok ngawaler: 'Nu gaduhna nuju ka luar kota, Pa!'"),
    PetugasQuote(text: "Imah agréng tingkat tilu mobil aya di garasi, giliran mayar PBB Rp 35.000 menta dicicil tilu kali!"),
    PetugasQuote(text: "Akal patugas mun warga api-api saré: ketok pantona bari ngambeu-ngambeu bala-bala haneut."),
    PetugasQuote(text: "Ngetok panto isuk-isuk harepan panggih jeung nu boga imah, ari pek nu kaluar anjing galak. Uji nyali dimulai!"),
    PetugasQuote(text: "Waktu ditagih pokna: 'Ke antos panén', ari geus panén pokna deui: 'Aduh artosna parantos kanggé DP motor!'"),
    PetugasQuote(text: "Patugas lapangan mah kudu apal: aya sora gohékan ti jero imah hartina jalmana aya di kamar!"),
    PetugasQuote(text: "Ngakuna nuju teu nyepeng artos pisan, ari pas patugas rék pamit kurir paket COD datang!"),
    PetugasQuote(text: "PBB mah sataun sakali, tapi dramana leuwih panjang tibatan sandiwara radio."),
    PetugasQuote(text: "Warga nyungkeun bukti mayar dipotoan tina saban juru. Layanan wéh, nu penting mah artosna katampi."),
    PetugasQuote(text: "Disuguhan kopi tiis jeung réngginang dina kaléng biskuit Kong Guan. Tong ditolak, éta ciri bageurna warga!"),
    PetugasQuote(text: "Kolektor senior mah geus apal bédana sora imah kosong jeung sora warga nu keur nyumput di kolong ranjang."),
    PetugasQuote(text: "Dina SPPT alamatna 'Blok Sawah Tonggoh', pas disampeurkeun geus robah jadi balong lauk nila. Catet dina katerangan!"),
    PetugasQuote(text: "Warga protés: 'Naha pajak abdi naék, Pa?' Padahal baheula kebon eurih, ayeuna geus ngadeg ruko tilu panto."),
    PetugasQuote(text: "Geus ngurilingan lima blok néangan imah Pa RT, ari pék imahna nu tadi kaliwatan mimiti pisan."),
    PetugasQuote(text: "Gogoda pang beuratna kolektor lain panas atawa hujan, tapi ningali bél-bél awi di teras warga matak tunduh."),
    PetugasQuote(text: "Warga ambek-ambekan jalan gararejul, padahal pajetna nunggak lima taun. Balas ku imut bari sodorkeun SPPT-na."),
    PetugasQuote(text: "Gaji saeutik ulah matak ngurangan harga diri. Duit titipan warga kudu utuh nepi ka kas daerah tanpa kakurangan sasén!"),
    PetugasQuote(text: "Kolektor téh intel desa: apal saha nu kakara ngajual tanah, apal saha nu kakara ngajual cengkéh."),
    PetugasQuote(text: "Inget, duit pajak nu kapaké tapi teu digantian baris jadi hisab beurat di ahérat jeung matak nyilakakeun kulawarga."),
    PetugasQuote(text: "Kopi hideung geus lekasan tilu gelas, tapi SPPT can aya nu lunas hiji-hiji acan. Hayu nginum deui, tarékah deui!"),
    PetugasQuote(text: "Panas ngentrung ulah poho mawa botol cai bodas. Ginjal séhat, nagih lancar tepi ka burit."),
    PetugasQuote(text: "Dahar beurang ulah ditunda-tunda. Niatna ngudag target, ulah tepi ka maag nu meunang."),
    PetugasQuote(text: "Jas hujan kudu sayaga dina jok motor. Usum pancaroba, ulah tepi ka katirisan méméh 30 Séptémber."),
    PetugasQuote(text: "Mun awak geus mimiti muriang jeung punduk karasa beurat, ngaleueut tolak angin teras reureuh heula. Awak anjeun berharga!"),
    PetugasQuote(text: "Jalanan lembur loba batu jeung leueur. Lalaunan wéh nyetirna, target penting tapi nyawa tetep nomer hiji."),
    PetugasQuote(text: "Kurangan kopi gelas kaopat poé ieu, lobakeun cai hérang ngarah sirah teu nyanyautan kahalodoan."),
    PetugasQuote(text: "Anggo helm standar tur pariksa rem motor saméméh ngabring. Kasalametan anjeun dianti-anti ku kulawarga di bumi."),
    PetugasQuote(text: "Koyo dina tonggong lain tanda lemah, éta lambang perjuangan kolektor lapangan nu sajati!"),
    PetugasQuote(text: "Sapatu baseuh kahujanan gancang ganti, ulah dipaksa sapoé jeput ngarah dampal suku teu rorombeheun."),
    PetugasQuote(text: "Ulah nahan kahampangan di jalan. Ngarandeg heula ka balé desa atawa ka tajug terdekat."),
    PetugasQuote(text: "Mulih dines kumbah beungeut jeung reureuhkeun suku dina cai haneut. Pulihkeun tanaga keur isuk pagéto."),
    PetugasQuote(text: "Gorengan di warung ulah dihanca kabéh. Tikoro serak matak hésé ngawangkong ka Wajib Pajak."),
    PetugasQuote(text: "Awak jagjag waringkas matak imut patugas tetep manis sanajan dibébélékék ku warga."),
    PetugasQuote(text: "Inget, murangkalih jeung geureuha ngadagoan anjeun mulang kalayan salamet tur seuri, lain ngadéngé anjeun asup puskésmas."),
    PetugasQuote(text: "Mun poé ieu loba ditarolak, jadikeun pangalaman. Késang anjeun moal mubadir di payuneun Gusti."),
    PetugasQuote(text: "Jalan satapak nu pinuh ku leutak moal bisa ngeureunkeun tékad patugas nu boga wawanén."),
    PetugasQuote(text: "Bismillah dina ketukan panto mimiti, Alhamdulillah waktu nyetorkeun titipan panungtung."),
    PetugasQuote(text: "Lengkahan suku anjeun poé ieu mangrupakeun saksi nyata yén lembur urang terus ngaléngkah maju."),
    PetugasQuote(text: "Kompak jeung batur salembur, soméah ka sakumna warga, jujur ka nagara. Éta kahormatan sajati urang!"),
    PetugasQuote(text: "Tutup poé ieu ku rasa syukur. Isuk panonpoé medal deui, mawa sumanget anyar ngahontal 100%!"),
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
