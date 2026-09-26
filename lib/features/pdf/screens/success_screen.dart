import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/exceptions/app_exceptions.dart';
import 'package:snap_scanner/core/services/ad_service.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:pdfx/pdfx.dart' as px;
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/animated_success_check.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tool_shortcut_card.dart';
import '../../documents/widgets/pdf_thumbnail.dart';
import '../../home/tool_actions.dart';
import '../../compress/screens/pdf_compress_screen.dart';
import '../../lock/screens/pdf_lock_screen.dart';
import '../../merge/screens/pdf_merge_screen.dart';
import '../../split/screens/pdf_split_screen.dart';
import '../../lock/services/pdf_lock_service.dart';

/// Follow-up tools offered on the success screen. Each tool screen picks the
/// set that makes sense after it.
enum SuccessShortcut {
  addPage,
  signPdf,
  lockPdf,
  compressPdf,
  mergePdf,
  splitPdf,
  resizeImage,
  scanPdf,
  imageToPdf,
  addSign,
}

class SuccessScreen extends StatefulWidget {
  final File pdfFile;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final IconData fileIcon;
  final Color fileIconColor;

  /// Shortcuts shown under the file card. Ones that act on this PDF are
  /// hidden automatically for images and password-protected PDFs.
  final List<SuccessShortcut> shortcuts;

  const SuccessScreen({
    super.key,
    required this.pdfFile,
    this.icon = Icons.check_circle,
    this.iconColor = Colors.green,
    this.title = 'PDF Created Successfully!',
    this.subtitle,
    this.shortcuts = const [
      SuccessShortcut.addPage,
      SuccessShortcut.signPdf,
      SuccessShortcut.lockPdf,
      SuccessShortcut.compressPdf,
    ],
    IconData? fileIcon,
    Color? fileIconColor,
  })  : fileIcon = fileIcon ?? Icons.picture_as_pdf,
        fileIconColor = fileIconColor ?? Colors.redAccent;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  /// Current file; changes when the user renames it here.
  late File _file = widget.pdfFile;

  bool get _isPdf => _file.path.toLowerCase().endsWith('.pdf');

  String get _baseName =>
      _file.path.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

