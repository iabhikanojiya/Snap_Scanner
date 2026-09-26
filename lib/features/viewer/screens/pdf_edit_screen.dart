import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../compress/screens/pdf_compress_screen.dart';
import '../../home/tool_actions.dart';
import '../../lock/screens/pdf_lock_screen.dart';
import '../../pdf/screens/success_screen.dart';
import '../services/pdf_annotate_service.dart';
import '../widgets/pdf_pages.dart';

/// Edit page for an opened PDF: top bar with back, name and Save; pages in
/// the middle; a docked capsule with Highlight, Sign, Lock and Compress.
///
/// Highlight draws straight on the pages (tap for a dot, drag for a line);
/// while it is on, one finger draws and two fingers scroll. Tapping
/// Highlight again opens a small colour popup.
class PdfEditScreen extends StatefulWidget {
  final String path;
  final int initialPage;

  const PdfEditScreen({super.key, required this.path, this.initialPage = 0});

  @override
  State<PdfEditScreen> createState() => _PdfEditScreenState();
}

class _PdfEditScreenState extends State<PdfEditScreen> {
  static const List<Color> _colors = [
    Color(0xFF9BF59B), // light green (default)
    Color(0xFFFFF176), // yellow
    Color(0xFFFF9EC7), // pink
    Color(0xFF90CAF9), // light blue
    Color(0xFFFFB74D), // orange
  ];
  static const double _strokeWidth = 0.035; // fraction of page width

  PdfPageSource? _source;
  Object? _error;
  final ScrollController _scroll = ScrollController();
  PdfPagesLayout? _layout;
  int _currentPage = 0;
  bool _jumpedToInitial = false;

  bool _highlighting = false;
  Color _color = _colors.first;
  bool _colorPopupOpen = false;
  final GlobalKey _highlightKey = GlobalKey();
  double _popupAnchorX = 0;

  final List<HighlightStroke> _strokes = [];
  HighlightStroke? _activeStroke;
  final Set<int> _pointers = {};

  bool _saving = false;
  bool _savedCopy = false;

