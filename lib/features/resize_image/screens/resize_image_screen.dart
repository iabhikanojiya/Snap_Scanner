import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import '../services/resize_image_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/document_icon.dart';
import '../../../core/widgets/tool_ui.dart';

class ResizeImageScreen extends StatefulWidget {
  const ResizeImageScreen({super.key});

  @override
  State<ResizeImageScreen> createState() => _ResizeImageScreenState();
}

class _ResizeImageScreenState extends State<ResizeImageScreen> {
  File? _selectedFile;
  int _originalWidth = 0;
  int _originalHeight = 0;
  late TextEditingController _widthController;
  late TextEditingController _heightController;
  late TextEditingController _nameController;
  bool _keepAspectRatio = true;
  ResizeFormat _format = ResizeFormat.jpeg;
  double _quality = 85;
  bool _isProcessing = false;
  bool _isLoadingImage = false;

  static const _presets = [
    {'label': 'HD (1920x1080)', 'w': 1920, 'h': 1080},
    {'label': 'Square (1080x1080)', 'w': 1080, 'h': 1080},
    {'label': '800x600', 'w': 800, 'h': 600},
    {'label': '640x480', 'w': 640, 'h': 480},
  ];

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController();
    _heightController = TextEditingController();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// True while the picker is open or the picked image is being read, so
  /// repeated taps can't open a second picker ("already_active" error).
  bool _isPicking = false;

