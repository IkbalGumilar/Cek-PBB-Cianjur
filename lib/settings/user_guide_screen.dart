import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../feature_tour/feature_tour.dart';
import 'user_guide_data.dart';

class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  final TextEditingController _searchController = TextEditingController();
  GuideCategory _selectedCategory = GuideCategory.all;
  String _searchQuery = '';
  int? _expandedFaqIndex = 0;

  static const List<String> _quickKeywords = [
    'QRIS',
    'Banyak NOP',
    'DHKP',
    'Kolektif',
    'Google Drive',
    'Saweria',
    'MFA',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<GuideTopic> get _filteredTopics {
    final q = _searchQuery.trim().toLowerCase();
    return UserGuideRepository.topics.where((topic) {
      if (_selectedCategory != GuideCategory.all &&
          _selectedCategory != GuideCategory.faq &&
          topic.category != _selectedCategory) {
        return false;
      }
      if (_selectedCategory == GuideCategory.faq) {
        return false;
      }
      if (q.isEmpty) return true;
      if (topic.title.toLowerCase().contains(q) ||
          topic.subtitle.toLowerCase().contains(q) ||
          topic.summary.toLowerCase().contains(q) ||
          topic.chapterBadge.toLowerCase().contains(q)) {
        return true;
      }
      for (final pin in topic.pins) {
        if (pin.title.toLowerCase().contains(q) ||
            pin.description.toLowerCase().contains(q) ||
            (pin.tip?.toLowerCase().contains(q) ?? false)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  List<GuideFaqItem> get _filteredFaqs {
    final q = _searchQuery.trim().toLowerCase();
    return UserGuideRepository.faqs.where((faq) {
      if (_selectedCategory != GuideCategory.all &&
          _selectedCategory != GuideCategory.faq &&
          faq.category != _selectedCategory) {
        return false;
      }
      if (q.isEmpty) return true;
      return faq.question.toLowerCase().contains(q) ||
          faq.answer.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _resetInteractiveTours() async {
    await FeatureTourStore.resetAllTours();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tur petunjuk interaktif di semua halaman telah diaktifkan kembali.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openTopic(GuideTopic topic) {
    final allTopics = UserGuideRepository.topics;
    final initialIndex = allTopics.indexOf(topic);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuideTopicDetailScreen(
          topics: allTopics,
          initialTopicIndex: initialIndex >= 0 ? initialIndex : 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topics = _filteredTopics;
    final faqs = _filteredFaqs;
    final totalPins = UserGuideRepository.topics.fold<int>(
      0,
      (sum, item) => sum + item.pins.length,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Buku Panduan & Bantuan'),
        actions: [
          IconButton(
            tooltip: 'Aktifkan Ulang Tur Layar',
            icon: const Icon(Icons.replay_rounded),
            onPressed: _resetInteractiveTours,
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // 1. Hero Header Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildHeroCard(context, scheme, totalPins),
              ),
            ),

            // 2. Search Bar & Quick Chips
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: _buildSearchSection(scheme),
              ),
            ),

            // 3. Category Filter Bar (All 6 categories visible at once)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final cat in GuideCategory.values)
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        selected: _selectedCategory == cat,
                        showCheckmark: false,
                        avatar: Icon(
                          cat.icon,
                          size: 16,
                          color: _selectedCategory == cat
                              ? scheme.onPrimary
                              : cat.color,
                        ),
                        label: Text(
                          cat.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _selectedCategory == cat
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _selectedCategory == cat
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                        selectedColor: scheme.primary,
                        backgroundColor: scheme.surfaceContainerLow,
                        side: BorderSide(
                          color: _selectedCategory == cat
                              ? scheme.primary
                              : scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                        onSelected: (_) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedCategory = cat);
                        },
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // 4. Topics List
            if (topics.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Daftar Bab Panduan Visual (${topics.length} Layar)',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        'Ketuk untuk membuka',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: topics.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final topic = topics[index];
                    return _GuideTopicCard(
                      topic: topic,
                      searchQuery: _searchQuery,
                      onTap: () => _openTopic(topic),
                    );
                  },
                ),
              ),
            ],

            // 5. FAQ Section
            if (faqs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.quiz_rounded,
                        size: 20,
                        color: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Tanya Jawab & Solusi Cepat (FAQ)',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverList.separated(
                  itemCount: faqs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final faq = faqs[index];
                    final isExpanded = _expandedFaqIndex == index;
                    return _FaqCard(
                      faq: faq,
                      isExpanded: isExpanded,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _expandedFaqIndex = isExpanded ? null : index;
                        });
                      },
                    );
                  },
                ),
              ),
            ],

            // Empty search state
            if (topics.isEmpty && faqs.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ditemukan panduan untuk "$_searchQuery"',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Coba gunakan kata kunci lain seperti "Blok", "QRIS", "DHKP", atau "Kolektif".',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _selectedCategory = GuideCategory.all;
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tampilkan Semua Panduan'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    ColorScheme scheme,
    int totalPins,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.surfaceContainerHighest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: scheme.onPrimary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panduan Visual Interaktif',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pelajari fungsi setiap tombol dan menu melalui tangkapan layar bertitik nomor yang dapat diketuk secara langsung.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatPill(
                scheme,
                Icons.phone_android_rounded,
                '${UserGuideRepository.topics.length} Layar Fitur',
              ),
              _buildStatPill(
                scheme,
                Icons.touch_app_rounded,
                '$totalPins Titik Panduan',
              ),
              _buildStatPill(
                scheme,
                Icons.offline_pin_rounded,
                'Bisa Dibaca Offline',
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _resetInteractiveTours,
              icon: const Icon(Icons.replay_circle_filled_rounded, size: 18),
              label: const Text(
                'Tampilkan Ulang Popup Tur di Semua Halaman',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: scheme.surface.withValues(alpha: 0.65),
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(ColorScheme scheme, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText:
                'Cari fitur, tombol, atau masalah (mis. QRIS, Kolektif)...',
            hintStyle: TextStyle(
              fontSize: 13.5,
              color: scheme.onSurfaceVariant,
            ),
            prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'Populer:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              ..._quickKeywords.map((kw) {
                final isSelected =
                    _searchQuery.toLowerCase() == kw.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isSelected
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerLowest,
                    side: BorderSide(
                      color: isSelected
                          ? scheme.primary
                          : scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    label: Text(
                      kw,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (isSelected) {
                          _searchController.clear();
                          _searchQuery = '';
                        } else {
                          _searchController.text = kw;
                          _searchQuery = kw;
                          _selectedCategory = GuideCategory.all;
                        }
                      });
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// TOPIC CARD IN LIST
// =============================================================================

class _GuideTopicCard extends StatelessWidget {
  final GuideTopic topic;
  final String searchQuery;
  final VoidCallback onTap;

  const _GuideTopicCard({
    required this.topic,
    required this.searchQuery,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final catColor = topic.category.color;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Miniature phone screen preview
              Container(
                width: 68,
                height: 136,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      topic.imageAsset,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          Icon(topic.icon, color: Colors.white54),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${topic.pins.length} titik',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Topic Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${topic.chapterBadge} • ${topic.category.label}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: catColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      topic.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      topic.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...topic.pins.take(3).map((pin) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(
                                alpha: 0.65,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: pin.color,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${pin.number}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    pin.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (topic.pins.length > 3)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(
                                alpha: 0.6,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '+${topic.pins.length - 3} lainnya',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// FAQ ACCORDION CARD
// =============================================================================

class _FaqCard extends StatelessWidget {
  final GuideFaqItem faq;
  final bool isExpanded;
  final VoidCallback onTap;

  const _FaqCard({
    required this.faq,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isExpanded
          ? scheme.secondaryContainer.withValues(alpha: 0.35)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isExpanded
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(faq.icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      faq.question,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Text(
                  faq.answer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE TOPIC DETAIL READER SCREEN
// =============================================================================

class GuideTopicDetailScreen extends StatefulWidget {
  final List<GuideTopic> topics;
  final int initialTopicIndex;

  const GuideTopicDetailScreen({
    super.key,
    required this.topics,
    required this.initialTopicIndex,
  });

  @override
  State<GuideTopicDetailScreen> createState() => _GuideTopicDetailScreenState();
}

class _GuideTopicDetailScreenState extends State<GuideTopicDetailScreen>
    with SingleTickerProviderStateMixin {
  late int _topicIndex;
  int _selectedPinIndex = 0;
  bool _showPins = true;
  late final AnimationController _pulseController;
  final ScrollController _scrollController = ScrollController();

  GuideTopic get _topic => widget.topics[_topicIndex];

  @override
  void initState() {
    super.initState();
    _topicIndex = widget.initialTopicIndex.clamp(0, widget.topics.length - 1);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPin(int index) {
    if (index < 0 || index >= _topic.pins.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPinIndex = index;
      _showPins = true;
    });
  }

  void _switchTopic(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.topics.length) return;
    HapticFeedback.lightImpact();
    setState(() {
      _topicIndex = newIndex;
      _selectedPinIndex = 0;
      _showPins = true;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _openFullscreenViewer() {
    showDialog<void>(
      context: context,
      builder: (_) => _FullscreenGuideImageDialog(
        topic: _topic,
        initialSelectedPinIndex: _selectedPinIndex,
        onPinSelected: (idx) => setState(() => _selectedPinIndex = idx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topic = _topic;
    final activePin = topic.pins.isNotEmpty
        ? topic.pins[_selectedPinIndex.clamp(0, topic.pins.length - 1)]
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${topic.chapterBadge} • ${topic.title}',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            tooltip: 'Perbesar Gambar Layar',
            icon: const Icon(Icons.zoom_out_map_rounded),
            onPressed: _openFullscreenViewer,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            // 1. Header Summary Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: topic.category.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${topic.chapterBadge} • ${topic.category.label}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: topic.category.color,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Layar ${_topicIndex + 1} dari ${widget.topics.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    topic.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  if (topic.warningNote != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amber.shade700.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: Colors.amber.shade800,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              topic.warningNote!,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Interactive Phone + Active Pin Spotlight Card (Unified in one view!)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  // Top Bar of Phone Preview
                  Row(
                    children: [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ketuk nomor pada gambar atau tombol panah di bawah',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      FilterChip(
                        visualDensity: VisualDensity.compact,
                        selected: _showPins,
                        label: Text(
                          _showPins ? 'Titik Aktif' : 'Sembunyi',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onSelected: (val) => setState(() => _showPins = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Compact Centered Phone Frame (width: 196 px so phone + spotlight fit together on screen)
                  Center(
                    child: SizedBox(
                      width: 196,
                      child: AspectRatio(
                        aspectRatio: 1080 / 2246,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: scheme.outline.withValues(alpha: 0.45),
                              width: 2.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.20),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _InteractiveGuideScreenshot(
                            imageAsset: topic.imageAsset,
                            pins: topic.pins,
                            selectedPinIndex: _selectedPinIndex,
                            showPins: _showPins,
                            pulseAnimation: _pulseController,
                            onPinTapped: _selectPin,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _openFullscreenViewer,
                    icon: const Icon(Icons.zoom_in_rounded, size: 17),
                    label: const Text(
                      'Perbesar Layar Penuh (Zoom)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),

                  // Active Pin Spotlight integrated directly underneath the phone!
                  if (activePin != null) ...[
                    const SizedBox(height: 6),
                    _buildActivePinSpotlight(context, scheme, topic, activePin),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),

            // 4. Complete List of All Numbered Pins
            Row(
              children: [
                Icon(
                  Icons.format_list_numbered_rounded,
                  size: 20,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Daftar Lengkap Elemen & Fungsi (${topic.pins.length} Titik)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            ...List.generate(topic.pins.length, (idx) {
              final pin = topic.pins[idx];
              final isSelected = idx == _selectedPinIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _selectPin(idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? pin.color.withValues(alpha: 0.10)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? pin.color
                            : scheme.outlineVariant.withValues(alpha: 0.4),
                        width: isSelected ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: pin.color,
                            shape: BoxShape.circle,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: pin.color.withValues(alpha: 0.4),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '${pin.number}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      pin.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: pin.color,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Disorot',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                pin.description,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                              ),
                              if (pin.tip != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.lightbulb_outline_rounded,
                                        size: 15,
                                        color: pin.color,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          pin.tip!,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 14),

            // 5. Previous / Next Chapter Navigation Bar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _topicIndex > 0
                        ? () => _switchTopic(_topicIndex - 1)
                        : null,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(
                      _topicIndex > 0
                          ? widget.topics[_topicIndex - 1].title
                          : 'Bab Awal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _topicIndex < widget.topics.length - 1
                        ? () => _switchTopic(_topicIndex + 1)
                        : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(
                      _topicIndex < widget.topics.length - 1
                          ? widget.topics[_topicIndex + 1].title
                          : 'Bab Akhir',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivePinSpotlight(
    BuildContext context,
    ColorScheme scheme,
    GuideTopic topic,
    GuidePin activePin,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: activePin.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: activePin.color.withValues(alpha: 0.65),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: activePin.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Titik #${activePin.number} dari ${topic.pins.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Titik Sebelumnya',
                onPressed: _selectedPinIndex > 0
                    ? () => _selectPin(_selectedPinIndex - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                tooltip: 'Titik Berikutnya',
                onPressed: _selectedPinIndex < topic.pins.length - 1
                    ? () => _selectPin(_selectedPinIndex + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            activePin.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            activePin.description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurface,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE VECTOR PIN & ARROW SCREENSHOT WIDGET
// =============================================================================

class _InteractiveGuideScreenshot extends StatelessWidget {
  final String imageAsset;
  final List<GuidePin> pins;
  final int selectedPinIndex;
  final bool showPins;
  final Animation<double> pulseAnimation;
  final ValueChanged<int> onPinTapped;

  const _InteractiveGuideScreenshot({
    required this.imageAsset,
    required this.pins,
    required this.selectedPinIndex,
    required this.showPins,
    required this.pulseAnimation,
    required this.onPinTapped,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final scaleX = w / UserGuideRepository.referenceCanvasSize.width;
        final scaleY = h / UserGuideRepository.referenceCanvasSize.height;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (!showPins || pins.isEmpty) return;
            final localPos = details.localPosition;
            int? bestIdx;
            double bestDist = 36.0; // Hit radius in logical pixels

            for (var i = 0; i < pins.length; i++) {
              final p = pins[i];
              final dotPx = Offset(p.dotPos.dx * scaleX, p.dotPos.dy * scaleY);
              final targetPx = Offset(
                p.targetPos.dx * scaleX,
                p.targetPos.dy * scaleY,
              );
              final dDot = (localPos - dotPx).distance;
              final dTarget = (localPos - targetPx).distance;
              final minD = math.min(dDot, dTarget);
              if (minD < bestDist) {
                bestDist = minD;
                bestIdx = i;
              }
            }
            if (bestIdx != null) {
              onPinTapped(bestIdx);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(imageAsset, fit: BoxFit.fill),
              if (showPins)
                AnimatedBuilder(
                  animation: pulseAnimation,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _GuidePinOverlayPainter(
                        pins: pins,
                        selectedPinIndex: selectedPinIndex,
                        pulseValue: pulseAnimation.value,
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GuidePinOverlayPainter extends CustomPainter {
  final List<GuidePin> pins;
  final int selectedPinIndex;
  final double pulseValue;

  const _GuidePinOverlayPainter({
    required this.pins,
    required this.selectedPinIndex,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / UserGuideRepository.referenceCanvasSize.width;
    final scaleY = size.height / UserGuideRepository.referenceCanvasSize.height;

    // Draw non-selected pins first, then selected pin on top
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < pins.length; i++) {
        final isSelected = i == selectedPinIndex;
        if ((pass == 0 && isSelected) || (pass == 1 && !isSelected)) {
          continue;
        }
        _drawPin(
          canvas,
          pins[i],
          scaleX: scaleX,
          scaleY: scaleY,
          isSelected: isSelected,
        );
      }
    }
  }

  void _drawPin(
    Canvas canvas,
    GuidePin pin, {
    required double scaleX,
    required double scaleY,
    required bool isSelected,
  }) {
    final dot = Offset(pin.dotPos.dx * scaleX, pin.dotPos.dy * scaleY);
    final target = Offset(pin.targetPos.dx * scaleX, pin.targetPos.dy * scaleY);
    final baseRadius = (26.0 * scaleX).clamp(8.5, 16.0);
    final r = isSelected ? baseRadius * 1.15 : baseRadius;

    final vec = target - dot;
    final dist = vec.distance;

    // 1. Draw Arrow Shaft & Head
    if (dist > r + 2) {
      final unit = vec / dist;
      final start = dot + unit * (r + 1.5);

      // White halo shaft
      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: isSelected ? 0.98 : 0.88)
        ..strokeWidth = isSelected ? 3.8 : 2.8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, target, haloPaint);

      // Colored shaft
      final shaftPaint = Paint()
        ..color = pin.color
        ..strokeWidth = isSelected ? 2.3 : 1.7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(start, target, shaftPaint);

      // Arrowhead
      final headLen = isSelected ? 7.5 : 6.0;
      final headAngle = 28 * math.pi / 180;
      final angle = math.atan2(vec.dy, vec.dx);

      final p1 = Offset(
        target.dx - headLen * math.cos(angle - headAngle),
        target.dy - headLen * math.sin(angle - headAngle),
      );
      final p2 = Offset(
        target.dx - headLen * math.cos(angle + headAngle),
        target.dy - headLen * math.sin(angle + headAngle),
      );

      final headPath = Path()
        ..moveTo(target.dx, target.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();

      canvas.drawPath(
        headPath,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..color = pin.color
          ..style = PaintingStyle.fill,
      );
    }

    // 2. Pulse Ring if selected
    if (isSelected) {
      final pulseRadius = r + 3.0 + (pulseValue * 5.5);
      final pulsePaint = Paint()
        ..color = pin.color.withValues(alpha: (1.0 - pulseValue) * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(dot, pulseRadius, pulsePaint);

      // Subtle target spotlight dot
      canvas.drawCircle(
        target,
        3.0 + pulseValue * 3.0,
        Paint()
          ..color = pin.color.withValues(alpha: (1.0 - pulseValue) * 0.5)
          ..style = PaintingStyle.fill,
      );
    }

    // 3. Shadow + White Ring + Colored Circle
    canvas.drawCircle(
      dot + const Offset(0.8, 1.5),
      r + 1.0,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      dot,
      r + (isSelected ? 2.0 : 1.4),
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(dot, r, Paint()..color = pin.color);

    // 4. Number Label
    final tp = TextPainter(
      text: TextSpan(
        text: '${pin.number}',
        style: TextStyle(
          color: Colors.white,
          fontSize: r * 1.12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, dot - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _GuidePinOverlayPainter oldDelegate) {
    return oldDelegate.selectedPinIndex != selectedPinIndex ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.pins != pins;
  }
}

// =============================================================================
// FULLSCREEN ZOOMABLE GUIDE DIALOG
// =============================================================================

class _FullscreenGuideImageDialog extends StatefulWidget {
  final GuideTopic topic;
  final int initialSelectedPinIndex;
  final ValueChanged<int> onPinSelected;

  const _FullscreenGuideImageDialog({
    required this.topic,
    required this.initialSelectedPinIndex,
    required this.onPinSelected,
  });

  @override
  State<_FullscreenGuideImageDialog> createState() =>
      _FullscreenGuideImageDialogState();
}

class _FullscreenGuideImageDialogState
    extends State<_FullscreenGuideImageDialog>
    with SingleTickerProviderStateMixin {
  late int _selectedIdx;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _selectedIdx = widget.initialSelectedPinIndex;
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.topic.pins[_selectedIdx];
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.topic.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Zoomable interactive image
            Expanded(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1080 / 2246,
                    child: _InteractiveGuideScreenshot(
                      imageAsset: widget.topic.imageAsset,
                      pins: widget.topic.pins,
                      selectedPinIndex: _selectedIdx,
                      showPins: true,
                      pulseAnimation: _pulse,
                      onPinTapped: (idx) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedIdx = idx);
                        widget.onPinSelected(idx);
                      },
                    ),
                  ),
                ),
              ),
            ),

            // Bottom active pin caption bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: Colors.grey.shade900,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: pin.color,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${pin.number}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pin.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pin.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
