import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/review/screens/review_screen.dart';
import 'package:snap_scanner/core/widgets/banner_ad_widget.dart';
import 'package:snap_scanner/core/models/scanned_page.dart';
import 'package:snap_scanner/core/theme/app_colors.dart';
import '../widgets/page_counter.dart';

class BatchFilterScreen extends StatefulWidget {
  /// Page to show first, so it matches the page the user was on in Crop.
  final int initialIndex;

  const BatchFilterScreen({super.key, this.initialIndex = 0});

  @override
  State<BatchFilterScreen> createState() => _BatchFilterScreenState();
}

class _BatchFilterScreenState extends State<BatchFilterScreen> {
  /// Picker order: Enhance first (applied by default), then Original.
  static const List<(FilterType, String)> _filters = [
    (FilterType.enhance, 'Enhance'),
    (FilterType.original, 'Original'),
    (FilterType.magicColor, 'Magic Color'),
    (FilterType.sharpen, 'Sharpen'),
    (FilterType.bright, 'Bright'),
    (FilterType.grayscale, 'Grayscale'),
    (FilterType.bw, 'B&W'),
    (FilterType.sepia, 'Sepia'),
  ];
  static const FilterType _defaultFilter = FilterType.enhance;

  late PageController _pageController;
  int _currentIndex = 0;
  bool _isProcessing = false;

  /// Unfiltered (cropped) image per page id, so filters never stack and
  /// "Original" returns to the cropped image.
  final Map<String, File> _baseFiles = {};

  /// Filter currently applied to each page id.
  final Map<String, FilterType> _pageFilters = {};

  /// Filter thumbnails per page id.
  final Map<String, Map<FilterType, Uint8List>> _previews = {};

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<ScanProvider>(context, listen: false);
    _currentIndex = provider.pages.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, provider.pages.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    for (final page in provider.pages) {
      _baseFiles[page.id] = page.displayFile;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreviews(_currentIndex);
      _applyDefaultFilter();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  FilterType get _currentFilter {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty || _currentIndex >= provider.pages.length) {
      return _defaultFilter;
    }
    return _pageFilters[provider.pages[_currentIndex].id] ?? FilterType.original;
  }

  File _baseFor(ScannedPage page) =>
      _baseFiles.putIfAbsent(page.id, () => page.displayFile);

  Future<void> _applyToPage(ScannedPage page, FilterType type, ScanProvider provider) async {
    final base = _baseFor(page);
    final file = type == FilterType.original ? base : await ImageUtils.applyFilter(base, type);
    provider.updatePageProcessedFile(page.id, file);
    _pageFilters[page.id] = type;
  }

  Future<void> _loadPreviews(int index) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (index >= provider.pages.length) return;
    final page = provider.pages[index];
    if (_previews.containsKey(page.id)) return;
    try {
      final previews = await ImageUtils.buildFilterPreviews(
        _baseFor(page),
        [for (final f in _filters) f.$1],
      );
      if (mounted) setState(() => _previews[page.id] = previews);
    } catch (e) {
      debugPrint('Filter previews failed: $e');
    }
  }

  /// Applies Enhance to every page when the screen opens.
  Future<void> _applyDefaultFilter() async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      for (final page in List.of(provider.pages)) {
        await _applyToPage(page, _defaultFilter, provider);
      }
    } catch (e) {
      debugPrint('Default filter failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyFilterToCurrent(FilterType type) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) return;

    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    try {
      final page = provider.pages[_currentIndex];
      await _applyToPage(page, type, provider);
    } catch (e) {
      debugPrint('Filter failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply filter. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyFilterToAll() async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) return;

    if (_isProcessing) return;
    final type = _currentFilter;
    setState(() {
      _isProcessing = true;
    });

    try {
      for (var page in List.of(provider.pages)) {
        await _applyToPage(page, type, provider);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Filter applied to all pages')),
        );
      }
    } catch (e) {
      debugPrint('Apply all filter failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not apply filter to all pages. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _onDone() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ReviewScreen()),
    );
  }

  /// Going back to crop: drop filters so re-entering starts from the
  /// unfiltered image instead of filtering an already-filtered one.
  void _restoreBaseFiles() {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    for (final page in provider.pages) {
      final base = _baseFiles[page.id];
      if (base != null) provider.updatePageProcessedFile(page.id, base);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _restoreBaseFiles();
      },
      child: Consumer<ScanProvider>(
      builder: (context, provider, child) {
        if (provider.pages.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text("No images", style: TextStyle(color: Colors.white))),
          );
        }

        final totalPages = provider.pages.length;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            leading: BackButton(
              color: Colors.white,
              // Return the current page so Crop reopens on the same page.
              onPressed: () => Navigator.pop(context, _currentIndex),
            ),
            title: PageCounter(current: _currentIndex + 1, total: totalPages),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: _isProcessing ? null : _onDone,
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: totalPages,
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                        });
                        _loadPreviews(index);
                      },
                      itemBuilder: (context, index) {
                        final page = provider.pages[index];
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          // Decoded at screen width, not the photo's full
                          // resolution (display only; filters use the file).
                          child: Image.file(
                            page.displayFile,
                            fit: BoxFit.contain,
                            cacheWidth: (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          ),
                        );
                      },
                    ),
                    if (_isProcessing)
                      Container(
                        color: Colors.black54,
                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                      ),
                  ],
                ),
              ),
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _applyFilterToAll,
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Apply to All'),
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.black,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 104,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filters.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final (type, label) = _filters[i];
                          final pageId = provider.pages[_currentIndex].id;
                          return _FilterPreview(
                            label: label,
                            preview: _previews[pageId]?[type],
                            isSelected: _currentFilter == type,
                            onTap: _isProcessing ? null : () => _applyFilterToCurrent(type),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SafeArea(
                  top: false,
                  child: const BannerAdWidget(compact: true),
                ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }
}

class _FilterPreview extends StatelessWidget {
  final String label;
  final Uint8List? preview;
  final bool isSelected;
  final VoidCallback? onTap;

  const _FilterPreview({
    required this.label,
    required this.preview,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 66,
              height: 78,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.brandRed : Colors.white24,
                  width: isSelected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: preview != null
                    ? Image.memory(preview!, fit: BoxFit.cover, gaplessPlayback: true)
                    : const ColoredBox(
                        color: Colors.white10,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
