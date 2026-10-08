import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;

  Future<void> _pick(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked != null) {
      setState(() => _photo = picked);
    }
  }

  Widget _preview() {
    if (kIsWeb) {
      return Image.network(_photo!.path, fit: BoxFit.contain);
    }
    return Image.file(File(_photo!.path), fit: BoxFit.contain);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Back Photo'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _photo == null ? _buildGuidelines() : _buildReview(),
        ),
      ),
    );
  }

  Widget _buildGuidelines() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Photo guidelines',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Patient stands straight, feet together'),
                SizedBox(height: 8),
                Text('• Back faces the camera'),
                SizedBox(height: 8),
                Text('• Upper back clearly visible (no loose clothing)'),
                SizedBox(height: 8),
                Text('• Whole back from neck to hips is in the frame'),
                SizedBox(height: 8),
                Text('• Good lighting, plain background'),
                SizedBox(height: 8),
                Text('• Camera held level with the middle of the back'),
              ],
            ),
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Take Photo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Choose from Gallery'),
        ),
      ],
    );
  }

  Widget _buildReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Is the image clear and within the guidelines?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Expanded(child: _preview()),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => context.go('/screening/test'),
          child: const Text('Yes, continue'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _photo = null),
          child: const Text('No, retake'),
        ),
      ],
    );
  }
}
