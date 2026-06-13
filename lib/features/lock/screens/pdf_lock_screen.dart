import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/pdf_lock_service.dart';
import '../../pdf/screens/success_screen.dart';

class PdfLockScreen extends StatefulWidget {
  const PdfLockScreen({super.key});

  @override
  State<PdfLockScreen> createState() => _PdfLockScreenState();
}

class _PdfLockScreenState extends State<PdfLockScreen> {
  File? _selectedFile;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  bool _isProcessing = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final filePath = result.files.first.path!;
        final file = File(filePath);

        setState(() {
          _selectedFile = file;
          _nameController.text = '${file.path.split('/').last.replaceAll('.pdf', '')}_locked';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _lockPdf() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file to lock.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final outputName = _nameController.text.trim();

      final lockedFile = await PdfLockService.lockPdf(
        sourcePath: _selectedFile!.path,
        password: _passwordController.text,
        outputName: outputName,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(pdfFile: lockedFile),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to lock PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Lock PDF', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'Encrypting PDF offline, please wait...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : _selectedFile == null
              ? _buildEmptyState()
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
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
                                'Selected File',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blueGrey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.picture_as_pdf, color: Colors.blueGrey),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      _selectedFile!.path.split('/').last,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh, color: Colors.blueAccent),
                                    onPressed: _pickFile,
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
                              const Text('File Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'File Name',
                                  prefixIcon: const Icon(Icons.edit_document),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  suffixText: '.pdf',
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a name';
                                  }
                                  return null;
                                },
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
                              const Text('Set Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text(
                                'Your PDF will be encrypted with AES-256 bit encryption.',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter a password';
                                  }
                                  if (value.length < 4) {
                                    return 'Password must be at least 4 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please confirm your password';
                                  }
                                  if (value != _passwordController.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),

                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 2,
                            ),
                            onPressed: _lockPdf,
                            child: const Text('Lock PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
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
                color: Colors.blueGrey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                color: Colors.blueGrey,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select PDF to Lock',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a PDF file from your device storage to password protect it with AES-256 encryption.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _pickFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text(
                  'Select PDF',
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
