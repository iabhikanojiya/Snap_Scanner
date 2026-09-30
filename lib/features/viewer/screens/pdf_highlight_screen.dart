import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/database_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../services/pdf_annotate_service.dart';
import '../widgets/pdf_pages.dart';
import '../widgets/pdf_tool_capsule.dart';

/// One highlight: text boxes (one per line) when drawn over text, or a
/// freehand marker stroke on pages without a text layer (scans).
class _Mark {
  final int page;
  final Color color;
  final List<Rect> rects;
  final List<Offset> points;

  const _Mark({required this.page, required this.color, this.rects = const [], this.points = const []});

  bool get isEmpty => rects.isEmpty && points.isEmpty;

  /// Normalised area covered, for the selection outline.
  Rect get bounds {
    if (rects.isNotEmpty) return rects.reduce((a, b) => a.expandToInclude(b));
    // Freehand: include roughly half the marker width around the line.
    return points.map((p) => Rect.fromPoints(p, p)).reduce((a, b) => a.expandToInclude(b)).inflate(0.015);
  }
}

enum _BackChoice { save, discard }

/// Highlights the PDF at [path] and, on Save, writes them into that same
/// file (same name, no copy). Pops `true` after a successful save.
///
/// Dragging over text selects the words between start and end, like text
/// selection, and highlights them line by line (word positions come from
/// the PDF's text layer). Where there is no text (scanned pages, images)
/// the drag draws a freehand marker instead. One finger highlights, two
/// fingers scroll.
class PdfHighlightScreen extends StatefulWidget {
  final String path;
  final int initialPage;

  const PdfHighlightScreen({super.key, required this.path, this.initialPage = 0});

  @override
  State<PdfHighlightScreen> createState() => _PdfHighlightScreenState();
}

class _PdfHighlightScreenState extends State<PdfHighlightScreen> {
  static const List<(String, Color)> _colors = [
    ('Yellow', Color(0xFFFFE600)),
    ('Green', Color(0xFF4CD964)),
    ('Blue', Color(0xFF4FC3F7)),
    ('Pink', Color(0xFFFF6FB5)),
  ];
  static const double _strokeWidth = 0.035; // freehand, fraction of page width
  static const double _hitSlop = 0.03; // in page widths

  PdfPageSource? _source;
  Object? _error;
  List<List<PdfWord>>? _words;
  final ScrollController _scroll = ScrollController();
  PdfPagesLayout? _layout;
  int _currentPage = 0;
  bool _jumpedToInitial = false;

  bool _highlighting = true;
  Color _color = _colors.first.$2;

  // Marks are immutable; undo/redo keep whole snapshots of the list.
  List<_Mark> _marks = const [];
  final List<List<_Mark>> _undo = [];
  final List<List<_Mark>> _redo = [];
  _Mark? _selected;

  // Current drag.
  List<_Mark>? _beforeDrag;
  int? _dragPage;
  int? _anchorWord; // text drag: index of the first word
  List<Offset>? _dragPoints; // freehand drag
  final Set<int> _pointers = {};

  bool _saving = false;

  bool get _hasChanges => _marks.isNotEmpty;

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
      PdfAnnotateService.extractWords(widget.path, source.pageCount).then((words) {
        if (mounted) setState(() => _words = words);
      }, onError: (Object e) {
        // No usable text layer: every page uses the freehand marker.
        debugPrint('[Highlight] text extraction failed: $e');
        if (mounted) setState(() => _words = List.generate(source.pageCount, (_) => const []));
      });
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

  // ---------------------------------------------------------------- history

  void _commit(List<_Mark> before, List<_Mark> after) {
    setState(() {
      _undo.add(before);
      _redo.clear();
      _marks = after;
      _selected = null;
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(_marks);
      _marks = _undo.removeLast();
      _selected = null;
    });
  }

