import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../main.dart' show AppColors;

class StickerLayer extends StatelessWidget {
  const StickerLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context);
    final stickers = provider.currentStickers;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: stickers
              .map((sticker) => _DraggableStickerWidget(
                    key: ValueKey(sticker.id),
                    sticker: sticker,
                    constraints: constraints,
                  ))
              .toList(),
        );
      },
    );
  }
}

class _DraggableStickerWidget extends StatefulWidget {
  final StickerModel sticker;
  final BoxConstraints constraints;

  const _DraggableStickerWidget({
    super.key,
    required this.sticker,
    required this.constraints,
  });

  @override
  State<_DraggableStickerWidget> createState() =>
      _DraggableStickerWidgetState();
}

class _DraggableStickerWidgetState extends State<_DraggableStickerWidget> {
  Offset? _localPosition;
  double _pinchScale = 1.0;
  double _baseScale = 1.0;

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final isSelected = provider.selectedStickerId == widget.sticker.id;
    final position = _localPosition ?? widget.sticker.position;

    // Default base size increased significantly for better visibility
    const double baseSize = 600.0;
    final effectiveSize = baseSize * widget.sticker.scale * _pinchScale;

    return Positioned(
      left: position.dx * widget.constraints.maxWidth - (effectiveSize / 2),
      top: position.dy * widget.constraints.maxHeight - (effectiveSize / 2),
      child: GestureDetector(
        onTap: () => provider.selectSticker(widget.sticker.id),
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          provider.selectSticker(widget.sticker.id);
          _localPosition = widget.sticker.position;
          _baseScale = _pinchScale;
          provider.recordUndo();
        },
        onScaleUpdate: (details) {
          setState(() {
            if (details.scale != 1.0) {
              _pinchScale = (_baseScale * details.scale).clamp(0.1, 10.0);
            }

            final currentX = _localPosition!.dx * widget.constraints.maxWidth;
            final currentY = _localPosition!.dy * widget.constraints.maxHeight;

            final newX = currentX + details.focalPointDelta.dx;
            final newY = currentY + details.focalPointDelta.dy;

            _localPosition = Offset(
              (newX / widget.constraints.maxWidth).clamp(0.0, 1.0),
              (newY / widget.constraints.maxHeight).clamp(0.0, 1.0),
            );
          });
        },
        onScaleEnd: (details) {
          final finalScale =
              (widget.sticker.scale * _pinchScale).clamp(0.1, 10.0);
          provider.updateSticker(
            widget.sticker.id,
            position: _localPosition,
            scale: finalScale,
          );
          _localPosition = null;
          _pinchScale = 1.0;
          _baseScale = 1.0;
        },
        child: Transform.rotate(
          angle: widget.sticker.rotation,
          child: Container(
            width: effectiveSize,
            height: effectiveSize,
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: AppColors.primary, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  widget.sticker.assetPath,
                  fit: BoxFit.contain,
                  opacity: AlwaysStoppedAnimation(widget.sticker.opacity),
                ),
                if (isSelected)
                  _buildStickerControls(
                      context, provider, widget.sticker, effectiveSize),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStickerControls(
    BuildContext context,
    VideoEditorProvider provider,
    StickerModel sticker,
    double size,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Delete button
        Positioned(
          top: -20,
          right: -20,
          child: GestureDetector(
            onTap: () => provider.removeSticker(sticker.id),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 24),
            ),
          ),
        ),
        // Duplicate button
        Positioned(
          bottom: -20,
          right: -20,
          child: GestureDetector(
            onTap: () => _duplicateSticker(provider, sticker),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
              ),
              child: const Icon(Icons.copy, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  void _duplicateSticker(VideoEditorProvider provider, StickerModel sticker) {
    provider.addSticker(
      assetPath: sticker.assetPath,
      position: Offset(
        (sticker.position.dx + 0.05).clamp(0.0, 1.0),
        (sticker.position.dy + 0.05).clamp(0.0, 1.0),
      ),
      scale: sticker.scale,
      rotation: sticker.rotation,
      startTime: sticker.startTime,
      endTime: sticker.endTime,
      opacity: sticker.opacity,
    );
  }
}
