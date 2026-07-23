import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/exceptions/app_exceptions.dart';
import 'package:snap_scanner/core/services/ad_service.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/banner_ad_widget.dart';
import 'package:snap_scanner/providers/scan_provider.dart';

class SuccessScreen extends StatefulWidget {
  final File pdfFile;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final IconData fileIcon;
  final Color fileIconColor;

  const SuccessScreen({
    super.key,
    required this.pdfFile,
    this.icon = Icons.check_circle,
    this.iconColor = Colors.green,
    this.title = 'PDF Created Successfully!',
    this.subtitle,
    IconData? fileIcon,
    Color? fileIconColor,
  })  : fileIcon = fileIcon ?? Icons.picture_as_pdf,
        fileIconColor = fileIconColor ?? Colors.redAccent;

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  Future<void> _shareFile() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(widget.pdfFile.path)],
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
      final result = await OpenFilex.open(widget.pdfFile.path);
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
      if (!await widget.pdfFile.exists()) {
        throw const StorageException(
          technicalMessage: 'PDF file no longer exists at path',
        );
      }

      final bytes = await widget.pdfFile.readAsBytes();
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save File',
        fileName: widget.pdfFile.path.split('/').last,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon,
                        color: widget.iconColor, size: 80),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 28),
                  Container(
                    width: double.infinity,
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
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 18),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: widget.fileIconColor
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(widget.fileIcon,
                                    color: widget.fileIconColor,
                                    size: 26),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  widget.pdfFile.path.split('/').last,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade100),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      _downloadFile(context),
                                  icon: const Icon(Icons.download,
                                      size: 20),
                                  label: const Text('Download',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15)),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 14),
                                        backgroundColor: Colors.white,
                                        foregroundColor:
                                            Colors.blueAccent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    14)),
                                        elevation: 0,
                                        side: const BorderSide(
                                            color: Colors.blueAccent,
                                            width: 2),
                                      ),
                                      onPressed: _openFile,
                                      icon: const Icon(Icons.visibility,
                                          size: 20),
                                      label: const Text('Open',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                vertical: 14),
                                        backgroundColor:
                                            Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    14)),
                                        elevation: 0,
                                      ),
                                      onPressed: _shareFile,
                                      icon: const Icon(Icons.share,
                                          size: 20),
                                      label: const Text('Share',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: () => _goHome(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                    child: Text(
                      'Back to Home',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const BannerAdWidget(),
        ],
      ),
    );
  }
}
