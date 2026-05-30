import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import '../providers/video_editor_provider.dart';
import '../services/media_picker_service.dart';
import '../main.dart' show AppColors;
import 'modern_slider.dart';

class ChromaKeyEditor extends StatefulWidget {
  const ChromaKeyEditor({super.key});

  @override
  State<ChromaKeyEditor> createState() => _ChromaKeyEditorState();
}

class _ChromaKeyEditorState extends State<ChromaKeyEditor> {
  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final settings = provider.currentChromaKeySettings;
        final backgrounds = provider.chromaKeyBackgrounds;
        final activeBackground = provider.activeChromaKeyBackgroundPath;

        return Container(
          color: AppColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Chroma Key',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh,
                          color: AppColors.textTertiary, size: 18),
                      onPressed: () => provider.resetChromaKey(),
                      tooltip: 'Reset',
                      padding: const EdgeInsets.all(6),
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),

              // ── Scrollable body ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),

                      // ── Background Section ────────────────────────────────
                      const Text(
                        'Background',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),

                      // Upload buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.image_outlined,
                              label: 'Upload Image',
                              onPressed: () =>
                                  _pickBackground(isVideo: false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.videocam_outlined,
                              label: 'Upload Video',
                              onPressed: () =>
                                  _pickBackground(isVideo: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Current background preview
                      if (activeBackground != null) ...[
                        _buildBackgroundPreview(activeBackground, provider),
                        const SizedBox(height: 12),
                      ],

                      // Available backgrounds list
                      if (backgrounds.isNotEmpty) ...[
                        const Text(
                          'Available Backgrounds',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: backgrounds.length,
                            itemBuilder: (context, index) {
                              final path = backgrounds[index];
                              final isSelected = path == activeBackground;
                              final isVideo =
                                  provider.isChromaKeyBackgroundVideo(path);
                              return _buildBackgroundThumbnail(
                                path,
                                isSelected,
                                isVideo,
                                () => _selectBackground(path),
                                () => _removeBackground(path),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ── Key Color Section ─────────────────────────────────
                      const Text(
                        'Key Color',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      _buildColorPicker(settings?.keyColor, provider),

                      const SizedBox(height: 16),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ── Keying Parameters ─────────────────────────────────
                      const Text(
                        'Keying Parameters',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 12),

                      ModernSlider(
                        value: settings?.similarity ?? 0.3,
                        min: 0.0,
                        max: 0.6,
                        divisions: 60,
                        label: 'Similarity  (how aggressively the key color is removed)',
                        onChanged: (value) =>
                            provider.updateChromaKeySettings(
                                similarity: value),
                      ),
                      const SizedBox(height: 12),

                      ModernSlider(
                        value: settings?.blend ?? 0.05,
                        min: 0.0,
                        max: 0.5,
                        divisions: 50,
                        label: 'Blend  (edge softness / feathering)',
                        onChanged: (value) =>
                            provider.updateChromaKeySettings(blend: value),
                      ),

                      const SizedBox(height: 16),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ── Position & Scale ──────────────────────────────────
                      const Text(
                        'Position & Scale',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 12),

                      ModernSlider(
                        value: settings?.position.dx ?? 0.5,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: 'Position X',
                        onChanged: (value) =>
                            provider.updateChromaKeySettings(
                          position: Offset(
                              value, settings?.position.dy ?? 0.5),
                        ),
                      ),
                      const SizedBox(height: 12),

                      ModernSlider(
                        value: settings?.position.dy ?? 0.5,
                        min: 0.0,
                        max: 1.0,
                        divisions: 100,
                        label: 'Position Y',
                        onChanged: (value) =>
                            provider.updateChromaKeySettings(
                          position: Offset(
                              settings?.position.dx ?? 0.5, value),
                        ),
                      ),
                      const SizedBox(height: 12),

                      ModernSlider(
                        value: settings?.scale ?? 1.0,
                        min: 0.1,
                        max: 3.0,
                        divisions: 100,
                        label: 'Scale',
                        onChanged: (value) =>
                            provider.updateChromaKeySettings(scale: value),
                      ),

                      const SizedBox(height: 16),
                      Container(height: 1, color: AppColors.border),
                      const SizedBox(height: 16),

                      // ── Tips ──────────────────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tips_and_updates_outlined,
                                    color: AppColors.primary, size: 16),
                                const SizedBox(width: 8),
                                const Text(
                                  'Tips for best results',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '• Start with Similarity ~0.30 and Blend ~0.05\n'
                              '• Increase Similarity to remove more green\n'
                              '• Increase Blend to soften harsh edges\n'
                              '• Effect is applied at export time',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Apply Button ──────────────────────────────────────
                      _buildApplyButton(provider),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Apply button ──────────────────────────────────────────────────────────
  Widget _buildApplyButton(VideoEditorProvider provider) {
    final isProcessing = provider.isChromaKeyProcessing;

    if (isProcessing) {
      return Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: provider.chromaKeyProcessingProgress,
              backgroundColor: AppColors.surfaceLight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Processing… ${(provider.chromaKeyProcessingProgress * 100).toInt()}%',
            style: const TextStyle(
                color: AppColors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => provider.cancelChromaKeyProcessing(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.red, size: 16),
                  SizedBox(width: 6),
                  Text('Cancel',
                      style: TextStyle(color: Colors.red, fontSize: 12)),
                ],
              ),
            ),
          ),
          if (provider.chromaKeyProcessingError != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                provider.chromaKeyProcessingError!,
                style: const TextStyle(color: Colors.red, fontSize: 11),
              ),
            ),
          ],
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _applyChromaKey(provider),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                color: AppColors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Apply Chroma Key',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Apply logic (unchanged) ────────────────────────────────────────────────
  Future<void> _applyChromaKey(VideoEditorProvider provider) async {
    final success = await provider.applyChromaKey(
      onProgress: (progress) {
        // Progress is handled in the provider
      },
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chroma key applied successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        provider.toggleChromaKeyEditor();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to apply chroma key: ${provider.chromaKeyProcessingError}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Upload button ──────────────────────────────────────────────────────────
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.border.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, color: AppColors.textSecondary, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Current background preview ─────────────────────────────────────────────
  Widget _buildBackgroundPreview(
      String path, VideoEditorProvider provider) {
    final isVideo = provider.isChromaKeyBackgroundVideo(path);
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(10)),
            child: SizedBox(
              width: 80,
              height: 60,
              child: isVideo
                  ? const Icon(Icons.videocam_outlined,
                      color: AppColors.textTertiary, size: 28)
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textTertiary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.basename(path),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                color: AppColors.textTertiary, size: 18),
            onPressed: () => provider.updateChromaKeySettings(
              backgroundPath: null,
              isBackgroundVideo: false,
            ),
          ),
        ],
      ),
    );
  }

  // ── Background thumbnail strip ─────────────────────────────────────────────
  Widget _buildBackgroundThumbnail(
    String path,
    bool isSelected,
    bool isVideo,
    VoidCallback onTap,
    VoidCallback onRemove,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
                child: isVideo
                    ? Container(
                        color: AppColors.surfaceLight,
                        child: const Icon(Icons.videocam_outlined,
                            color: AppColors.textTertiary, size: 28),
                      )
                    : Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surfaceLight,
                          child: const Icon(Icons.broken_image_outlined,
                              color: AppColors.textTertiary),
                        ),
                      ),
              ),
            ),
            // Remove button
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 10),
                ),
              ),
            ),
            if (isVideo)
              const Positioned(
                bottom: 4,
                left: 4,
                child: Icon(Icons.play_circle_filled,
                    color: Colors.white, size: 14),
              ),
          ],
        ),
      ),
    );
  }

  // ── Color picker ───────────────────────────────────────────────────────────
  Widget _buildColorPicker(Color? currentColor, VideoEditorProvider provider) {
    final colors = [
      const Color(0xFF00FF00), // Green
      const Color(0xFF0000FF), // Blue
      const Color(0xFFFFFF00), // Yellow
      const Color(0xFFFF00FF), // Magenta
      const Color(0xFF00FFFF), // Cyan
      const Color(0xFFFF0000), // Red
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: colors.map((color) {
        final isSelected =
            currentColor?.toARGB32() == color.toARGB32();
        return GestureDetector(
          onTap: () =>
              provider.updateChromaKeySettings(keyColor: color),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    isSelected ? AppColors.textPrimary : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: color.a * 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Picker / select / remove (logic unchanged) ────────────────────────────
  Future<void> _pickBackground({required bool isVideo}) async {
    try {
      final provider = context.read<VideoEditorProvider>();
      final media = await MediaPickerService.open(
        context,
        mediaFilter: isVideo ? 'video' : 'image',
      );
      if (media != null) {
        final file = await media.getFile();
        await provider.setChromaKeyBackground(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  void _selectBackground(String path) {
    final provider = context.read<VideoEditorProvider>();
    final isVideo = provider.isChromaKeyBackgroundVideo(path);
    provider.updateChromaKeySettings(
      backgroundPath: path,
      isBackgroundVideo: isVideo,
    );
  }

  void _removeBackground(String path) {
    final provider = context.read<VideoEditorProvider>();
    provider.removeChromaKeyBackground(path);
  }
}
