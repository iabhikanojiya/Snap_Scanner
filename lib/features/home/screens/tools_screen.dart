import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/blue_header.dart';
import '../../../core/widgets/glass_bottom_nav.dart';
import '../../../core/widgets/native_ad_widget.dart';
import '../tool_actions.dart';
import '../widgets/tool_card.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim().toLowerCase();

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchController.clear();
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
    }
  }

  /// Cards whose title or description contains every word of the query.
  List<ToolCard> _filter(List<ToolCard> cards) {
    final words = _query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return cards;
    return cards.where((card) {
      final text = '${card.title} ${card.description}'.toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search tools',
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 19),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// Banner stays mounted while searching (just hidden), so a loaded ad
  /// isn't thrown away and reloaded afterwards. Always built here so every
  /// placement produces the same keyed subtree.
  Widget _buildBanner({required bool visible}) {
    return Visibility(
      key: const ValueKey('tools_banner'),
      visible: visible,
      maintainState: true,
      child: const Padding(
        padding: EdgeInsets.only(top: 16),
        child: BannerAdWidget(compact: true),
      ),
    );
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 56, 32, 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: const BoxDecoration(color: Color(0xFFF1F2F4), shape: BoxShape.circle),
            child: const Icon(Icons.search_off_rounded, size: 44, color: Color(0xFFA0A6B1)),
          ),
          const SizedBox(height: 18),
          const Text(
            'No tools found',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different word, like "sign" or "merge"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
  Widget _sectionHeader(String label, {double topPadding = 24}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 12),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _toolGrid(List<ToolCard> cards) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 ? 4 : 2;
          const spacing = 12.0;
          final rows = <Widget>[];
          for (var i = 0; i < cards.length; i += columns) {
            final rowCards = cards.skip(i).take(columns).toList();
            rows.add(Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : spacing),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      Expanded(
                        child: j < rowCards.length
                            ? rowCards[j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ));
          }
          return Column(children: rows);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final create = _filter([
      ToolCard(
        title: 'Scan PDF',
        description: 'Scan documents with your camera',
        icon: Icons.document_scanner_outlined,
        color: AppColors.toolScan,
        onTap: () => ToolActions.openScanner(context),
      ),
      ToolCard(
        title: 'Image to PDF',
        description: 'Convert images to PDF documents',
        icon: Icons.image_outlined,
        color: AppColors.toolImageToPdf,
        onTap: () => ToolActions.pickImages(context),
      ),
    ]);
    final documentTools = _filter([
      ToolCard(
        title: 'Merge PDF',
        description: 'Combine multiple PDFs',
        icon: Icons.merge_type_rounded,
        color: AppColors.toolMerge,
        onTap: () => ToolActions.openMerge(context),
      ),
      ToolCard(
        title: 'Split PDF',
        description: 'Extract pages from a PDF',
        icon: Icons.call_split_rounded,
        color: AppColors.toolSplit,
        onTap: () => ToolActions.openSplit(context),
      ),
      ToolCard(
        title: 'Compress PDF',
        description: 'Reduce PDF file size',
        icon: Icons.compress_rounded,
        color: AppColors.toolCompress,
        onTap: () => ToolActions.openCompress(context),
      ),
      ToolCard(
        title: 'Lock PDF',
        description: 'Protect with a password',
        icon: Icons.lock_outline_rounded,
        color: AppColors.toolLock,
        onTap: () => ToolActions.openLock(context),
      ),
    ]);
    final annotate = _filter([
      ToolCard(
        title: 'Signature',
        description: 'Sign your PDF documents',
        icon: Icons.draw_outlined,
        color: AppColors.toolSignature,
        onTap: () => ToolActions.openSignature(context),
      ),
      ToolCard(
        title: 'Resize Image',
        description: 'Change image dimensions',
        icon: Icons.photo_size_select_large_rounded,
        color: AppColors.toolResize,
        onTap: () => ToolActions.openResizeImage(context),
      ),
    ]);

    final searching = _query.isNotEmpty;
    final sections = <(String, List<ToolCard>)>[
      ('CREATE', create),
      ('DOCUMENT TOOLS', documentTools),
      ('ANNOTATE', annotate),
    ].where((section) => section.$2.isNotEmpty).toList();

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          BlueHeader(
            title: 'Tools',
            subtitle: _searchOpen ? null : 'All your PDF utilities in one place',
            actions: [
              HeaderIconButton(
                icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searchOpen ? 'Close search' : 'Search',
                active: _searchOpen,
                onPressed: _toggleSearch,
              ),
            ],
            bottom: _searchOpen ? _buildSearchField() : null,
          ),
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: GlassBottomNav.clearance(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sections.isEmpty) ...[
                    _buildNoResults(),
                    _buildBanner(visible: false),
                  ],
                  for (var i = 0; i < sections.length; i++) ...[
                    _sectionHeader(sections[i].$1, topPadding: i == 0 ? 20 : 24),
                    _toolGrid(sections[i].$2),
                    if (i == 0) _buildBanner(visible: !searching),
                  ],
                  Visibility(
                    key: const ValueKey('tools_native_ad'),
                    visible: !searching,
                    maintainState: true,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: NativeAdWidget(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
