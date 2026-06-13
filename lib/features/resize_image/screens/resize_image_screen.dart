import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../services/resize_image_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';

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

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final file = File(image.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      if (decoded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to decode image.')),
          );
        }
        return;
      }

      setState(() {
        _selectedFile = file;
        _originalWidth = decoded.width;
        _originalHeight = decoded.height;
        _widthController.text = decoded.width.toString();
        _heightController.text = decoded.height.toString();
        _nameController.text = file.path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Resize Image', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(height: 16),
                  Text(
                    'Resizing image, please wait...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : _selectedFile == null
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Image',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.image, color: Colors.pink),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedFile!.path.split('/').last,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$_originalWidth x $_originalHeight px',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                                  onPressed: _pickImage,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Dimensions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Lock ratio', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                    Switch(
                                      value: _keepAspectRatio,
                                      onChanged: (v) => setState(() => _keepAspectRatio = v),
                                      activeColor: Colors.blueAccent,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _widthController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Width (px)',
                                      prefixIcon: const Icon(Icons.arrow_right_alt),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onChanged: _onWidthChanged,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('x', style: TextStyle(fontSize: 20, color: Colors.grey.shade600)),
                                ),
                                Expanded(
                                  child: TextFormField(
                                    controller: _heightController,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Height (px)',
                                      prefixIcon: const Icon(Icons.arrow_downward),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onChanged: _onHeightChanged,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Presets', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _presets.map((preset) {
                                return ActionChip(
                                  label: Text(preset['label'] as String, style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
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
                      const SizedBox(height: 24),

                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Output Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'File Name',
                                prefixIcon: const Icon(Icons.edit_document),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Text('Format:', style: TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(width: 16),
                                SegmentedButton<ResizeFormat>(
                                  segments: const [
                                    ButtonSegment(value: ResizeFormat.jpeg, label: Text('JPEG'), icon: Icon(Icons.image, size: 18)),
                                    ButtonSegment(value: ResizeFormat.png, label: Text('PNG'), icon: Icon(Icons.image_outlined, size: 18)),
                                  ],
                                  selected: {_format},
                                  onSelectionChanged: (s) => setState(() => _format = s.first),
                                ),
                              ],
                            ),
                            if (_format == ResizeFormat.jpeg) ...[
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Text('Quality:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Expanded(
                                    child: Slider(
                                      value: _quality,
                                      min: 10,
                                      max: 100,
                                      divisions: 9,
                                      label: '${_quality.round()}%',
                                      onChanged: (v) => setState(() => _quality = v),
                                    ),
                                  ),
                                  Text('${_quality.round()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pink,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 2,
                          ),
                          onPressed: _resize,
                          child: const Text('Resize Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.pink.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.photo_size_select_large,
                color: Colors.pink,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select Image to Resize',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an image from your gallery to resize to your desired dimensions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _pickImage,
                icon: const Icon(Icons.image),
                label: const Text(
                  'Select Image',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
