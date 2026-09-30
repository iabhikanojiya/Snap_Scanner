import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tool_ui.dart';
import '../../compress/screens/pdf_compress_screen.dart';
import '../../home/tool_actions.dart';
import '../../lock/screens/pdf_lock_screen.dart';
import '../services/pdf_annotate_service.dart';
import '../widgets/pdf_pages.dart';
import '../widgets/pdf_tool_capsule.dart';
import 'pdf_highlight_screen.dart';

/// Reader for PDFs opened in Snap Scanner (from My PDFs or other apps):
/// black top bar (back, name, search, share, download), zoomable pages and
/// a docked tool capsule.
class PdfViewerScreen extends StatefulWidget {
  final String path;

  const PdfViewerScreen({super.key, required this.path});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfPageSource? _source;
  Object? _error;
  final ScrollController _scroll = ScrollController();
  PdfPagesLayout? _layout;
  int _currentPage = 0;

  // Search
  bool _searchOpen = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PdfTextMatch> _matches = const [];
  int _matchIndex = 0;
  bool _searching = false;
  String _searchedFor = '';

  String get _fileName => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    PdfPageSource.open(widget.path).then((source) {
      if (!mounted) {
        source.dispose();
        return;
      }
      setState(() => _source = source);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _source?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final page = layout.pageAt(_scroll.offset, _scroll.position.viewportDimension);
    if (page != _currentPage) setState(() => _currentPage = page);
  }

  void _scrollToPage(int index, {double withinPage = 0}) {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final target = layout.offsetOf(index) + withinPage * layout.pageHeight(index) - 80;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(widget.path)]));
    } catch (_) {
      _snack('Could not open share sheet');
    }
  }

  Future<void> _download() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final out = await FilePicker.saveFile(
        dialogTitle: 'Download PDF',
        fileName: _fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );
      if (out != null) _snack('File downloaded successfully!');
    } catch (e) {
      debugPrint('[Viewer] download failed: $e');
      _snack('Could not download the file. Please try again.');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Capsule actions: entry points to the existing tools, all on this PDF.
  /// The tools save their result as a new PDF, so this file (and the
  /// viewer's state) is unchanged when the user comes back.
  void _openTool(void Function() open) {
    if (_searchOpen) _closeSearch();
    open();
  }

  // ---------------------------------------------------------------- search

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searchOpen = false;
      _searchController.clear();
      _matches = const [];
      _searchedFor = '';
    });
  }

  Future<void> _runSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final matches = await PdfAnnotateService.findText(widget.path, query);
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _matchIndex = 0;
        _searchedFor = query;
      });
      if (matches.isNotEmpty) {
        _scrollToPage(matches.first.pageIndex, withinPage: matches.first.rect.top);
      }
    } catch (e) {
      debugPrint('[Viewer] search failed: $e');
      _snack("Couldn't search this PDF");
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _matchIndex = (_matchIndex + delta) % _matches.length);
    final m = _matches[_matchIndex];
    _scrollToPage(m.pageIndex, withinPage: m.rect.top);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF2A2C31),
        appBar: _appBar(source != null),
        body: _error != null
            ? _buildError()
            : source == null
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _buildReader(source),
        bottomNavigationBar: source == null ? null : _buildCapsuleBar(),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool loaded) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      elevation: 0,
      titleSpacing: 0,
      title: _searchOpen
          ? TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                hintText: 'Search in PDF',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
            )
          : Text(
              _fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
      actions: _searchOpen
          ? [
              if (_searching)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              else if (_searchedFor.isNotEmpty)
                Center(
                  child: Text(
                    _matches.isEmpty ? '0' : '${_matchIndex + 1}/${_matches.length}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              IconButton(
                tooltip: 'Previous match',
                onPressed: _matches.isEmpty ? null : () => _stepMatch(-1),
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                color: Colors.white,
                disabledColor: Colors.white30,
              ),
              IconButton(
                tooltip: 'Next match',
                onPressed: _matches.isEmpty ? null : () => _stepMatch(1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: Colors.white,
                disabledColor: Colors.white30,
              ),
              IconButton(
                tooltip: 'Close search',
                onPressed: _closeSearch,
                icon: const Icon(Icons.close_rounded),
              ),
            ]
          : [
              IconButton(
                tooltip: 'Search',
                onPressed: loaded ? _openSearch : null,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Share',
                onPressed: _share,
                icon: const Icon(Icons.share_rounded),
              ),
              IconButton(
                tooltip: 'Download',
                onPressed: _download,
                icon: const Icon(Icons.download_rounded),
              ),
            ],
    );
  }

  Widget _buildReader(PdfPageSource source) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final layout = _layout = PdfPagesLayout(source.sizes, constraints.maxWidth);
            final renderWidth = layout.renderWidth(context);
            return InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  PdfPagesLayout.side,
                  PdfPagesLayout.gap,
                  PdfPagesLayout.side,
                  PdfPagesLayout.gap,
                ),
                itemCount: source.pageCount,
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.only(bottom: index == source.pageCount - 1 ? 0 : PdfPagesLayout.gap),
                  child: PdfPageTile(
                    image: source.render(index, renderWidth),
                    aspectRatio: source.sizes[index].width / source.sizes[index].height,
                    matches: [
                      for (var i = 0; i < _matches.length; i++)
                        if (_matches[i].pageIndex == index) (_matches[i].rect, i == _matchIndex),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: _Pill('${_currentPage + 1} / ${source.pageCount}'),
          ),
        ),
        if (_searchOpen && _searchedFor.isNotEmpty && _matches.isEmpty && !_searching)
          Positioned(
            top: 52,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  'No results for "$_searchedFor"',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCapsuleBar() {
    final itemWidth = PdfToolCapsule.itemWidth(context, 5);
    return PdfToolCapsule(
      children: [
        PdfCapsuleItem(
          icon: Icons.note_add_outlined,
          label: 'Add Page',
          width: itemWidth,
          onTap: () => _openTool(() => ToolActions.addPagesToPdf(context, File(widget.path))),
        ),
        PdfCapsuleItem(
          icon: Icons.draw_rounded,
          label: 'Sign',
          width: itemWidth,
          onTap: () => _openTool(() => ToolActions.openSignature(context, pdfPath: widget.path)),
        ),
        PdfCapsuleItem(
          icon: Icons.border_color_rounded,
          label: 'Highlight',
          width: itemWidth,
          onTap: () => _openTool(_openHighlight),
        ),
        PdfCapsuleItem(
          icon: Icons.lock_outline_rounded,
          label: 'Lock',
          width: itemWidth,
          onTap: () => _openTool(() => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PdfLockScreen(initialPdfPath: widget.path)),
              )),
        ),
        PdfCapsuleItem(
          icon: Icons.compress_rounded,
          label: 'Compress',
          width: itemWidth,
          onTap: () => _openTool(() => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PdfCompressScreen(initialPdfPath: widget.path)),
              )),
        ),
      ],
    );
  }

  /// Highlights are saved into this same file; re-render it afterwards.
  Future<void> _openHighlight() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PdfHighlightScreen(path: widget.path, initialPage: _currentPage)),
    );
    if (saved != true || !mounted) return;
    try {
      final fresh = await PdfPageSource.open(widget.path);
      if (!mounted) {
        fresh.dispose();
        return;
      }
      final old = _source;
      setState(() => _source = fresh);
      old?.dispose();
    } catch (e) {
      debugPrint('[Viewer] reload failed: $e');
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Color(0xFF3A3D43), shape: BoxShape.circle),
              child: const Icon(Icons.lock_outline_rounded, size: 40, color: Colors.white70),
            ),
            const SizedBox(height: 18),
            const Text(
              "Can't open this PDF",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'The file may be password-protected or damaged.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Colors.white70),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ToolPrimaryButton(label: 'Go Back', onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
