import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../documents/pdf_file_actions.dart';

class HistoryScreen extends StatefulWidget {
  /// Reserve space for the floating bottom nav (false when pushed as a page).
  final bool reserveBottomNavSpace;

  const HistoryScreen({super.key, this.reserveBottomNavSpace = true});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<PdfFileModel> _recentFiles = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  final _searchController = TextEditingController();

  static const _filterOptions = PdfFileActions.filterOptions;

  List<PdfFileModel> get _filteredFiles {
    var files = _recentFiles;
    if (_selectedFilter != 'all') {
      files = files.where((f) => f.toolType == _selectedFilter).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      files = files.where((f) => f.name.toLowerCase().contains(query)).toList();
    }
    return files;
  }

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentFiles() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final files = await DatabaseService.getAllFiles();
    if (mounted) {
      setState(() {
        _recentFiles = files;
        _isLoading = false;
      });
    }
  }

  void reload() {
    _loadRecentFiles();
  }

  void _showFileActions(PdfFileModel file) {
    PdfFileActions.showFileActions(context, file, onChanged: _loadRecentFiles);
  }

  double _bottomNavClearance(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const navBarHeight = 65.0;
    const desiredGap = 10.0;
    final navPosition = bottomPadding > 0 ? bottomPadding.toDouble() : 24.0;
    return navPosition + navBarHeight + desiredGap;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'History',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recently created and modified files',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _filterOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final label = _filterOptions[index].$1;
                final value = _filterOptions[index].$2;
                final isSelected = _selectedFilter == value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueAccent : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.blueAccent : Colors.grey.shade200,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recentFiles.isEmpty
                    ? _buildEmptyState()
                    : _filteredFiles.isEmpty
                        ? _buildNoResultsState()
                        : _buildRecentFilesList(),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: BannerAdWidget(),
          ),
          SizedBox(
            height: widget.reserveBottomNavSpace
                ? _bottomNavClearance(context)
                : MediaQuery.paddingOf(context).bottom + 8,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history, size: 56, color: Colors.blueAccent),
          ),
          const SizedBox(height: 24),
          Text(
            'No files yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your created PDFs will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_off, size: 48, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Text(
            'No matching files',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search or filter',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFilesList() {
    final files = _filteredFiles;
    const adInterval = 3;
    final adCount = files.length ~/ adInterval;
    final itemCount = files.length + adCount;
    return ListView.builder(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if ((index + 1) % (adInterval + 1) == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: BannerAdWidget(),
          );
        }
        final fileIndex = index - (index ~/ (adInterval + 1));
        final file = files[fileIndex];
        final isImage = file.toolType == 'resize_image';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _showFileActions(file),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isImage
                            ? Colors.pink.withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isImage ? Icons.image : Icons.picture_as_pdf,
                        color: isImage ? Colors.pink : Colors.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            PdfFileActions.formatToolType(file.toolType),
                            style: TextStyle(color: Colors.blueAccent.shade400, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${PdfFileActions.formatSize(file.size)} • ${DateFormat('MMM dd, yyyy').format(file.createdAt)}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
