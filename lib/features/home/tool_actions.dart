import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/scanned_page.dart';
import '../../core/services/analytics_service.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/image_utils.dart';
import '../../providers/scan_provider.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/document_icon.dart';

import 'package:snap_scanner/features/editor/screens/batch_crop_screen.dart';
import 'package:snap_scanner/features/scanner/screens/scanner_screen.dart';
import 'package:snap_scanner/features/scanner/services/mlkit_document_scanner_service.dart';
import 'package:snap_scanner/features/review/screens/review_screen.dart';
import 'package:snap_scanner/features/merge/screens/pdf_merge_screen.dart';
import 'package:snap_scanner/features/split/screens/pdf_split_screen.dart';
import 'package:snap_scanner/features/compress/screens/pdf_compress_screen.dart';
import 'package:snap_scanner/features/lock/screens/pdf_lock_screen.dart';
import 'package:snap_scanner/features/signature/screens/signature_screen.dart';
import 'package:snap_scanner/features/signature/screens/saved_signatures_screen.dart';
import 'package:snap_scanner/features/signature/services/signature_service.dart';
import 'package:snap_scanner/features/resize_image/screens/resize_image_screen.dart';

/// Where new pages come from in "Add pages".
enum PageSource { camera, gallery, pdf }

/// Entry points for the existing tool flows, moved unchanged out of
/// ToolsScreen so the PDF tab's Scan CTA and the Tools grid share them.
class ToolActions {
  ToolActions._();

