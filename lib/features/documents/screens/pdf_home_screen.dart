import 'package:flutter/material.dart';

import '../../../core/models/folder_model.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/folder_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/blue_header.dart';
import '../../../core/widgets/glass_bottom_nav.dart';
import '../../home/tool_actions.dart';
import '../pdf_file_actions.dart';
import '../widgets/folder_card.dart';
import '../widgets/folder_picker_sheet.dart';
import '../widgets/pdf_list_item.dart';
import 'folder_detail_screen.dart';
import '../../../core/widgets/app_dialog.dart';

enum PdfSort { newest, oldest, nameAsc, nameDesc, largest }

extension on PdfSort {
  String get label {
    switch (this) {
      case PdfSort.newest:
        return 'Newest first';
      case PdfSort.oldest:
        return 'Oldest first';
      case PdfSort.nameAsc:
        return 'Name (A–Z)';
      case PdfSort.nameDesc:
        return 'Name (Z–A)';
      case PdfSort.largest:
        return 'Largest first';
    }
  }
}

/// The "PDF" tab: My PDFs (same data and filters as History) and Folders.
class PdfHomeScreen extends StatefulWidget {
  const PdfHomeScreen({super.key});

  @override
  State<PdfHomeScreen> createState() => PdfHomeScreenState();
}

class PdfHomeScreenState extends State<PdfHomeScreen> with RouteAware {
  List<PdfFileModel> _files = [];
  List<FolderModel> _folders = [];
  bool _isLoading = true;
  int _section = 0; // 0 = My PDFs, 1 = Folders
  String _selectedFilter = 'all';
  PdfSort _sort = PdfSort.newest;
  bool _searchOpen = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Returning from any tool/success screen: pick up new or changed files.
  @override
  void didPopNext() => _loadAll();

