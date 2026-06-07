import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import '../services/pdf_service.dart';
import 'success_screen.dart';

class PdfSettingsScreen extends StatefulWidget {
  final String? buttonText;
  const PdfSettingsScreen({super.key, this.buttonText});

  @override
  State<PdfSettingsScreen> createState() => _PdfSettingsScreenState();
}

class _PdfSettingsScreenState extends State<PdfSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  PdfPageFormat _selectedFormat = PdfPageFormat.a4;
  bool _isLandscape = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    String defaultName = 'Scan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    _nameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generateAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isGenerating = true);
    
    try {
      final provider = Provider.of<ScanProvider>(context, listen: false);
      
      PdfPageFormat format = _selectedFormat;
      if (_isLandscape) {
        format = format.landscape;
      }

      final file = await PdfService.generatePdf(
        fileName: _nameController.text,
        pages: provider.pages,
        format: format,
        toolType: provider.toolType,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SuccessScreen(pdfFile: file)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('PDF Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
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
                        if (value == null || value.isEmpty) {
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
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Page Setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PdfPageFormat>(
                      value: _selectedFormat,
                      decoration: InputDecoration(
                        labelText: 'Page Size',
                        prefixIcon: const Icon(Icons.pages),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: const [
                        DropdownMenuItem(value: PdfPageFormat.a4, child: Text("A4")),
                        DropdownMenuItem(value: PdfPageFormat.letter, child: Text("Letter")),
                        DropdownMenuItem(value: PdfPageFormat.legal, child: Text("Legal")),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedFormat = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Landscape Orientation', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Rotate pages horizontally', style: TextStyle(fontSize: 12)),
                      value: _isLandscape,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => _isLandscape = val),
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
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  onPressed: _isGenerating ? null : _generateAndSave,
                  child: _isGenerating 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : Text(widget.buttonText ?? 'Generate PDF', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