  Future<void> _pickImage() async {
    if (_isPicking) return;
    _isPicking = true;
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      if (mounted) setState(() => _isLoadingImage = true);
      final file = File(image.path);
      final size = await ResizeImageService.readDimensions(file);

      if (size == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to decode image.')),
          );
        }
        return;
      }

      if (!mounted) return;
      final (width, height) = size;
      setState(() {
        _selectedFile = file;
        _originalWidth = width;
        _originalHeight = height;
        _widthController.text = width.toString();
        _heightController.text = height.toString();
        _nameController.text = file.path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    } finally {
      _isPicking = false;
      if (mounted && _isLoadingImage) setState(() => _isLoadingImage = false);
    }
  }

  void _onWidthChanged(String value) {
    if (!_keepAspectRatio || _originalHeight == 0) return;
    final w = int.tryParse(value);
    if (w != null && w > 0) {
      final h = (w / _originalWidth * _originalHeight).round();
      _heightController.text = h.toString();
    }
  }

  void _onHeightChanged(String value) {
    if (!_keepAspectRatio || _originalWidth == 0) return;
    final h = int.tryParse(value);
    if (h != null && h > 0) {
      final w = (h / _originalHeight * _originalWidth).round();
      _widthController.text = w.toString();
    }
  }

  Future<void> _resize() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }

    final w = int.tryParse(_widthController.text);
    final h = int.tryParse(_heightController.text);

    if (w == null || h == null || w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid width and height.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final name = _nameController.text.trim().isEmpty ? null : _nameController.text.trim();
      final file = await ResizeImageService.resizeImage(
        sourceFile: _selectedFile!,
        width: w,
        height: h,
        format: _format,
        quality: _quality.round(),
        outputName: name,
      );

      await DatabaseService.insertFile(PdfFileModel(
        id: const Uuid().v4(),
        name: file.path.split('/').last,
        path: file.path,
        size: await file.length(),
        createdAt: DateTime.now(),
        toolType: 'resize_image',
      ));

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              icon: Icons.photo_size_select_large,
              iconColor: Colors.pink,
              title: 'Image Resized Successfully!',
              shortcuts: const [SuccessShortcut.scanPdf, SuccessShortcut.imageToPdf],
              fileIcon: Icons.image,
              fileIconColor: Colors.pink,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resize image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_isProcessing && !_isLoadingImage && _selectedFile != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Resize Image'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Resizing your image...')
          : _isLoadingImage
              ? const ToolProcessingView(message: 'Loading image...')
          : _selectedFile == null
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  children: [
                    ToolSectionCard(
                      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedFile!,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              cacheWidth: 168,
                              errorBuilder: (_, _, _) => const DocumentIcon(
                                icon: Icons.photo_size_select_large_rounded,
                                color: AppColors.toolResize,
                                size: 56,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedFile!.path.split('/').last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$_originalWidth × $_originalHeight px',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _pickImage,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.brandRed,
                              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                            ),
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ToolSectionCard(
                      title: 'Dimensions',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Lock ratio', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                          Switch(
                            value: _keepAspectRatio,
                            onChanged: (v) => setState(() => _keepAspectRatio = v),
                            activeThumbColor: Colors.white,
                            activeTrackColor: AppColors.brandRed,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _widthController,
                                  keyboardType: TextInputType.number,
                                  decoration: toolInputDecoration(label: 'Width (px)'),
                                  onChanged: _onWidthChanged,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text('×', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
                              ),
                              Expanded(
                                child: TextFormField(
                                  controller: _heightController,
                                  keyboardType: TextInputType.number,
                                  decoration: toolInputDecoration(label: 'Height (px)'),
                                  onChanged: _onHeightChanged,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Presets',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presets.map((preset) {
                              final active = _widthController.text == preset['w'].toString() &&
                                  _heightController.text == preset['h'].toString();
                              return ChoiceChip(
                                label: Text(preset['label'] as String),
                                selected: active,
                                showCheckmark: false,
                                labelStyle: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: active ? AppColors.brandRed : AppColors.textPrimary,
                                ),
                                backgroundColor: const Color(0xFFF3F4F6),
                                selectedColor: AppColors.brandRed.withValues(alpha: 0.1),
                                side: BorderSide(color: active ? AppColors.brandRed : Colors.transparent),
                                shape: const StadiumBorder(),
                                onSelected: (_) {
                                  setState(() {
                                    _widthController.text = preset['w'].toString();
                                    _heightController.text = preset['h'].toString();
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ToolSectionCard(
                      title: 'Output',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: toolInputDecoration(hint: 'File name', icon: Icons.edit_document),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Format',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<ResizeFormat>(
                              segments: const [
                                ButtonSegment(value: ResizeFormat.jpeg, label: Text('JPEG')),
                                ButtonSegment(value: ResizeFormat.png, label: Text('PNG')),
                              ],
                              selected: {_format},
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: AppColors.brandRed.withValues(alpha: 0.1),
                                selectedForegroundColor: AppColors.brandRed,
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.border),
                                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              onSelectionChanged: (s) => setState(() => _format = s.first),
                            ),
                          ),
                          if (_format == ResizeFormat.jpeg) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Text(
                                  'Quality',
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                ),
                                const Spacer(),
                                Text(
                                  '${_quality.round()}%',
                                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppColors.brandRed,
                                thumbColor: AppColors.brandRed,
                                inactiveTrackColor: AppColors.brandRed.withValues(alpha: 0.15),
                                overlayColor: AppColors.brandRed.withValues(alpha: 0.1),
                                valueIndicatorColor: AppColors.brandRed,
                              ),
                              child: Slider(
                                value: _quality,
                                min: 10,
                                max: 100,
                                divisions: 9,
                                label: '${_quality.round()}%',
                                onChanged: (v) => setState(() => _quality = v),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: ready
          ? ToolBottomBar(
              child: ToolPrimaryButton(
                label: 'Resize Image',
                icon: Icons.photo_size_select_large_rounded,
                onPressed: _resize,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return ToolEmptyWithAd(
      empty: ToolEmptyState(
        icon: Icons.photo_size_select_large_rounded,
        color: AppColors.toolResize,
        title: 'Select Image to Resize',
        message: 'Choose an image from your gallery to resize to your desired dimensions.',
        buttonLabel: 'Select Image',
        buttonIcon: Icons.image_rounded,
        onPressed: _pickImage,
      ),
      ad: const NativeAdWidget(),
    );
  }
}