  /// [folderId]: the scan was started from that folder, so the resulting
  /// PDF is added to it. Null for the normal Scan flow.
  static Future<void> openScanner(BuildContext context, {String? folderId}) async {
    // ML Kit Document Scanner is Android-only. Keep iOS behaviour unchanged.
    if (!Platform.isAndroid) {
      AnalyticsService.instance.logScanStarted();
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ScannerScreen(folderId: folderId)),
      );
      return;
    }

    AnalyticsService.instance.logScanStarted();
    final provider = Provider.of<ScanProvider>(context, listen: false);
    provider.clearPages();
    provider.setToolType('scan_pdf');
    provider.setTargetFolder(folderId);

    List<String>? imagePaths;
    try {
      imagePaths = await MlkitDocumentScannerService.scanDocuments();
    } catch (e) {
      debugPrint('[ToolsScreen] ML Kit scanner failed: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanner failed to start. Please try again.')),
      );
      return;
    }

    // Cancelled – do nothing, stay on Tools (no PDF, no error).
    if (imagePaths == null || imagePaths.isEmpty) {
      debugPrint('[ToolsScreen] ML Kit cancelled or no pages');
      return;
    }

    await _addScannedImages(provider, imagePaths);

    if (!context.mounted) return;
    if (provider.pages.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ReviewScreen()),
    );
  }

  /// Copies scanner output into the app's permanent images dir (ML Kit files
  /// may be temporary) and adds them as pages.
  static Future<void> _addScannedImages(ScanProvider provider, List<String> imagePaths) async {
    for (final path in imagePaths) {
      try {
        final src = File(path);
        if (!await src.exists()) {
          debugPrint('[ToolActions] Missing scanned file: $path');
          continue;
        }
        final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
        await src.copy(permFile.path);
        provider.addPage(ScannedPage(
          id: const Uuid().v4(),
          originalPath: permFile.path,
          processedFile: permFile,
        ));
      } catch (e) {
        debugPrint('[ToolActions] Failed to copy scanned file $path: $e');
      }
    }
  }

  /// Asks where new pages should come from; null if cancelled.
  /// [includePdf] also offers importing the pages of an existing PDF.
  static Future<PageSource?> askPageSource(BuildContext context, {bool includePdf = false}) {
    return showAppDialog<PageSource>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: Icons.note_add_outlined,
        title: 'Add pages',
        description: 'New pages are added after the existing ones.',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogOption(
              icon: Icons.document_scanner_outlined,
              label: 'Scan with camera',
              onTap: () => Navigator.pop(ctx, PageSource.camera),
            ),
            AppDialogOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () => Navigator.pop(ctx, PageSource.gallery),
            ),
            if (includePdf)
              AppDialogOption(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Import from existing PDF',
                onTap: () => Navigator.pop(ctx, PageSource.pdf),
              ),
          ],
        ),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(ctx),
      ),
    );
  }

  /// Appends pages from the camera or gallery to the current session.
  /// Returns how many pages were added.
  static Future<int> addPagesFrom(BuildContext context, {required bool camera}) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    final before = provider.pages.length;
    if (camera) {
      if (Platform.isAndroid) {
        List<String>? paths;
        try {
          paths = await MlkitDocumentScannerService.scanDocuments();
        } catch (e) {
          debugPrint('[ToolActions] ML Kit scanner failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Scanner failed to start. Please try again.')),
            );
          }
        }
        if (paths != null && paths.isNotEmpty) {
          await _addScannedImages(provider, paths);
        }
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScannerScreen(appendMode: true)),
        );
      }
    } else {
      final images = await ImagePicker().pickMultiImage();
      if (images.isNotEmpty) {
        if (context.mounted) _showLoading(context);
        try {
          final optimized = await Future.wait(
            images.map((img) => ImageUtils.optimizeImage(File(img.path))),
          );
          for (var i = 0; i < images.length; i++) {
            provider.addPage(ScannedPage(
              id: const Uuid().v4(),
              originalPath: images[i].path,
              processedFile: optimized[i],
            ));
          }
        } finally {
          if (context.mounted) Navigator.pop(context);
        }
      }
    }
    return provider.pages.length - before;
  }

  /// Longest side, in pixels, of a page imported from a PDF
  /// (about A4 at 170 dpi: sharp, without huge files).
  static const double _importedPageLongSide = 2000;

  /// Appends every page of a picked PDF, in the PDF's order, as page images
  /// (the same [ScannedPage]s the scanner and gallery produce). The picked
  /// PDF is only read. All or nothing: if any page can't be rendered the
  /// session is left unchanged and this throws. Returns 0 if cancelled.
  /// [onProgress] is called before each page, once a PDF was picked.
  static Future<int> addPagesFromPdf(
    BuildContext context, {
    void Function(int done, int total)? onProgress,
  }) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return 0;

    final doc = await px.PdfDocument.openFile(path);
    final created = <File>[];
    try {
      final total = doc.pagesCount;
      for (var i = 1; i <= total; i++) {
        onProgress?.call(i - 1, total);
        final page = await doc.getPage(i);
        try {
          final scale = _importedPageLongSide / math.max(page.width, page.height);
          final image = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: px.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 90,
          );
          if (image == null) throw Exception('Page $i could not be rendered');
          final file = await FileUtils.createPermanentFile(extension: 'jpg');
          await file.writeAsBytes(image.bytes);
          created.add(file);
        } finally {
          await page.close();
        }
      }
    } catch (_) {
      for (final file in created) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await doc.close();
    }

    for (final file in created) {
      provider.addPage(ScannedPage(
        id: const Uuid().v4(),
        originalPath: file.path,
        processedFile: file,
      ));
    }
    return created.length;
  }

  /// "Add Page" on an existing PDF: new pages are saved, after [pdf]'s
  /// pages, as a new PDF. Each source continues like its own tool:
  /// gallery → crop → filter → review (Image to PDF); camera → review, the
  /// Scan PDF flow (on iOS the in-app camera's pages still go through crop,
  /// as in Scan PDF there).
  static Future<void> addPagesToPdf(BuildContext context, File pdf) async {
    final source = await askPageSource(context);
    if (source == null || !context.mounted) return;
    final camera = source == PageSource.camera;
    final provider = Provider.of<ScanProvider>(context, listen: false);
    provider.clearPages();
    provider.setToolType(camera ? 'scan_pdf' : 'image_to_pdf');
    provider.setAppendTarget(pdf.path);
    final added = await addPagesFrom(context, camera: camera);
    if (!context.mounted) return;
    if (added == 0) {
      provider.setAppendTarget(null);
      return;
    }
    final skipCrop = camera && Platform.isAndroid;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => skipCrop ? const ReviewScreen() : const BatchCropScreen(),
      ),
    );
  }

  static Future<void> pickImages(BuildContext context) async {
    AnalyticsService.instance.logImageToPdfStarted();
    final ImagePicker picker = ImagePicker();
    final provider = Provider.of<ScanProvider>(context, listen: false);
    provider.clearPages();
    provider.setToolType('image_to_pdf');

    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      if (context.mounted) _showLoading(context);

      final optimizedFiles = await Future.wait(
        images.map((img) => ImageUtils.optimizeImage(File(img.path))),
      );

      for (int i = 0; i < images.length; i++) {
        provider.addPage(ScannedPage(
          id: const Uuid().v4(),
          originalPath: images[i].path,
          processedFile: optimizedFiles[i],
        ));
      }
      if (context.mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BatchCropScreen()),
        );
      }
    }
  }

  static void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );
  }

  static void openMerge(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfMergeScreen()));
  }

  static void openSplit(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfSplitScreen()));
  }

  static void openCompress(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfCompressScreen()));
  }

  static void openLock(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfLockScreen()));
  }

  static void openResizeImage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ResizeImageScreen()));
  }

  /// [pdfPath] preselects the PDF to sign (e.g. from a PDF card's actions).
  static Future<void> openSignature(BuildContext context, {String? pdfPath}) async {
    final hasSaved = await SignatureService.hasSavedSignatures();
    if (!context.mounted) return;
    if (!hasSaved) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => SignatureScreen(pdfPath: pdfPath)));
    } else {
      _showSignatureOptions(context, pdfPath: pdfPath);
    }
  }

  static void _showSignatureOptions(BuildContext context, {String? pdfPath}) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppDialog(
        illustration: const DocumentIcon(
          icon: Icons.draw_outlined,
          color: AppColors.toolSignature,
          size: 64,
        ),
        title: 'Add Signature',
        description: 'Choose an option to add your signature',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppDialogOption(
              icon: Icons.draw_rounded,
              iconColor: AppColors.toolSignature,
              label: 'Create New Signature',
              subtitle: 'Draw a new signature',
              showChevron: true,
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => SignatureScreen(pdfPath: pdfPath)));
              },
            ),
            AppDialogOption(
              icon: Icons.folder_open_rounded,
              iconColor: const Color(0xFFD97706),
              label: 'Use Saved Signature',
              subtitle: 'Select from saved signatures',
              showChevron: true,
              onTap: () async {
                Navigator.pop(ctx);
                final hasSaved = await SignatureService.hasSavedSignatures();
                if (!hasSaved) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No saved signatures found. Create one first.')),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SavedSignaturesScreen(pdfPath: pdfPath)));
                }
              },
            ),
          ],
        ),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(ctx),
      ),
    );
  }
}
