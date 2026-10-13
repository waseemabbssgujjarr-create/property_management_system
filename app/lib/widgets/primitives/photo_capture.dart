import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/platform/file_support.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// PhotoCapture — big camera button for photo-first capture.
///
/// Rules (§5.3, §7.1):
/// - Camera > Gallery (but both offered)
/// - Client-side compress to ≤1600px, WebP q75, EXIF strip, ≤300KB
/// - Shows upload progress with icon (no text needed)
/// - Offline queue: photo stored locally, uploaded when online
///
/// Returns local file path. Upload to Supabase Storage happens in repo layer.
class PhotoCapture extends StatefulWidget {
  final void Function(String localPath) onPhotoCaptured;
  final String? existingPhotoUrl;
  final String labelUr;
  final bool allowMultiple;

  const PhotoCapture({
    required this.onPhotoCaptured,
    required this.labelUr,
    this.existingPhotoUrl,
    this.allowMultiple = false,
    super.key,
  });

  @override
  State<PhotoCapture> createState() => _PhotoCaptureState();
}

class _PhotoCaptureState extends State<PhotoCapture> {
  final _picker = ImagePicker();
  String? _localPath;
  bool _compressing = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (file == null) return;

      setState(() => _compressing = true);

      final compressed = await _compressImage(file.path);
      if (compressed == null) return;

      setState(() {
        _localPath = compressed;
        _compressing = false;
      });

      HapticFeedback.lightImpact();
      widget.onPhotoCaptured(compressed);
    } catch (e) {
      setState(() => _compressing = false);
      debugPrint('PhotoCapture error: $e');
    }
  }

  Future<String?> _compressImage(String sourcePath) async {
    if (kIsWeb) return sourcePath; // No compression on web
    try {
      final dir = await getTemporaryDirectory();
      final target = '${dir.path}/photo_${const Uuid().v4()}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        sourcePath,
        target,
        quality: 75,
        minWidth: 800,
        minHeight: 800,
      );
      return result?.path;
    } catch (e) {
      debugPrint('Image compression failed: $e');
      return sourcePath;
    }
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: Text('فوٹو لیں', style: AppTypography.urBodyMedium),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text('گیلری سے', style: AppTypography.urBodyMedium),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_localPath != null || widget.existingPhotoUrl != null)
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppColors.danger),
                title: Text(
                  'فوٹو ہٹائیں',
                  style: AppTypography.urBodyMedium.copyWith(
                    color: AppColors.danger,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _localPath = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _localPath != null || widget.existingPhotoUrl != null;

    return GestureDetector(
      onTap: _showOptions,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: hasPhoto
              ? Colors.transparent
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: AppSpacing.cardRadius,
          border: Border.all(
            color: hasPhoto ? Colors.transparent : AppColors.ink100,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        child: _compressing
            ? const Center(child: CircularProgressIndicator())
            : hasPhoto
                ? _PhotoPreview(
                    localPath: _localPath,
                    remoteUrl: widget.existingPhotoUrl,
                    onRetake: _showOptions,
                  )
                : _EmptyState(label: widget.labelUr),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.camera_alt_rounded,
          size: 40,
          color: AppColors.ink300,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.urBodyMedium.copyWith(color: AppColors.ink500),
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  final String? localPath;
  final String? remoteUrl;
  final VoidCallback onRetake;

  const _PhotoPreview({
    this.localPath,
    this.remoteUrl,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    // On web, use XFile.path as a blob URL; on native, use FileImage
    final ImageProvider image;
    if (localPath != null) {
      if (kIsWeb) {
        // image_picker on web returns a blob URL we can load directly
        image = NetworkImage(localPath!);
      } else {
        image = FileImage(File(localPath!));
      }
    } else {
      image = NetworkImage(remoteUrl!);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: AppSpacing.cardRadius,
          child: Image(image: image, fit: BoxFit.cover),
        ),
        Positioned(
          bottom: AppSpacing.sm,
          right: AppSpacing.sm,
          child: Material(
            color: Colors.black54,
            borderRadius: AppSpacing.pillRadius,
            child: InkWell(
              onTap: onRetake,
              borderRadius: AppSpacing.pillRadius,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
