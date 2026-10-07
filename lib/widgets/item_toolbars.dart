import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppColors;
import '../models/chroma_key_settings.dart';
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';
import '../utils/overlay_shapes.dart';
import '../utils/text_overlay_painter.dart';
import 'clip_toolbar.dart';
import 'length_prompt.dart';

// Bottom toolbars for selected timeline items (media overlays, text,
// stickers, audio), in the same style as the clip toolbar, and the sheets
// their tools open. Sheet sliders update live and form one undo step per
// drag.

void _snack(BuildContext context, String text, {VoidCallback? undo}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      action: undo == null ? null : SnackBarAction(label: 'UNDO', onPressed: undo),
    ));
}

String _secs(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';

String? _animBadge(String animIn, String animOut) =>
    animIn != 'none' || animOut != 'none' ? '•' : null;

String? _percentBadge(double v) => v < 0.995 ? '${(v * 100).round()}' : null;

/// Split at the playhead, with a hint when the playhead is outside.
void _split(BuildContext context, Duration start, Duration end,
    Duration playhead, VoidCallback split) {
  if (playhead <= start || playhead >= end) {
    _snack(context, 'Move the playhead inside the item to split it');
    return;
  }
  split();
}

// ═════════════════════════════════════════════════════════════════════════
// Toolbars
// ═════════════════════════════════════════════════════════════════════════

/// Tools for a selected media overlay (picture-in-picture).
class OverlayItemToolbar extends StatelessWidget {
  final VideoEditorProvider provider;
  final VideoClip clip;

  const OverlayItemToolbar(
      {super.key, required this.provider, required this.clip});

  @override
  Widget build(BuildContext context) {
    final isVideo = clip.mediaType == MediaType.video;
    final (layer, layers) = provider.overlayLayerOf(clip.id);
    final keyframes = clip.keyframes.length;
    final id = clip.id;
    final tools = <ToolbarTool>[
      ToolbarTool(Icons.content_cut_rounded, 'Split', () {
        _split(context, clip.startTime, clip.endTime, provider.currentPosition,
            () => provider.cutOverlayClip(id));
      }),
      if (isVideo)
        ToolbarTool(Icons.speed_rounded, 'Speed',
            () => ItemSheets.overlaySpeed(context, id),
            badge: (clip.playbackSpeed - 1).abs() > 0.001
                ? '${clip.playbackSpeed}x'
                : null),
      if (isVideo)
        ToolbarTool(
          clip.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          'Volume',
          () => ItemSheets.overlayVolume(context, id),
          badge: clip.isMuted ? 'off' : _percentBadge(clip.volume),
        ),
      ToolbarTool(Icons.opacity_rounded, 'Opacity',
          () => ItemSheets.overlayOpacity(context, id),
          badge: _percentBadge(clip.overlayOpacity)),
      ToolbarTool(Icons.crop_rounded, 'Crop',
          () => ItemSheets.overlayCrop(context, id),
          active: clip.cropRect != null),
      ToolbarTool(Icons.rotate_90_degrees_ccw_rounded, 'Rotate',
          () => ItemSheets.overlayRotate(context, id),
          badge: clip.rotation.abs() > 0.5 || clip.isMirrored ? '•' : null),
      ToolbarTool(Icons.interests_outlined, 'Shape',
          () => ItemSheets.overlayShape(context, id),
          active: OverlayShapes.isMasked(clip)),
      ToolbarTool(Icons.border_outer_rounded, 'Border',
          () => ItemSheets.overlayBorder(context, id),
          active: clip.hasBorder),
      ToolbarTool(Icons.blur_on_rounded, 'Shadow', () {
        provider.updateOverlayClipStyle(id, shadow: !clip.shadow);
      }, active: clip.shadow),
      ToolbarTool(Icons.filter_vintage_outlined, 'Chroma',
          () => ItemSheets.overlayChroma(context, id),
          active: clip.chromaKeySettings?.enabled == true),
      ToolbarTool(Icons.animation_rounded, 'Animate',
          () => ItemSheets.overlayAnimation(context, id),
          badge: _animBadge(clip.animIn, clip.animOut)),
      ToolbarTool(Icons.route_rounded, 'Motion',
          () => ItemSheets.motion(context, TimelineItemKind.overlay, id),
          badge: keyframes > 0 ? '$keyframes' : null, highlight: true),
      ToolbarTool(Icons.layers_outlined, 'Layer',
          () => ItemSheets.overlayLayer(context, id),
          badge: layers > 1 ? '${layer + 1}' : null),
      ToolbarTool(Icons.copy_rounded, 'Duplicate', () {
        provider.duplicateOverlayClip(id);
        _snack(context, 'Overlay duplicated');
      }),
      ToolbarTool(Icons.delete_outline_rounded, 'Delete', () {
        HapticFeedback.mediumImpact();
        provider.removeOverlayClip(id);
        _snack(context, 'Overlay deleted', undo: provider.undo);
      }, danger: true),
    ];
    return SelectionToolbar(
      title: isVideo ? 'Overlay' : 'Photo',
      subtitle: _secs(clip.endTime - clip.startTime),
      onClose: () => provider.selectOverlayClip(null),
      tools: tools,
    );
  }
}

/// Tools for a selected text overlay.
class TextItemToolbar extends StatelessWidget {
  final VideoEditorProvider provider;
  final TextOverlay overlay;

  const TextItemToolbar(
      {super.key, required this.provider, required this.overlay});

  @override
  Widget build(BuildContext context) {
    final id = overlay.id;
    final tools = <ToolbarTool>[
      ToolbarTool(Icons.edit_rounded, 'Edit', provider.toggleTextEditor,
          active: provider.showTextEditor),
      ToolbarTool(Icons.content_cut_rounded, 'Split', () {
        _split(context, overlay.startTime, overlay.endTime,
            provider.currentPosition, () => provider.cutTextOverlay(id));
      }),
      ToolbarTool(Icons.animation_rounded, 'Animate',
          () => ItemSheets.textAnimation(context, id),
          badge: _animBadge(overlay.animIn, overlay.animOut)),
      ToolbarTool(Icons.opacity_rounded, 'Opacity',
          () => ItemSheets.textOpacity(context, id),
          badge: _percentBadge(overlay.opacity)),
      ToolbarTool(Icons.rotate_90_degrees_ccw_rounded, 'Rotate',
          () => ItemSheets.textRotate(context, id),
          badge: overlay.rotation.abs() > 0.5
              ? '${overlay.rotation.round()}°'
              : null),
      ToolbarTool(Icons.route_rounded, 'Motion',
          () => ItemSheets.motion(context, TimelineItemKind.text, id),
          badge: overlay.keyframes.isNotEmpty
              ? '${overlay.keyframes.length}'
              : null,
          highlight: true),
      ToolbarTool(Icons.copy_rounded, 'Duplicate', () {
        provider.duplicateTextOverlay(id);
        _snack(context, 'Text duplicated');
      }),
      ToolbarTool(Icons.delete_outline_rounded, 'Delete', () {
        HapticFeedback.mediumImpact();
        provider.removeTextOverlay(id);
        _snack(context, 'Text deleted', undo: provider.undo);
      }, danger: true),
    ];
    final label = overlay.text.trim().replaceAll('\n', ' ');
    return SelectionToolbar(
      title: label.isEmpty ? 'Text' : label,
      subtitle: _secs(overlay.endTime - overlay.startTime),
      onClose: () => provider.selectTextOverlay(null),
      tools: tools,
      accent: AppColors.textTrack,
    );
  }
}

/// Tools for a selected sticker.
class StickerItemToolbar extends StatelessWidget {
  final VideoEditorProvider provider;
  final StickerModel sticker;

  const StickerItemToolbar(
      {super.key, required this.provider, required this.sticker});

  @override
  Widget build(BuildContext context) {
    final id = sticker.id;
    final degrees = sticker.rotation * 180 / math.pi;
    final tools = <ToolbarTool>[
      ToolbarTool(Icons.content_cut_rounded, 'Split', () {
        _split(context, sticker.startTime, sticker.endTime,
            provider.currentPosition, () => provider.cutSticker(id));
      }),
      ToolbarTool(Icons.opacity_rounded, 'Opacity',
          () => ItemSheets.stickerOpacity(context, id),
          badge: _percentBadge(sticker.opacity)),
      ToolbarTool(Icons.rotate_90_degrees_ccw_rounded, 'Rotate',
          () => ItemSheets.stickerRotate(context, id),
          badge: degrees.abs() > 0.5 ? '${degrees.round()}°' : null),
      ToolbarTool(Icons.flip_rounded, 'Flip', () {
        provider.updateSticker(id, flipX: !sticker.flipX);
      }, active: sticker.flipX),
      ToolbarTool(Icons.animation_rounded, 'Animate',
          () => ItemSheets.stickerAnimation(context, id),
          badge: _animBadge(sticker.animIn, sticker.animOut)),
      ToolbarTool(Icons.route_rounded, 'Motion',
          () => ItemSheets.motion(context, TimelineItemKind.sticker, id),
          badge: sticker.keyframes.isNotEmpty
              ? '${sticker.keyframes.length}'
              : null,
          highlight: true),
      ToolbarTool(Icons.layers_outlined, 'Layer',
          () => ItemSheets.stickerLayer(context, id)),
      ToolbarTool(Icons.copy_rounded, 'Duplicate', () {
        provider.duplicateSticker(id);
        _snack(context, 'Sticker duplicated');
      }),
      ToolbarTool(Icons.delete_outline_rounded, 'Delete', () {
        HapticFeedback.mediumImpact();
        provider.removeSticker(id);
        _snack(context, 'Sticker deleted', undo: provider.undo);
      }, danger: true),
    ];
    return SelectionToolbar(
      title: 'Sticker',
      subtitle: _secs(sticker.endTime - sticker.startTime),
      onClose: () => provider.selectSticker(null),
      tools: tools,
    );
  }
}

/// Tools for a selected audio clip.
class AudioItemToolbar extends StatelessWidget {
  final VideoEditorProvider provider;
  final AudioOverlay overlay;

  const AudioItemToolbar(
      {super.key, required this.provider, required this.overlay});

  @override
  Widget build(BuildContext context) {
    final id = overlay.id;
    final tools = <ToolbarTool>[
      ToolbarTool(Icons.volume_up_rounded, 'Volume',
          () => ItemSheets.audioVolume(context, id),
          badge: _percentBadge(overlay.volume)),
      ToolbarTool(Icons.trending_up_rounded, 'Fade in', () {
        provider.updateAudioOverlay(id, fadeIn: !overlay.fadeIn);
      }, active: overlay.fadeIn),
      ToolbarTool(Icons.trending_down_rounded, 'Fade out', () {
        provider.updateAudioOverlay(id, fadeOut: !overlay.fadeOut);
      }, active: overlay.fadeOut),
      ToolbarTool(Icons.content_cut_rounded, 'Split', () {
        _split(context, overlay.startTime, overlay.endTime,
            provider.currentPosition, () => provider.cutAudioOverlay(id));
      }),
      ToolbarTool(Icons.copy_rounded, 'Duplicate', () async {
        final before = provider.totalDuration;
        final copy = provider.duplicateAudioOverlay(id);
        await LengthPrompt.afterAdd(
            context, provider, before, TimelineItemKind.audio, copy);
      }),
      ToolbarTool(Icons.tune_rounded, 'Edit', provider.toggleAudioEditor,
          active: provider.showAudioEditor),
      ToolbarTool(Icons.delete_outline_rounded, 'Delete', () {
        HapticFeedback.mediumImpact();
        provider.removeAudioOverlay(id);
        _snack(context, 'Audio deleted', undo: provider.undo);
      }, danger: true),
    ];
    return SelectionToolbar(
      title: 'Audio',
      subtitle: _secs(overlay.endTime - overlay.startTime),
      onClose: () => provider.selectAudioOverlay(null),
      tools: tools,
      accent: AppColors.audioTrack,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Sheets
// ═════════════════════════════════════════════════════════════════════════

class ItemSheets {
  ItemSheets._();

  static Future<void> _show(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget? Function(VideoEditorProvider p) builder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Consumer<VideoEditorProvider>(
          builder: (ctx, provider, _) {
            // The item may be gone (deleted, undone): show nothing.
            final body = builder(provider);
            if (body == null) return const SizedBox(height: 120);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Icon(icon, color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Text(title,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 16),
                  body,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static TextOverlay? _text(VideoEditorProvider p, String id) {
    for (final t in p.currentProject?.textOverlays ?? const <TextOverlay>[]) {
      if (t.id == id) return t;
    }
    return null;
  }

  static StickerModel? _sticker(VideoEditorProvider p, String id) {
    for (final s in p.currentProject?.stickers ?? const <StickerModel>[]) {
      if (s.id == id) return s;
    }
    return null;
  }

  static AudioOverlay? _audio(VideoEditorProvider p, String id) {
    for (final a
        in p.currentProject?.audioOverlays ?? const <AudioOverlay>[]) {
      if (a.id == id) return a;
    }
    return null;
  }

  // ── Text ─────────────────────────────────────────────────────────────

  static Future<void> textAnimation(BuildContext context, String id) => _show(
        context,
        title: 'Text animation',
        icon: Icons.animation_rounded,
        builder: (p) {
          final t = _text(p, id);
          if (t == null) return null;
          return _AnimationBody(
            kinds: TextAnimations.all,
            animIn: t.animIn,
            animOut: t.animOut,
            onChanged: (i, o) =>
                p.updateTextOverlay(id, animIn: i, animOut: o),
          );
        },
      );

  static Future<void> textOpacity(BuildContext context, String id) => _show(
        context,
        title: 'Text opacity',
        icon: Icons.opacity_rounded,
        builder: (p) {
          final t = _text(p, id);
          if (t == null) return null;
          return _LiveSlider(
            value: t.opacity,
            min: 0.05,
            max: 1,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) => p.updateTextOverlay(id,
                opacity: v, undoKey: 'text-opacity:$id'),
            onChangeEnd: (_) => p.sealUndo(),
          );
        },
      );

  static Future<void> textRotate(BuildContext context, String id) => _show(
        context,
        title: 'Rotate text',
        icon: Icons.rotate_90_degrees_ccw_rounded,
        builder: (p) {
          final t = _text(p, id);
          if (t == null) return null;
          return _RotateBody(
            degrees: t.rotation,
            onChanged: (deg, live) => p.updateTextOverlay(id,
                rotation: deg, undoKey: live ? 'text-rotate:$id' : null),
            onChangeEnd: p.sealUndo,
          );
        },
      );

  // ── Stickers ─────────────────────────────────────────────────────────

  static Future<void> stickerOpacity(BuildContext context, String id) =>
      _show(
        context,
        title: 'Sticker opacity',
        icon: Icons.opacity_rounded,
        builder: (p) {
          final s = _sticker(p, id);
          if (s == null) return null;
          return _LiveSlider(
            value: s.opacity,
            min: 0.05,
            max: 1,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) => p.updateSticker(id,
                opacity: v, undoKey: 'sticker-opacity:$id'),
            onChangeEnd: (_) => p.sealUndo(),
          );
        },
      );

  static Future<void> stickerRotate(BuildContext context, String id) => _show(
        context,
        title: 'Rotate & flip',
        icon: Icons.rotate_90_degrees_ccw_rounded,
        builder: (p) {
          final s = _sticker(p, id);
          if (s == null) return null;
          return _RotateBody(
            degrees: s.rotation * 180 / math.pi,
            mirrored: s.flipX,
            onMirror: () => p.updateSticker(id, flipX: !s.flipX),
            onChanged: (deg, live) => p.updateSticker(id,
                rotation: deg * math.pi / 180,
                undoKey: live ? 'sticker-rotate:$id' : null),
            onChangeEnd: p.sealUndo,
          );
        },
      );

  static Future<void> stickerAnimation(BuildContext context, String id) =>
      _show(
        context,
        title: 'Sticker animation',
        icon: Icons.animation_rounded,
        builder: (p) {
          final s = _sticker(p, id);
          if (s == null) return null;
          return _AnimationBody(
            kinds: TextAnimations.motion,
            animIn: s.animIn,
            animOut: s.animOut,
            onChanged: (i, o) => p.updateSticker(id, animIn: i, animOut: o),
          );
        },
      );

  static Future<void> stickerLayer(BuildContext context, String id) => _show(
        context,
        title: 'Sticker layer',
        icon: Icons.layers_outlined,
        builder: (p) {
          final list = p.currentProject?.stickers ?? const <StickerModel>[];
          final i = list.indexWhere((s) => s.id == id);
          if (i == -1) return null;
          return _LayerBody(
            index: i,
            count: list.length,
            note: 'Stickers are drawn above text and media overlays.',
            onMove: (m) => p.moveStickerLayer(id, m),
          );
        },
      );

  // ── Audio ────────────────────────────────────────────────────────────

  static Future<void> audioVolume(BuildContext context, String id) => _show(
        context,
        title: 'Audio volume',
        icon: Icons.volume_up_rounded,
        builder: (p) {
          final a = _audio(p, id);
          if (a == null) return null;
          return _LiveSlider(
            value: a.volume.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 20,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) =>
                p.updateAudioOverlay(id, volume: v, undoKey: 'audio-vol:$id'),
            onChangeEnd: (_) => p.sealUndo(),
          );
        },
      );

  // ── Media overlays ───────────────────────────────────────────────────

  static const _speedPresets = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];

  static Future<void> overlaySpeed(BuildContext context, String id) => _show(
        context,
        title: 'Overlay speed',
        icon: Icons.speed_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _speedPresets)
                    ChoiceChip(
                      label: Text('${s}x'),
                      selected: (c.playbackSpeed - s).abs() < 0.001,
                      onSelected: (_) => p.setOverlayClipSpeed(id, s),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Length on the timeline: '
                '${_secs(c.endTime - c.startTime)}',
                style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
              ),
            ],
          );
        },
      );

  static Future<void> overlayVolume(BuildContext context, String id) => _show(
        context,
        title: 'Overlay volume',
        icon: Icons.volume_up_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () => p.toggleOverlayClipMute(id),
                  icon: Icon(c.isMuted
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded),
                  label: Text(c.isMuted ? 'Unmute' : 'Mute'),
                ),
              ]),
              _LiveSlider(
                value: c.volume.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                divisions: 20,
                enabled: !c.isMuted,
                label: (v) => c.isMuted ? 'Muted' : '${(v * 100).round()}%',
                onChanged: (_) {},
                onChangeEnd: (v) => p.updateOverlayClipVolume(id, v),
              ),
            ],
          );
        },
      );

  static Future<void> overlayOpacity(BuildContext context, String id) =>
      _show(
        context,
        title: 'Overlay opacity',
        icon: Icons.opacity_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return _LiveSlider(
            value: c.overlayOpacity,
            min: 0.05,
            max: 1,
            label: (v) => '${(v * 100).round()}%',
            onChanged: (v) => p.updateOverlayClipOpacity(id, v),
            onChangeEnd: (_) => p.sealUndo(),
          );
        },
      );

  static Future<void> overlayRotate(BuildContext context, String id) => _show(
        context,
        title: 'Rotate & flip',
        icon: Icons.rotate_90_degrees_ccw_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return _RotateBody(
            degrees: c.rotation,
            mirrored: c.isMirrored,
            onMirror: () =>
                p.updateOverlayClipStyle(id, isMirrored: !c.isMirrored),
            onChanged: (deg, live) => p.updateOverlayClipStyle(id,
                rotation: deg, undoKey: live ? 'overlay-rotate:$id' : null),
            onChangeEnd: p.sealUndo,
          );
        },
      );

  static Future<void> overlayCrop(BuildContext context, String id) => _show(
        context,
        title: 'Crop overlay',
        icon: Icons.crop_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          // Shape of the uncropped picture, from the box shape on screen.
          final crop = c.cropRect ?? const Rect.fromLTWH(0, 0, 1, 1);
          final boxAspect = c.overlaySize.width /
              c.overlaySize.height *
              p.canvasAspectAt(c.startTime);
          final mediaAspect = boxAspect / (crop.width / crop.height);
          return _CropBody(
            crop: c.cropRect,
            mediaAspect: mediaAspect,
            onChanged: (r) => p.setOverlayCrop(id, r),
          );
        },
      );

  static Future<void> overlayShape(BuildContext context, String id) => _show(
        context,
        title: 'Shape',
        icon: Icons.interests_outlined,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (key, label, icon) in OverlayShapes.all)
                _ChoiceTile(
                  icon: icon,
                  label: label,
                  selected: c.maskShape == key,
                  onTap: () => p.updateOverlayClipStyle(id, maskShape: key),
                ),
            ],
          );
        },
      );

  static const _borderColors = [
    Colors.white,
    Colors.black,
    Color(0xFFFACC15),
    Color(0xFFEC4899),
    Color(0xFF22D3EE),
    Color(0xFF7C3AED),
    Color(0xFF22C55E),
    Color(0xFFEF4444),
  ];

  static Future<void> overlayBorder(BuildContext context, String id) => _show(
        context,
        title: 'Border',
        icon: Icons.border_outer_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          final width = c.borderWidth > 0 ? c.borderWidth : 12.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Swatch(
                    color: null,
                    selected: !c.hasBorder,
                    onTap: () => p.updateOverlayClipStyle(id,
                        clearBorder: true, borderWidth: 0),
                  ),
                  for (final color in _borderColors)
                    _Swatch(
                      color: color,
                      selected: c.hasBorder &&
                          c.borderColor!.toARGB32() == color.toARGB32(),
                      onTap: () => p.updateOverlayClipStyle(id,
                          borderColor: color, borderWidth: width),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Thickness', style: TextStyle(color: AppColors.textSecondary)),
              _LiveSlider(
                value: width,
                min: 2,
                max: 48,
                enabled: c.hasBorder,
                label: (v) => '${v.round()} px',
                onChanged: (v) => p.updateOverlayClipStyle(id,
                    borderWidth: v, undoKey: 'overlay-border:$id'),
                onChangeEnd: (_) => p.sealUndo(),
              ),
            ],
          );
        },
      );

  static const _keyColors = [
    ('Green', Color(0xFF00FF00)),
    ('Studio green', Color(0xFF00B140)),
    ('Blue', Color(0xFF0000FF)),
    ('Black', Color(0xFF000000)),
    ('White', Color(0xFFFFFFFF)),
  ];

  static Future<void> overlayChroma(BuildContext context, String id) => _show(
        context,
        title: 'Green screen',
        icon: Icons.filter_vintage_outlined,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          final on = c.chromaKeySettings?.enabled == true;
          final s = c.chromaKeySettings ??
              const ChromaKeySettings(
                  enabled: true, similarity: 0.30, blend: 0.10);
          void set(ChromaKeySettings v, {String? undoKey}) =>
              p.setOverlayChromaKey(id, v, undoKey: undoKey);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Remove background colour',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: Text(
                    'Makes the chosen colour see-through, so the video '
                    'below shows.',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12)),
                value: on,
                onChanged: (v) => v
                    ? set(s.copyWith(enabled: true))
                    : p.setOverlayChromaKey(id, null),
              ),
              if (on) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, color) in _keyColors)
                      ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: color, radius: 8),
                        label: Text(label),
                        selected: s.keyColor.toARGB32() == color.toARGB32(),
                        onSelected: (_) => set(s.copyWith(keyColor: color)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Strength', style: TextStyle(color: AppColors.textSecondary)),
                _LiveSlider(
                  value: s.similarity,
                  min: 0.01,
                  max: 0.7,
                  label: (v) => '${(v * 100).round()}',
                  onChanged: (v) => set(s.copyWith(similarity: v),
                      undoKey: 'overlay-key-sim:$id'),
                  onChangeEnd: (_) => p.sealUndo(),
                ),
                Text('Edge softness',
                    style: TextStyle(color: AppColors.textSecondary)),
                _LiveSlider(
                  value: s.blend,
                  min: 0,
                  max: 0.5,
                  label: (v) => '${(v * 100).round()}',
                  onChanged: (v) => set(s.copyWith(blend: v),
                      undoKey: 'overlay-key-blend:$id'),
                  onChangeEnd: (_) => p.sealUndo(),
                ),
              ],
            ],
          );
        },
      );

  static Future<void> overlayAnimation(BuildContext context, String id) =>
      _show(
        context,
        title: 'Overlay animation',
        icon: Icons.animation_rounded,
        builder: (p) {
          final c = p.overlayClipById(id);
          if (c == null) return null;
          return _AnimationBody(
            kinds: TextAnimations.motion,
            animIn: c.animIn,
            animOut: c.animOut,
            onChanged: (i, o) =>
                p.updateOverlayClipStyle(id, animIn: i, animOut: o),
          );
        },
      );

  /// Motion keyframes for a media overlay, text or sticker.
  static Future<void> motion(
          BuildContext context, TimelineItemKind kind, String id) =>
      _show(
        context,
        title: 'Motion',
        icon: Icons.route_rounded,
        builder: (p) {
          final span = p.itemSpan(kind, id);
          if (span == null) return null;
          final count = p.keyframeCount(kind, id);
          final here = p.hasKeyframeAtPlayhead(kind, id);
          final inside =
              p.currentPosition >= span.$1 && p.currentPosition <= span.$2;
          final what = switch (kind) {
            TimelineItemKind.text => 'text',
            TimelineItemKind.sticker => 'sticker',
            _ => 'overlay',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count == 0
                    ? 'Make the $what move: add a keyframe, move the '
                        'playhead, then drag or pinch the $what. It glides '
                        'between keyframes.'
                    : '$count keyframes. With the playhead on the $what, '
                        'dragging or pinching it sets a keyframe at that '
                        'moment.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: inside && !here
                        ? () => p.addKeyframeAtPlayhead(kind, id)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Keyframe here'),
                  ),
                  OutlinedButton.icon(
                    onPressed: here
                        ? () => p.removeKeyframeAtPlayhead(kind, id)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                    label: const Text('Remove here'),
                  ),
                  TextButton.icon(
                    onPressed:
                        count == 0 ? null : () => p.clearKeyframes(kind, id),
                    icon: const Icon(Icons.clear_all_rounded),
                    label: const Text('Clear motion'),
                  ),
                ],
              ),
              if (!inside)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Move the playhead onto the $what first.',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12)),
                ),
            ],
          );
        },
      );

  static Future<void> overlayLayer(BuildContext context, String id) => _show(
        context,
        title: 'Overlay layer',
        icon: Icons.layers_outlined,
        builder: (p) {
          final (i, n) = p.overlayLayerOf(id);
          if (i == -1) return null;
          return _LayerBody(
            index: i,
            count: n,
            note: 'Higher layers are drawn on top of lower ones.',
            onMove: (m) => p.moveOverlayLayer(id, m),
          );
        },
      );
}

