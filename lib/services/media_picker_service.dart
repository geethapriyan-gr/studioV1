import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart' show AppColors;
import '../widgets/asset_media_library.dart';

/// Returns true if the given file extension is a video format.
bool _isVideoExt(String? ext) {
  if (ext == null) return false;
  return ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm']
      .contains(ext.toLowerCase());
}

/// Represents a picked media item with its source info.
class PickedMedia {
  /// File path — either an asset path (String) or a device file path.
  final String path;

  /// Whether this media came from the bundled asset library.
  final bool isAsset;

  /// Whether this media is a video (vs image).
  final bool isVideo;

  const PickedMedia({
    required this.path,
    required this.isAsset,
    required this.isVideo,
  });

  /// Convenience: get a [File] for the media. Handles copying assets to temp dir.
  Future<File> getFile() async {
    if (!isAsset) return File(path);
    // Copy asset to temp directory
    final byteData = await rootBundle.load(path);
    final tempDir = await getTemporaryDirectory();
    final fileName = path.split('/').last;
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    ));
    return tempFile;
  }

  @override
  String toString() =>
      'PickedMedia(path: $path, isAsset: $isAsset, isVideo: $isVideo)';
}

/// Global media picker service used across the entire app.
class MediaPickerService {
  MediaPickerService._();

  /// Opens the universal media picker popup (single-select).
  ///
  /// Returns a [PickedMedia] if the user selected something, or `null`
  /// if they dismissed the picker.
  ///
  /// [mediaFilter] — optionally restrict to 'image' or 'video'.
  static Future<PickedMedia?> open(
    BuildContext context, {
    String? mediaFilter,
  }) async {
    final list = await openMultiple(context, mediaFilter: mediaFilter);
    return list?.isNotEmpty == true ? list!.first : null;
  }

  /// Opens the universal media picker popup with **multi-select** support.
  ///
  /// Returns a non-empty [List<PickedMedia>] on success, or `null` if the
  /// user dismissed the picker without selecting anything.
  static Future<List<PickedMedia>?> openMultiple(
    BuildContext context, {
    String? mediaFilter,
  }) async {
    return await showModalBottomSheet<List<PickedMedia>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _MediaPickerPopup(mediaFilter: mediaFilter),
    );
  }

  /// Pick a video from device gallery using image_picker.
  static Future<File?> pickVideoFromGallery() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return File(file.path);
  }

  /// Pick an image from device gallery using image_picker.
  static Future<File?> pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return File(file.path);
  }

  /// Pick multiple media files (images and/or videos) from the device gallery.
  ///
  /// Uses [FilePicker] so the native system picker handles multi-select.
  /// Returns a non-empty list on success, or null if cancelled.
  static Future<List<PickedMedia>?> pickMultipleFromGallery({
    String? mediaFilter,
  }) async {
    FilePickerResult? result;

    if (mediaFilter == 'video') {
      result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
      );
    } else if (mediaFilter == 'image') {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
    } else {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm',
          'jpg', 'jpeg', 'png', 'gif', 'bmp', 'heic', 'heif', 'webp',
        ],
        allowMultiple: true,
      );
    }

    if (result == null || result.files.isEmpty) return null;

    final picked = <PickedMedia>[];
    for (final f in result.files) {
      final filePath = f.path;
      if (filePath == null) continue;
      final isVideo = _isVideoExt(f.extension);
      picked.add(PickedMedia(path: filePath, isAsset: false, isVideo: isVideo));
    }
    return picked.isEmpty ? null : picked;
  }

  /// Pick any media (image or video) from device gallery (single file, legacy).
  static Future<File?> pickFromGallery(BuildContext context) async {
    final list = await pickMultipleFromGallery();
    if (list == null || list.isEmpty) return null;
    return File(list.first.path);
  }
}

/// Internal popup widget that displays the picker options.
/// Returns a [List<PickedMedia>] to support multi-select.
class _MediaPickerPopup extends StatelessWidget {
  final String? mediaFilter;

  const _MediaPickerPopup({this.mediaFilter});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surfaceLighter,
            AppColors.surface,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: AppColors.border.withOpacity(0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.2),
                        AppColors.accent.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.perm_media_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload Media',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Choose your media source',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Option 1: Media Library (Assets)
          _MediaOptionTile(
            icon: Icons.video_library_rounded,
            title: 'Media Library',
            subtitle: 'Browse built-in images & videos',
            gradientColors: [
              AppColors.primary,
              AppColors.primaryLight,
            ],
            onTap: () async {
              final media = await Navigator.push<PickedMedia>(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => AssetMediaLibrary(
                    mediaFilter: mediaFilter,
                  ),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      )),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
              if (media != null && context.mounted) {
                Navigator.pop(context, [media]);
              }
            },
          ),

          // Option 2: Import From Gallery (multi-select)
          _MediaOptionTile(
            icon: Icons.photo_library_rounded,
            title: 'Import From Gallery',
            subtitle: 'Select one or more photos & videos',
            gradientColors: [
              AppColors.accent,
              Color(0xFF06D4A0),
            ],
            onTap: () async {
              final picked = await MediaPickerService.pickMultipleFromGallery(
                mediaFilter: mediaFilter,
              );
              if (picked != null && picked.isNotEmpty && context.mounted) {
                Navigator.pop(context, picked);
              }
            },
          ),

          // Option 3: Import From Drive (multi-select)
          _MediaOptionTile(
            icon: Icons.add_to_drive_rounded,
            title: 'Import From Drive',
            subtitle: 'Select from your Google Drive',
            gradientColors: const [
              Color(0xFF4285F4),
              Color(0xFF0F9D58),
            ],
            onTap: () async {
              FilePickerResult? result;

              if (mediaFilter == 'video') {
                result = await FilePicker.platform
                    .pickFiles(type: FileType.video, allowMultiple: true);
              } else if (mediaFilter == 'image') {
                result = await FilePicker.platform
                    .pickFiles(type: FileType.image, allowMultiple: true);
              } else {
                result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: [
                    'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm',
                    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'heic', 'heif', 'webp',
                  ],
                  allowMultiple: true,
                );
              }

              if (result != null && result.files.isNotEmpty && context.mounted) {
                final picked = result.files
                    .where((f) => f.path != null)
                    .map((f) => PickedMedia(
                          path: f.path!,
                          isAsset: false,
                          isVideo: _isVideoExt(f.extension),
                        ))
                    .toList();
                if (picked.isNotEmpty) {
                  Navigator.pop(context, picked);
                }
              }
            },
          ),

          const SizedBox(height: 16),

          // Cancel button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border.withOpacity(0.5)),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

/// A single option tile in the media picker popup.
class _MediaOptionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _MediaOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_MediaOptionTile> createState() => _MediaOptionTileState();
}

class _MediaOptionTileState extends State<_MediaOptionTile> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(_isPressed ? 0.97 : 1.0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isPressed
                ? AppColors.surfaceLighter.withOpacity(0.8)
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isPressed
                  ? widget.gradientColors.first.withOpacity(0.4)
                  : AppColors.border.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: _isPressed
                ? [
                    BoxShadow(
                      color: widget.gradientColors.first.withOpacity(0.1),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Icon with gradient background
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.gradientColors
                        .map((c) => c.withOpacity(0.2))
                        .toList(),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.gradientColors.first,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textTertiary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gallery type option widget used in the type chooser.
class _GalleryTypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GalleryTypeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.2), width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: color.withOpacity(0.5),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