  String get _fileName => widget.path.split('/').last;
  String get _baseName => _fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
  bool get _hasEdits => _strokes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
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
    _source?.dispose();
    super.dispose();
  }

  void _onScroll() {
    final layout = _layout;
    if (layout == null || !_scroll.hasClients) return;
    final page = layout.pageAt(_scroll.offset, _scroll.position.viewportDimension);
    if (page != _currentPage) setState(() => _currentPage = page);
  }

  // ---------------------------------------------------------------- highlight

  void _onHighlightTap() {
    if (!_highlighting) {
      setState(() => _highlighting = true);
      return;
    }
    // Already on: toggle the colour popup, anchored above the button.
    final box = _highlightKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      _popupAnchorX = box.localToGlobal(box.size.center(Offset.zero)).dx;
    }
    setState(() => _colorPopupOpen = !_colorPopupOpen);
  }

  void _stopHighlighting() {
    setState(() {
      _highlighting = false;
      _colorPopupOpen = false;
    });
  }

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  Offset _norm(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  void _startStroke(int page, Offset point) {
    if (_pointers.length > 1) return;
    final stroke = HighlightStroke(pageIndex: page, color: _color, width: _strokeWidth, points: [point]);
    setState(() {
      _colorPopupOpen = false;
      _activeStroke = stroke;
      _strokes.add(stroke);
    });
  }

  void _extendStroke(Offset point) {
    final stroke = _activeStroke;
    if (stroke == null) return;
    setState(() => stroke.points.add(point));
  }

  /// Two fingers: cancel any stroke just started and scroll instead.
  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length > 1 && _activeStroke != null) {
      setState(() {
        _strokes.remove(_activeStroke);
        _activeStroke = null;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_highlighting || _pointers.length < 2 || !_scroll.hasClients) return;
    final target = _scroll.offset - e.delta.dy / _pointers.length;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) _activeStroke = null;
  }

  // ---------------------------------------------------------------- actions

  Future<String> _uniqueName(String base) async {
    final dir = await StorageService.getAppDirectory();
    var name = base;
    var n = 2;
    while (await File('$dir/$name.pdf').exists()) {
      name = '${base}_$n';
      n++;
    }
    return name;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _colorPopupOpen = false;
    });
    try {
      if (_hasEdits) {
        final bytes = await PdfAnnotateService.applyHighlights(widget.path, _strokes);
        final name = await _uniqueName('${_baseName}_highlighted');
        final file = await StorageService.savePdfFile(name, bytes);
        await DatabaseService.insertFile(PdfFileModel(
          id: const Uuid().v4(),
          name: name,
          path: file.path,
          size: await file.length(),
          createdAt: DateTime.now(),
          toolType: 'highlight_pdf',
        ));
        if (!mounted) return;
        _strokes.clear();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuccessScreen(
              pdfFile: file,
              title: 'PDF Saved!',
              shortcuts: const [
                SuccessShortcut.signPdf,
                SuccessShortcut.lockPdf,
                SuccessShortcut.compressPdf,
              ],
            ),
          ),
        );
        return;
      }
      final name = await _uniqueName(_baseName);
      final file = await StorageService.savePdfFile(name, await File(widget.path).readAsBytes());
      await DatabaseService.insertFile(PdfFileModel(
        id: const Uuid().v4(),
        name: name,
        path: file.path,
        size: await file.length(),
        createdAt: DateTime.now(),
        toolType: 'imported',
      ));
      if (!mounted) return;
      setState(() => _savedCopy = true);
      _snack('Saved to My PDFs');
    } catch (e) {
      debugPrint('[Edit] save failed: $e');
      _snack('Could not save the PDF. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// File to hand to Sign / Lock / Compress: the original, or a temporary
  /// copy with the current highlights burned in so they aren't lost.
  Future<String?> _fileForTools() async {
    if (!_hasEdits) return widget.path;
    try {
      final bytes = await PdfAnnotateService.applyHighlights(widget.path, _strokes);
      final dir = await Directory.systemTemp.createTemp('edit_');
      final file = File('${dir.path}/${_baseName}_highlighted.pdf');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      debugPrint('[Edit] preparing file failed: $e');
      _snack('Could not prepare the PDF. Please try again.');
      return null;
    }
  }

  Future<void> _openTool(void Function(String path) open) async {
    setState(() {
      _colorPopupOpen = false;
      _highlighting = false;
    });
    final path = await _fileForTools();
    if (path != null && mounted) open(path);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.destructive,
        icon: Icons.delete_outline_rounded,
        title: 'Discard highlights?',
        description: "Your highlights haven't been saved yet.",
        primaryLabel: 'Discard',
        onPrimary: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Keep editing',
        onSecondary: () => Navigator.pop(ctx, false),
      ),
    );
    return discard == true;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(
      canPop: !_hasEdits,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _strokes.clear();
          Navigator.pop(context);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: const Color(0xFF2A2C31),
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            systemOverlayStyle: SystemUiOverlayStyle.light,
            elevation: 0,
            titleSpacing: 0,
            title: Text(
              _fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: source == null || _saving || (_savedCopy && !_hasEdits) ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white54,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_savedCopy && !_hasEdits ? 'Saved' : 'Save'),
                ),
              ),
            ],
          ),
          body: _error != null
              ? const Center(
                  child: Text("Can't open this PDF", style: TextStyle(color: Colors.white70)),
                )
              : source == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _buildBody(source),
          bottomNavigationBar: source == null ? null : _buildCapsuleBar(),
        ),
      ),
    );
  }

  Widget _buildBody(PdfPageSource source) {
    return Stack(
      children: [
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final layout = _layout = PdfPagesLayout(source.sizes, constraints.maxWidth);
              if (!_jumpedToInitial) {
                _jumpedToInitial = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients && widget.initialPage > 0) {
                    _scroll.jumpTo(
                      (layout.offsetOf(widget.initialPage) - PdfPagesLayout.gap)
                          .clamp(0.0, _scroll.position.maxScrollExtent),
                    );
                  }
                });
              }
              final renderWidth = layout.renderWidth(context);
              return ListView.builder(
                controller: _scroll,
                // One finger draws while highlighting; two fingers scroll.
                physics: _highlighting ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.all(PdfPagesLayout.side),
                itemCount: source.pageCount,
                itemBuilder: (context, index) {
                  final tile = PdfPageTile(
                    image: source.render(index, renderWidth),
                    aspectRatio: source.sizes[index].width / source.sizes[index].height,
                    strokes: _strokes.where((s) => s.pageIndex == index).toList(),
                  );
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == source.pageCount - 1 ? 0 : PdfPagesLayout.gap),
                    child: _highlighting
                        ? LayoutBuilder(
                            builder: (context, c) {
                              final size = Size(c.maxWidth, layout.pageHeight(index));
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapUp: (d) {
                                  _startStroke(index, _norm(d.localPosition, size));
                                  _activeStroke = null;
                                },
                                onPanStart: (d) => _startStroke(index, _norm(d.localPosition, size)),
                                onPanUpdate: (d) => _extendStroke(_norm(d.localPosition, size)),
                                onPanEnd: (_) => _activeStroke = null,
                                child: tile,
                              );
                            },
                          )
                        : tile,
                  );
                },
              );
            },
          ),
        ),
        // Page counter (right) and, while highlighting, the hint (left).
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(
            child: _Pill('${_currentPage + 1} / ${source.pageCount}'),
          ),
        ),
        if (_highlighting)
          const Positioned(
            top: 12,
            left: 12,
            child: IgnorePointer(child: _Pill('Highlighting · 2 fingers to scroll')),
          ),
        if (_highlighting && _hasEdits)
          Positioned(
            top: 50,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.65),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Undo',
                onPressed: _undo,
                icon: const Icon(Icons.undo_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        if (_colorPopupOpen) ...[
          // Tap outside closes; transparent, no dim or blur.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _colorPopupOpen = false),
            ),
          ),
          _buildColorPopup(),
        ],
      ],
    );
  }

  Widget _buildColorPopup() {
    const dot = 30.0;
    const gap = 8.0;
    const padding = 8.0;
    final width = padding * 2 + (_colors.length + 1) * dot + _colors.length * gap;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final left = (_popupAnchorX - width / 2).clamp(8.0, screenWidth - width - 8);
    return Positioned(
      left: left,
      bottom: 8,
      child: Material(
        color: Colors.white,
        elevation: 6,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(padding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in _colors) ...[
                Semantics(
                  selected: color == _color,
                  button: true,
                  label: 'Highlight color',
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _color = color;
                      _colorPopupOpen = false;
                    }),
                    child: Container(
                      width: dot,
                      height: dot,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == _color ? AppColors.textPrimary : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: gap),
              ],
              // Turn highlighting off (back to normal scrolling).
              Tooltip(
                message: 'Stop highlighting',
                child: GestureDetector(
                  onTap: _stopHighlighting,
                  child: const SizedBox(
                    width: dot,
                    height: dot,
                    child: Icon(Icons.pan_tool_alt_outlined, size: 20, color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapsuleBar() {
    // Four equal items; shrink a little on narrow phones.
    final itemWidth = ((MediaQuery.sizeOf(context).width - 56) / 4).clamp(58.0, 74.0);
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            // heightFactor: 1 keeps the bar as tall as the capsule; a plain
            // Center here would fill the whole screen height.
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF26282D),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CapsuleItem(
                    key: _highlightKey,
                    icon: Icons.border_color_rounded,
                    label: 'Highlight',
                    width: itemWidth,
                    active: _highlighting,
                    activeColor: _color,
                    onTap: _onHighlightTap,
                  ),
                  _CapsuleItem(
                    icon: Icons.draw_rounded,
                    label: 'Sign',
                    width: itemWidth,
                    onTap: () => _openTool((path) => ToolActions.openSignature(context, pdfPath: path)),
                  ),
                  _CapsuleItem(
                    icon: Icons.lock_outline_rounded,
                    label: 'Lock',
                    width: itemWidth,
                    onTap: () => _openTool((path) => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PdfLockScreen(initialPdfPath: path)),
                        )),
                  ),
                  _CapsuleItem(
                    icon: Icons.compress_rounded,
                    label: 'Compress',
                    width: itemWidth,
                    onTap: () => _openTool((path) => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PdfCompressScreen(initialPdfPath: path)),
                        )),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width item in the docked tool capsule.
class _CapsuleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;
  final double width;

  const _CapsuleItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.width,
    this.active = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: Colors.white),
                  if (active && activeColor != null)
                    Positioned(
                      right: -6,
                      bottom: -3,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF26282D), width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
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