  Future<void> _editName() async {
    final newName = await showAppDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initialName: _baseName,
        directory: _file.parent.path,
      ),
    );
    if (newName == null || newName == _baseName || !mounted) return;

    try {
      final oldPath = _file.path;
      final newPath = await StorageService.renameFile(oldPath, newName);
      final files = await DatabaseService.getAllFiles();
      for (final f in files.where((f) => f.path == oldPath)) {
        await DatabaseService.updateFileMetadata(f.id, newName, newPath);
      }
      if (!mounted) return;
      setState(() => _file = File(newPath));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File renamed')),
      );
    } catch (e) {
      debugPrint('Rename failed: $e');
      if (mounted) _showErrorSnackBar('Could not rename the file. Please try again.');
    }
  }

  /// Locked PDFs can't be signed, locked again or extended, so their
  /// shortcuts are hidden. Unknown until the check finishes.
  bool? _isLocked;
  int? _pageCount;
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final size = await _file.length();
      if (mounted) setState(() => _sizeBytes = size);
    } catch (_) {}
    if (!_isPdf) return;
    try {
      final locked = await PdfLockService.isPdfLocked(_file.path);
      if (mounted) setState(() => _isLocked = locked);
      if (locked) return;
      final doc = await px.PdfDocument.openFile(_file.path);
      final count = doc.pagesCount;
      await doc.close();
      if (mounted) setState(() => _pageCount = count);
    } catch (e) {
      debugPrint('Success details failed: $e');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _shareFile() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_file.path)],
          text: 'Here is my scanned document.',
        ),
      );
      AnalyticsService.instance.logPdfShared();
    } catch (e) {
      debugPrint('Share failed: $e');
      if (mounted) {
        _showErrorSnackBar('Could not open share sheet');
      }
    }
  }

  Future<void> _openFile() async {
    try {
      final result = await OpenFilex.open(_file.path);
      if (result.type != ResultType.done && mounted) {
        _showErrorSnackBar('Could not open the file');
      }
    } catch (e) {
      debugPrint('Open failed: $e');
      if (mounted) {
        _showErrorSnackBar('No app available to open this PDF');
      }
    }
  }

  Future<void> _downloadFile(BuildContext context) async {
    try {
      if (!await _file.exists()) {
        throw const StorageException(
          technicalMessage: 'PDF file no longer exists at path',
        );
      }

      final bytes = await _file.readAsBytes();
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save File',
        fileName: _file.path.split('/').last,
        bytes: bytes,
      );
      if (outputPath != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File downloaded successfully!')),
        );
      }
    } on AppException catch (e) {
      e.log();
      if (!context.mounted) return;
      _showErrorSnackBar(e.userMessage);
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'download_failed',
        message: e.toString(),
      );
      debugPrint('Download failed: $e');
      if (mounted) {
        _showErrorSnackBar('Could not download the file. Please try again.');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _goHome(BuildContext context) {
    AdService.instance.onSuccessfulOperation();
    Provider.of<ScanProvider>(context, listen: false).clearPages();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _file.path.split('/').last;
    final meta = [
      if (_pageCount != null) '$_pageCount page${_pageCount == 1 ? '' : 's'}',
      if (_sizeBytes != null) _formatSize(_sizeBytes!),
    ].join(' · ');
    final canUseFile = _isPdf && _isLocked == false;
    final shortcuts = [
      for (final s in widget.shortcuts)
        if (!_needsFile(s) || canUseFile) s,
    ];
    final showTools = shortcuts.isNotEmpty;

    return DecoratedBox(
      // Subtle brand-red wash that fades into the page background.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35, 0.7],
          colors: [
            Color.alphaBlend(AppColors.brandRed.withValues(alpha: 0.22), AppColors.background),
            Color.alphaBlend(AppColors.brandRed.withValues(alpha: 0.08), AppColors.background),
            AppColors.background,
          ],
        ),
      ),
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  if (widget.icon == Icons.check_circle)
                    // Default success: animated check. Tools that pass their
                    // own icon keep it.
                    const AnimatedSuccessCheck(size: 84)
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(widget.icon, color: widget.iconColor, size: 40),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _openFile,
                              child: _buildPreview(),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            fileName,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_isPdf)
                                        IconButton(
                                          tooltip: 'Edit name',
                                          onPressed: _editName,
                                          icon: const Icon(Icons.edit_outlined, size: 20),
                                          color: AppColors.textSecondary,
                                        ),
                                    ],
                                  ),
                                  if (meta.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      meta,
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: _openFile,
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 2),
                                      child: Text(
                                        'Open file',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.brandRed,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: () => _downloadFile(context),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.brandRed,
                                    foregroundColor: Colors.white,
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.download_rounded, size: 20),
                                  label: const Text('Download',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: OutlinedButton.icon(
                                  onPressed: _shareFile,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.brandRed,
                                    side: const BorderSide(color: AppColors.brandRed, width: 1.5),
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.share_rounded, size: 20),
                                  label: const Text('Share',
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (showTools) ...[
                          const SizedBox(height: 18),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          const SizedBox(height: 18),
                          _buildShortcuts(shortcuts),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => _goHome(context),
                    style: TextButton.styleFrom(padding: const EdgeInsets.all(16)),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const NativeAdWidget(),
          ],
        ),
      ),
      ),
    );
  }

  bool _needsFile(SuccessShortcut s) => switch (s) {
        SuccessShortcut.resizeImage ||
        SuccessShortcut.scanPdf ||
        SuccessShortcut.imageToPdf ||
        SuccessShortcut.addSign =>
          false,
        _ => true,
      };

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  ToolShortcutCard _shortcutCard(SuccessShortcut s) {
    final path = _file.path;
    final (icon, color, label, onTap) = switch (s) {
      SuccessShortcut.addPage => (Icons.note_add_outlined, AppColors.toolImageToPdf, 'Add Page',
          () => ToolActions.addPagesToPdf(context, _file)),
      SuccessShortcut.signPdf => (Icons.draw_outlined, AppColors.toolSignature, 'Sign PDF',
          () => ToolActions.openSignature(context, pdfPath: path)),
      SuccessShortcut.lockPdf => (Icons.lock_outline_rounded, AppColors.toolLock, 'Lock PDF',
          () => _push(PdfLockScreen(initialPdfPath: path))),
      SuccessShortcut.compressPdf => (Icons.compress_rounded, AppColors.toolCompress, 'Compress',
          () => _push(PdfCompressScreen(initialPdfPath: path))),
      SuccessShortcut.mergePdf => (Icons.merge_type_rounded, AppColors.toolMerge, 'Merge PDF',
          () => _push(PdfMergeScreen(initialPdfPaths: [path]))),
      SuccessShortcut.splitPdf => (Icons.call_split_rounded, AppColors.toolSplit, 'Split PDF',
          () => _push(PdfSplitScreen(initialPdfPath: path))),
      SuccessShortcut.resizeImage => (Icons.photo_size_select_large_rounded, AppColors.toolResize,
          'Resize Image', () => ToolActions.openResizeImage(context)),
      SuccessShortcut.scanPdf => (Icons.document_scanner_outlined, AppColors.toolScan, 'Scan PDF',
          () => ToolActions.openScanner(context)),
      SuccessShortcut.imageToPdf => (Icons.image_outlined, AppColors.toolImageToPdf, 'Image to PDF',
          () => ToolActions.pickImages(context)),
      SuccessShortcut.addSign => (Icons.draw_outlined, AppColors.toolSignature, 'Add Sign',
          () => ToolActions.openSignature(context)),
    };
    return ToolShortcutCard(icon: icon, color: color, label: label, onTap: onTap);
  }

  /// One row of cards; four cards switch to a 2×2 grid on narrow screens.
  Widget _buildShortcuts(List<SuccessShortcut> shortcuts) {
    Widget row(List<SuccessShortcut> items) => Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _shortcutCard(items[i]),
            ],
          ],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final perCard = (constraints.maxWidth - 8 * (shortcuts.length - 1)) / shortcuts.length;
        if (shortcuts.length == 4 && perCard < 74) {
          return Column(
            children: [
              row(shortcuts.sublist(0, 2)),
              const SizedBox(height: 8),
              row(shortcuts.sublist(2)),
            ],
          );
        }
        return row(shortcuts);
      },
    );
  }

  Widget _buildPreview() {
    const width = 88.0, height = 88.0;
    Widget child;
    if (_isPdf) {
      child = PdfThumbnail(
        file: PdfFileModel(
          id: _file.path,
          name: _file.path.split('/').last,
          path: _file.path,
          size: _sizeBytes ?? 0,
          createdAt: DateTime.now(),
        ),
        width: width,
        height: height,
      );
    } else {
      child = Image.file(
        _file,
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: 264,
        errorBuilder: (_, _, _) => Icon(widget.fileIcon, color: widget.fileIconColor, size: 32),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Owns its text controller so it is disposed only after the dialog's exit
/// animation (disposing it right after `showAppDialog` returns crashes).
class _RenameDialog extends StatefulWidget {
  final String initialName;
  final String directory;

  const _RenameDialog({required this.initialName, required this.directory});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }
    if (name != widget.initialName &&
        await File('${widget.directory}/$name.pdf').exists()) {
      if (mounted) setState(() => _error = 'A file with this name already exists');
      return;
    }
    if (mounted) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.edit_outlined,
      title: 'Rename File',
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: AppDialog.inputDecoration(suffixText: '.pdf', errorText: _error),
      ),
      primaryLabel: 'Rename',
      onPrimary: _submit,
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.pop(context),
    );
  }
}