  Future<void> _loadAll() async {
    try {
      final results = await Future.wait([
        DatabaseService.getAllFiles(),
        FolderService.getFolders(),
      ]);
      if (!mounted) return;
      setState(() {
        _files = results[0] as List<PdfFileModel>;
        _folders = results[1] as List<FolderModel>;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[PdfHome] load failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _query => _searchController.text.trim().toLowerCase();

  List<PdfFileModel> get _visibleFiles {
    var files = _files;
    if (_selectedFilter != 'all') {
      files = files.where((f) => f.toolType == _selectedFilter).toList();
    }
    final query = _query;
    if (query.isNotEmpty) {
      files = files.where((f) => f.name.toLowerCase().contains(query)).toList();
    }
    final sorted = List<PdfFileModel>.of(files);
    switch (_sort) {
      case PdfSort.newest:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case PdfSort.oldest:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case PdfSort.nameAsc:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case PdfSort.nameDesc:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case PdfSort.largest:
        sorted.sort((a, b) => b.size.compareTo(a.size));
    }
    return sorted;
  }

  List<FolderModel> get _visibleFolders {
    final query = _query;
    if (query.isEmpty) return _folders;
    return _folders.where((f) => f.name.toLowerCase().contains(query)).toList();
  }

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

  void _showSortOptions() {
    showAppDialog(
      context: context,
      builder: (sheetContext) => AppDialog(
        title: 'Sort by',
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(sheetContext),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in PdfSort.values)
              AppDialogOption(
                label: option.label,
                selected: option == _sort,
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _sort = option);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFileActions(PdfFileModel file) async {
    var inFolder = false;
    try {
      inFolder = await FolderService.isFileInAnyFolder(file.id);
    } catch (e) {
      debugPrint('[PdfHome] folder lookup failed: $e');
    }
    if (!mounted) return;
    PdfFileActions.showFileActions(
      context,
      file,
      onChanged: _loadAll,
      extraActions: [
        if (inFolder)
          PdfFileExtraAction(
            icon: Icons.drive_file_move_outline,
            label: 'Move to folder',
            onTap: () => showFolderPicker(context, file: file, move: true, onDone: _loadAll),
          )
        else
          PdfFileExtraAction(
            icon: Icons.create_new_folder_outlined,
            label: 'Add to folder',
            onTap: () => showFolderPicker(context, file: file, move: false, onDone: _loadAll),
          ),
      ],
    );
  }

  Future<void> _createFolder() async {
    final folder = await showCreateFolderDialog(context);
    if (folder != null) _loadAll();
  }

  Future<void> _openFolder(FolderModel? folder) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FolderDetailScreen(folder: folder)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          BlueHeader(
            title: 'Snap Scanner',
            actions: [
              HeaderIconButton(
                icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                tooltip: _searchOpen ? 'Close search' : 'Search',
                active: _searchOpen,
                onPressed: _toggleSearch,
              ),
              HeaderIconButton(
                icon: Icons.sort_rounded,
                tooltip: 'Sort',
                onPressed: _showSortOptions,
              ),
            ],
            bottom: Column(
              children: [
                if (_searchOpen) ...[
                  _buildSearchField(),
                  const SizedBox(height: 12),
                ],
                _buildSectionSwitcher(),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _section,
              children: [
                _buildMyPdfs(),
                _buildFolders(),
              ],
            ),
          ),
        ],
      ),
    );
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
          hintText: _section == 0 ? 'Search PDFs' : 'Search folders',
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

  Widget _buildSectionSwitcher() {
    Widget segment(int index, String label) {
      final selected = _section == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _section = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.brandRed : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          segment(0, 'My PDFs'),
          segment(1, 'Folders'),
        ],
      ),
    );
  }

  Widget _buildFab({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.extended(
      heroTag: null,
      onPressed: onPressed,
      backgroundColor: AppColors.textPrimary,
      foregroundColor: Colors.white,
      elevation: 3,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  // ---------------------------------------------------------------- My PDFs

  Widget _buildMyPdfs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: PdfFileActions.filterOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final label = PdfFileActions.filterOptions[index].$1;
              final value = PdfFileActions.filterOptions[index].$2;
              final isSelected = _selectedFilter == value;
              return GestureDetector(
                onTap: () => setState(() => _selectedFilter = value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.brandRed : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? AppColors.brandRed : const Color(0xFF4B5563),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: _buildPdfListBody()),
              Positioned(
                right: 20,
                bottom: 12,
                child: _buildFab(
                  icon: Icons.document_scanner_outlined,
                  label: 'Scan PDF',
                  onPressed: () => ToolActions.openScanner(context),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: BannerAdWidget(compact: true),
        ),
        SizedBox(height: GlassBottomNav.clearance(context)),
      ],
    );
  }

  Widget _buildPdfListBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_files.isEmpty) {
      return _buildEmptyState(
        icon: Icons.picture_as_pdf_outlined,
        title: 'No PDFs yet',
        message: 'Tap Scan PDF to create your first document',
      );
    }
    final files = _visibleFiles;
    if (files.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off,
        title: 'No matching files',
        message: 'Try a different search or filter',
      );
    }
    return ListView.builder(
      key: const PageStorageKey('my_pdfs_list'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 88),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return PdfListItem(
          key: ValueKey(file.id),
          file: file,
          onTap: () => _showFileActions(file),
        );
      },
    );
  }

  // ---------------------------------------------------------------- Folders

  Widget _buildFolders() {
    final folders = _visibleFolders;
    final showAll = _query.isEmpty;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (folders.isEmpty && !showAll)
                        ? _buildEmptyState(
                            icon: Icons.search_off,
                            title: 'No matching folders',
                            message: 'Try a different search',
                          )
                        : ListView(
                            key: const PageStorageKey('folders_list'),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 88),
                            children: [
                              if (showAll)
                                FolderCard(
                                  name: 'All PDFs',
                                  fileCount: _files.length,
                                  icon: Icons.folder_copy_rounded,
                                  onTap: () => _openFolder(null),
                                ),
                              for (final folder in folders)
                                FolderCard(
                                  key: ValueKey(folder.id),
                                  name: folder.name,
                                  fileCount: folder.fileCount,
                                  onTap: () => _openFolder(folder),
                                ),
                            ],
                          ),
              ),
              Positioned(
                right: 20,
                bottom: 12,
                child: _buildFab(
                  icon: Icons.create_new_folder_outlined,
                  label: 'Create Folder',
                  onPressed: _createFolder,
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: BannerAdWidget(compact: true),
        ),
        SizedBox(height: GlassBottomNav.clearance(context)),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 88),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F2F4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: Color(0xFFA0A6B1)),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