// ═════════════════════════════════════════════════════════════════════════
// Sheet bodies
// ═════════════════════════════════════════════════════════════════════════

/// Slider that shows its drag value immediately and reports changes.
class _LiveSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final bool enabled;
  final String Function(double) label;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _LiveSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    required this.onChangeEnd,
    this.divisions,
    this.enabled = true,
  });

  @override
  State<_LiveSlider> createState() => _LiveSliderState();
}

class _LiveSliderState extends State<_LiveSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: widget.enabled
                ? (x) {
                    setState(() => _drag = x);
                    widget.onChanged(x);
                  }
                : null,
            onChangeEnd: widget.enabled
                ? (x) {
                    setState(() => _drag = null);
                    HapticFeedback.selectionClick();
                    widget.onChangeEnd(x);
                  }
                : null,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(widget.label(v),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _AnimationBody extends StatelessWidget {
  final List<(String, String, IconData)> kinds;
  final String animIn;
  final String animOut;
  final void Function(String animIn, String animOut) onChanged;

  const _AnimationBody({
    required this.kinds,
    required this.animIn,
    required this.animOut,
    required this.onChanged,
  });

  Widget _row(String title, String value, ValueChanged<String> pick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (key, label, icon) in kinds)
              _ChoiceTile(
                icon: icon,
                label: label,
                selected: value == key,
                onTap: () => pick(key),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('In', animIn, (v) => onChanged(v, animOut)),
        const SizedBox(height: 16),
        _row('Out', animOut, (v) => onChanged(animIn, v)),
        const SizedBox(height: 10),
        Text('Plays in the preview while playing and in the export.',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      ],
    );
  }
}