  void _redoLast() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(_marks);
      _marks = _redo.removeLast();
      _selected = null;
    });
  }

  /// Deletes the selected highlight, or clears all when none is selected.
  void _deleteOrClear() {
    if (_marks.isEmpty) return;
    final selected = _selected;
    _commit(_marks, selected == null ? const [] : [for (final m in _marks) if (m != selected) m]);
  }

  // ---------------------------------------------------------------- geometry

  Offset _norm(Offset local, Size size) => Offset(
        (local.dx / size.width).clamp(0.0, 1.0),
        (local.dy / size.height).clamp(0.0, 1.0),
      );

  /// Distance in page widths (y scaled by the page's aspect ratio).
  double _distance(Rect r, Offset p, double aspect) {
    final dx = math.max(0.0, math.max(r.left - p.dx, p.dx - r.right));
    final dy = math.max(0.0, math.max(r.top - p.dy, p.dy - r.bottom)) / aspect;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Index of the word nearest [p]; with [maxDistance], null if none is close.
  int? _wordAt(int page, Offset p, {double? maxDistance}) {
    final words = _words?[page];
    final source = _source;
    if (words == null || words.isEmpty || source == null) return null;
    final aspect = source.sizes[page].width / source.sizes[page].height;
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < words.length; i++) {
      final d = _distance(words[i].rect, p, aspect);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    if (maxDistance != null && bestDistance > maxDistance) return null;
    return best;
  }

  /// Boxes for words [a]..[b] (either order), merged per line.
  List<Rect> _lineBoxes(int page, int a, int b) {
    final words = _words![page];
    final byLine = <int, Rect>{};
    for (var i = math.min(a, b); i <= math.max(a, b); i++) {
      final w = words[i];
      byLine.update(w.line, (r) => r.expandToInclude(w.rect), ifAbsent: () => w.rect);
    }
    return byLine.values.toList();
  }

  // ---------------------------------------------------------------- gestures

  void _dragStart(int page, Offset p) {
    // Wait for the text layer, so text is never drawn over freehand.
    if (_pointers.length > 1 || _words == null) return;
    _beforeDrag = _marks;
    _dragPage = page;
    _anchorWord = _wordAt(page, p, maxDistance: _hitSlop);
    _dragPoints = _anchorWord == null ? [p] : null;
    _dragUpdate(p);
  }

  void _dragUpdate(Offset p) {
    final before = _beforeDrag;
    final page = _dragPage;
    if (before == null || page == null) return;
    final anchor = _anchorWord;
    final _Mark mark;
    if (anchor != null) {
      final end = _wordAt(page, p) ?? anchor;
      mark = _Mark(page: page, color: _color, rects: _lineBoxes(page, anchor, end));
    } else {
      final points = _dragPoints!;
      if (points.last != p) points.add(p);
      mark = _Mark(page: page, color: _color, points: List.of(points));
    }
    setState(() {
      _selected = null;
      _marks = [...before, mark];
    });
  }

  void _dragEnd() {
    final before = _beforeDrag;
    if (before == null) return;
    _beforeDrag = null;
    _dragPage = null;
    final added = _marks.length > before.length && !_marks.last.isEmpty;
    if (added) {
      _commit(before, _marks);
    } else {
      setState(() => _marks = before);
    }
  }

  void _dragCancel() {
    final before = _beforeDrag;
    if (before == null) return;
    _beforeDrag = null;
    _dragPage = null;
    setState(() => _marks = before);
  }

  /// Tap: select the highlight under the finger (for Delete), or deselect.
  void _tapAt(int page, Offset p) {
    final source = _source;
    if (source == null) return;
    final aspect = source.sizes[page].width / source.sizes[page].height;
    _Mark? hit;
    for (final m in _marks.reversed) {
      if (m.page != page) continue;
      final near = m.rects.isNotEmpty
          ? m.rects.any((r) => _distance(r, p, aspect) < 0.01)
          : m.points.any((q) => _distance(Rect.fromPoints(q, q), p, aspect) < _strokeWidth);
      if (near) {
        hit = m;
        break;
      }
    }
    setState(() => _selected = hit == _selected ? null : hit);
  }

  /// Two fingers: cancel any highlight just started and scroll instead.
  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (_pointers.length > 1) _dragCancel();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_highlighting || _pointers.length < 2 || !_scroll.hasClients) return;
    final target = _scroll.offset - e.delta.dy / _pointers.length;
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  void _onPointerUp(PointerEvent e) => _pointers.remove(e.pointer);

  // ---------------------------------------------------------------- save / back

  Future<void> _save() async {
    if (_saving || !_hasChanges) return;
    setState(() {
      _saving = true;
      _selected = null;
    });
    try {
      final bytes = await PdfAnnotateService.applyHighlights(
        widget.path,
        [
          for (final m in _marks)
            if (m.points.isNotEmpty)
              HighlightStroke(pageIndex: m.page, color: m.color, width: _strokeWidth, points: m.points),
        ],
        boxes: [
          for (final m in _marks)
            for (final r in m.rects) HighlightBox(pageIndex: m.page, color: m.color, rect: r),
        ],
      );
      // Write next to the file, then swap it in: the original is never left
      // half-written.
      final temp = File('${widget.path}.saving');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(widget.path);
      try {
        await DatabaseService.updateFileSizeByPath(widget.path, bytes.length);
      } catch (e) {
        debugPrint('[Highlight] size update failed: $e');
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[Highlight] save failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not save highlights. Please try again.')));
    }
  }

  Future<void> _onBack() async {
    if (_saving) return;
    final choice = await showAppDialog<_BackChoice>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: Icons.border_color_rounded,
        title: 'Save changes?',
        description: 'Your highlights haven\'t been saved yet.',
        primaryLabel: 'Save',
        onPrimary: () => Navigator.pop(ctx, _BackChoice.save),
        secondaryLabel: 'Discard',
        onSecondary: () => Navigator.pop(ctx, _BackChoice.discard),
        // Cancel: X button (or tapping outside) keeps editing.
        onClose: () => Navigator.pop(ctx),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _BackChoice.save:
        await _save();
      case _BackChoice.discard:
        Navigator.pop(context);
      case null:
        break;
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return PopScope(
      canPop: !_hasChanges && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _hasChanges) _onBack();
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
            title: const Text(
              'Highlight',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: _hasChanges && !_saving ? _save : null,
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
                      : const Text('Save'),
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
          bottomNavigationBar: source == null ? null : _buildToolbar(),
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
                // One finger highlights; two fingers scroll.
                physics: _highlighting ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.all(PdfPagesLayout.side),
                itemCount: source.pageCount,
                itemBuilder: (context, index) {
                  final marks = _marks.where((m) => m.page == index);
                  final selected = _selected;
                  final tile = PdfPageTile(
                    image: source.render(index, renderWidth),
                    aspectRatio: source.sizes[index].width / source.sizes[index].height,
                    boxes: [
                      for (final m in marks)
                        for (final r in m.rects) (r, m.color),
                    ],
                    strokes: [
                      for (final m in marks)
                        if (m.points.isNotEmpty)
                          HighlightStroke(pageIndex: index, color: m.color, width: _strokeWidth, points: m.points),
                    ],
                    outline: selected != null && selected.page == index ? selected.bounds : null,
                  );
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == source.pageCount - 1 ? 0 : PdfPagesLayout.gap),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final size = Size(c.maxWidth, layout.pageHeight(index));
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _tapAt(index, _norm(d.localPosition, size)),
                          onPanStart: _highlighting ? (d) => _dragStart(index, _norm(d.localPosition, size)) : null,
                          onPanUpdate: _highlighting ? (d) => _dragUpdate(_norm(d.localPosition, size)) : null,
                          onPanEnd: _highlighting ? (_) => _dragEnd() : null,
                          onPanCancel: _highlighting ? _dragCancel : null,
                          child: tile,
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: IgnorePointer(child: _Pill('${_currentPage + 1} / ${source.pageCount}')),
        ),
        if (_highlighting)
          Positioned(
            top: 12,
            left: 12,
            child: IgnorePointer(
              child: _Pill(_words == null ? 'Preparing text…' : 'Drag to highlight · 2 fingers to scroll'),
            ),
          ),
      ],
    );
  }

  Widget _buildToolbar() {
    final itemWidth = PdfToolCapsule.itemWidth(context, 4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Colour selector, shown while Highlight is on.
        if (_highlighting)
          Container(
            color: Colors.black,
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (name, color) in _colors)
                  Semantics(
                    button: true,
                    selected: color == _color,
                    label: '$name highlight',
                    child: GestureDetector(
                      onTap: () => setState(() => _color = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == _color ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        PdfToolCapsule(
          children: [
            PdfCapsuleItem(
              icon: Icons.border_color_rounded,
              label: 'Highlight',
              width: itemWidth,
              active: _highlighting,
              activeColor: _color,
              onTap: () => setState(() => _highlighting = !_highlighting),
            ),
            _enabled(
              _undo.isNotEmpty,
              PdfCapsuleItem(icon: Icons.undo_rounded, label: 'Undo', width: itemWidth, onTap: _undoLast),
            ),
            _enabled(
              _redo.isNotEmpty,
              PdfCapsuleItem(icon: Icons.redo_rounded, label: 'Redo', width: itemWidth, onTap: _redoLast),
            ),
            _enabled(
              _marks.isNotEmpty,
              PdfCapsuleItem(
                icon: _selected != null ? Icons.delete_outline_rounded : Icons.layers_clear_outlined,
                label: _selected != null ? 'Delete' : 'Clear',
                width: itemWidth,
                onTap: _deleteOrClear,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _enabled(bool enabled, Widget child) => IgnorePointer(
        ignoring: !enabled,
        child: Opacity(opacity: enabled ? 1 : 0.35, child: child),
      );
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
