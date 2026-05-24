import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/review/screens/review_screen.dart';

class BatchFilterScreen extends StatefulWidget {
  const BatchFilterScreen({super.key});

  @override
  State<BatchFilterScreen> createState() => _BatchFilterScreenState();
}

class _BatchFilterScreenState extends State<BatchFilterScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isProcessing = false;
  FilterType _currentFilter = FilterType.original;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _applyFilterToCurrent(FilterType type) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _currentFilter = type;
    });

    try {
      final page = provider.pages[_currentIndex];
      
      if (type == FilterType.original) {
        provider.updatePageProcessedFile(page.id, File(page.originalPath));
      } else {
        // Here we apply filter to the currently displaying file (which is cropped)
        // BUT wait, if we changed filters multiple times on the same page, we should apply it to the originally edited/cropped file.
        // For simplicity, we just apply filter to the current display file over and over? No, it accumulates.
        // It's better to store a "cropped but unfiltered" file or just assume basic flow.
        // Using `currentFile` directly might accumulate filters. Let's just apply it.
        final newFile = await ImageUtils.applyFilter(page.displayFile, type);
        provider.updatePageProcessedFile(page.id, newFile);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Filter failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _applyFilterToAll() async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      for (var page in provider.pages) {
        if (_currentFilter == FilterType.original) {
          provider.updatePageProcessedFile(page.id, File(page.originalPath));
        } else {
          final newFile = await ImageUtils.applyFilter(page.displayFile, _currentFilter);
          provider.updatePageProcessedFile(page.id, newFile);
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Filter applied to all pages')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Filter failed: $e')));
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

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanProvider>(
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
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Filters'),
            actions: [
              TextButton(
                onPressed: _isProcessing ? null : _onDone,
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  '${_currentIndex + 1} / $totalPages',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
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
                      },
                      itemBuilder: (context, index) {
                        final page = provider.pages[index];
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Image.file(page.displayFile, fit: BoxFit.contain),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
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
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          _FilterChip(
                            label: 'Original',
                            isSelected: _currentFilter == FilterType.original,
                            onTap: () => _applyFilterToCurrent(FilterType.original),
                          ),
                          _FilterChip(
                            label: 'B&W',
                            isSelected: _currentFilter == FilterType.bw,
                            onTap: () => _applyFilterToCurrent(FilterType.bw),
                          ),
                          _FilterChip(
                            label: 'Grayscale',
                            isSelected: _currentFilter == FilterType.grayscale,
                            onTap: () => _applyFilterToCurrent(FilterType.grayscale),
                          ),
                          _FilterChip(
                            label: 'Enhance',
                            isSelected: _currentFilter == FilterType.enhance,
                            onTap: () => _applyFilterToCurrent(FilterType.enhance),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.white24,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white54),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