class _RotateBody extends StatefulWidget {
  final double degrees;
  final bool? mirrored;
  final VoidCallback? onMirror;

  /// [live] is true while a slider is being dragged.
  final void Function(double degrees, bool live) onChanged;
  final VoidCallback onChangeEnd;

  const _RotateBody({
    required this.degrees,
    required this.onChanged,
    required this.onChangeEnd,
    this.mirrored,
    this.onMirror,
  });

  @override
  State<_RotateBody> createState() => _RotateBodyState();
}

class _RotateBodyState extends State<_RotateBody> {
  double? _drag;

  double _norm(double d) {
    var x = d % 360;
    if (x > 180) x -= 360;
    if (x <= -180) x += 360;
    return x;
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
      {bool active = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: active ? AppColors.primary : AppColors.border),
            ),
            child: Column(children: [
              Icon(icon,
                  color: active ? AppColors.primary : AppColors.textPrimary),
              const SizedBox(height: 6),
              Text(label,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deg = _norm(_drag ?? widget.degrees);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _action(Icons.rotate_left_rounded, 'Left 90°',
              () => widget.onChanged(_norm(widget.degrees - 90), false)),
          _action(Icons.rotate_right_rounded, 'Right 90°',
              () => widget.onChanged(_norm(widget.degrees + 90), false)),
          if (widget.onMirror != null)
            _action(Icons.flip_rounded, 'Flip', widget.onMirror!,
                active: widget.mirrored == true),
          _action(Icons.restart_alt_rounded, 'Reset',
              () => widget.onChanged(0, false)),
        ]),
        const SizedBox(height: 16),
        Text('Angle  ${deg.round()}°',
            style: TextStyle(color: AppColors.textSecondary)),
        Slider(
          value: deg.clamp(-180.0, 180.0),
          min: -180,
          max: 180,
          divisions: 360,
          onChanged: (v) {
            setState(() => _drag = v);
            widget.onChanged(v, true);
          },
          onChangeEnd: (_) {
            setState(() => _drag = null);
            widget.onChangeEnd();
          },
        ),
      ],
    );
  }
}

class _LayerBody extends StatelessWidget {
  final int index;
  final int count;
  final String note;
  final ValueChanged<LayerMove> onMove;

  const _LayerBody({
    required this.index,
    required this.count,
    required this.note,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final top = index >= count - 1;
    final bottom = index <= 0;
    Widget btn(IconData icon, String label, LayerMove m, bool enabled) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: OutlinedButton(
              onPressed: enabled ? () => onMove(m) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Column(children: [
                Icon(icon),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 11)),
              ]),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Layer ${index + 1} of $count',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(note,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          btn(Icons.vertical_align_top_rounded, 'To front', LayerMove.front,
              !top),
          btn(Icons.arrow_upward_rounded, 'Forward', LayerMove.forward, !top),
          btn(Icons.arrow_downward_rounded, 'Backward', LayerMove.backward,
              !bottom),
          btn(Icons.vertical_align_bottom_rounded, 'To back', LayerMove.back,
              !bottom),
        ]),
      ],
    );
  }
}

class _CropBody extends StatefulWidget {
  final Rect? crop;
  final double mediaAspect;
  final ValueChanged<Rect?> onChanged;

  const _CropBody(
      {required this.crop, required this.mediaAspect, required this.onChanged});

  @override
  State<_CropBody> createState() => _CropBodyState();
}

class _CropBodyState extends State<_CropBody> {
  // Insets as fractions of the media: left, top, right, bottom.
  late List<double> _insets = _fromRect(widget.crop);

  static List<double> _fromRect(Rect? r) => r == null
      ? [0, 0, 0, 0]
      : [r.left, r.top, 1 - r.right, 1 - r.bottom];

  @override
  void didUpdateWidget(_CropBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.crop != widget.crop) _insets = _fromRect(widget.crop);
  }

  Rect? _rect(List<double> i) {
    if (i.every((v) => v < 0.001)) return null;
    return Rect.fromLTRB(i[0], i[1], 1 - i[2], 1 - i[3]);
  }

  /// Centred crop to [aspect] (width / height of the result).
  void _preset(double aspect) {
    final media = widget.mediaAspect > 0 ? widget.mediaAspect : 1.0;
    double w = 1, h = 1;
    if (aspect > media) {
      h = media / aspect;
    } else {
      w = aspect / media;
    }
    final l = (1 - w) / 2;
    final t = (1 - h) / 2;
    widget.onChanged(_rect([l, t, l, t]));
  }

  Widget _slider(String label, int i) {
    return Row(
      children: [
        SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(color: AppColors.textSecondary))),
        Expanded(
          child: Slider(
            value: _insets[i].clamp(0.0, 0.45),
            min: 0,
            max: 0.45,
            onChanged: (v) => setState(() => _insets[i] = v),
            onChangeEnd: (_) => widget.onChanged(_rect(_insets)),
          ),
        ),
        SizedBox(
            width: 44,
            child: Text('${(_insets[i] * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(color: AppColors.textPrimary))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
                label: const Text('Original'),
                onPressed: () => widget.onChanged(null)),
            for (final (label, a) in const [
              ('1:1', 1.0),
              ('4:5', 0.8),
              ('9:16', 9 / 16),
              ('16:9', 16 / 9),
              ('4:3', 4 / 3),
            ])
              ActionChip(label: Text(label), onPressed: () => _preset(a)),
          ],
        ),
        const SizedBox(height: 10),
        _slider('Left', 0),
        _slider('Right', 2),
        _slider('Top', 1),
        _slider('Bottom', 3),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Column(children: [
          Icon(icon,
              color: selected ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 11)),
        ]),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color ?? AppColors.surfaceLight,
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 3 : 1),
        ),
        child: color == null
            ? Icon(Icons.block_rounded,
                size: 18, color: AppColors.textTertiary)
            : null,
      ),
    );
  }
}
