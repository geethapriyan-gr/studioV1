import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart' show AppColors;
import '../models/chroma_key_settings.dart';
import '../providers/video_editor_provider.dart';
import '../services/video_thumbnail_service.dart';
import '../utils/chroma_key.dart';

/// Green screen panel for the selected clip.
///
/// Live and non-destructive: the preview shows the key as you change it and
/// the export renders exactly that. Three steps — the colour to remove (auto,
/// tap it in the preview, or a preset), how strongly to remove it, and what
/// shows behind. The subject is moved and sized by dragging and pinching it
/// in the preview.
class ChromaKeyEditor extends StatefulWidget {
  const ChromaKeyEditor({super.key});

  @override
  State<ChromaKeyEditor> createState() => _ChromaKeyEditorState();
}

class _ChromaKeyEditorState extends State<ChromaKeyEditor> {
  bool _detecting = false;
  List<String> _library = const [];

  static const _presets = [
    ('Green', Color(0xFF00FF00)),
    ('Studio green', Color(0xFF00B140)),
    ('Blue', Color(0xFF0047BB)),
  ];

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final images = manifest
          .listAssets()
          .where((a) => a.startsWith('assets/image-library/'))
          .toList()
        ..sort();
      if (mounted) setState(() => _library = images);
    } catch (_) {}
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _autoDetect(VideoEditorProvider provider) async {
    setState(() => _detecting = true);
    final color = await provider.autoDetectChromaColor();
    if (!mounted) return;
    setState(() => _detecting = false);
    if (color == null) {
      _snack('No green or blue screen found at the edges — '
          'tap "Pick" and tap the background instead.');
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _pickBackground(
      VideoEditorProvider provider, bool isVideo) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: isVideo ? FileType.video : FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      await provider.setChromaKeyBackground(File(path));
    } catch (e) {
      if (mounted) _snack('Could not use that file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, _) {
        final hasClip = provider.selectedVideoClipId != null;
        final s = provider.currentChromaKeySettings ??
            ChromaKey.defaults.copyWith(enabled: false);
        final on = s.enabled;
        return Container(
          color: AppColors.surface,
          child: Column(
            children: [
              _header(provider, on, hasClip),
              Expanded(
                child: !hasClip
                    ? Center(
                        child: Text('Select a clip to use green screen.',
                            style: TextStyle(color: AppColors.textTertiary)),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                        children: [
                          _stepTitle('1', 'Colour to remove'),
                          _colourRow(provider, s),
                          if (provider.chromaPickMode) _pickHint(),
                          const SizedBox(height: 16),
                          _stepTitle('2', 'Adjust'),
                          _slider(
                            label: 'Strength',
                            hint: 'Higher removes more of the colour',
                            value: s.similarity,
                            min: 0.02,
                            max: 0.7,
                            enabled: on,
                            onChanged: (v) => provider.updateChromaKeySettings(
                                similarity: v, undoKey: 'chroma-strength'),
                          ),
                          _slider(
                            label: 'Edge softness',
                            hint: 'Smooths the outline (hair, motion blur)',
                            value: s.blend,
                            min: 0.0,
                            max: 0.4,
                            enabled: on,
                            onChanged: (v) => provider.updateChromaKeySettings(
                                blend: v, undoKey: 'chroma-softness'),
                          ),
                          if (ChromaKey.canDespill(s.keyColor))
                            SwitchListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('Clean up coloured edges',
                                  style:
                                      TextStyle(color: AppColors.textPrimary)),
                              subtitle: Text(
                                  'Removes the screen\'s tint from hair and edges',
                                  style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 11)),
                              value: s.spillReduction > 0.5,
                              onChanged: on
                                  ? (v) => provider.updateChromaKeySettings(
                                      spillReduction: v ? 1.0 : 0.0)
                                  : null,
                            ),
                          const SizedBox(height: 12),
                          _stepTitle('3', 'Background'),
                          _backgroundRow(provider, s),
                          const SizedBox(height: 16),
                          _subjectCard(provider, s, on),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────

  Widget _header(VideoEditorProvider provider, bool on, bool hasClip) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_vintage_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Green screen',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                Text(on ? 'On — live in the preview' : 'Off',
                    style: TextStyle(
                        color: on ? AppColors.success : AppColors.textTertiary,
                        fontSize: 11)),
              ],
            ),
          ),
          if (hasClip && on)
            GestureDetector(
              onTapDown: (_) => provider.setChromaCompare(true),
              onTapUp: (_) => provider.setChromaCompare(false),
              onTapCancel: () => provider.setChromaCompare(false),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: provider.chromaCompare
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.compare_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('Hold: original',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ]),
              ),
            ),
          if (hasClip)
            Switch(
              value: on,
              onChanged: (v) => provider.updateChromaKeySettings(enabled: v),
            ),
          IconButton(
            tooltip: 'Reset',
            onPressed: hasClip ? provider.resetChromaKey : null,
            icon: Icon(Icons.restart_alt_rounded,
                color: AppColors.textTertiary, size: 20),
          ),
          IconButton(
            tooltip: 'Done',
            onPressed: provider.toggleChromaKeyEditor,
            icon: Icon(Icons.check_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _stepTitle(String n, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(n,
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ],
      ),
    );
  }

  // ── Step 1: colour ─────────────────────────────────────────────────────

  Widget _colourRow(VideoEditorProvider provider, ChromaKeySettings s) {
    final picking = provider.chromaPickMode;
    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _bigChoice(
            icon: Icons.auto_awesome_rounded,
            label: 'Auto',
            busy: _detecting,
            onTap: _detecting ? null : () => _autoDetect(provider),
          ),
          _bigChoice(
            icon: Icons.colorize_rounded,
            label: picking ? 'Tap preview' : 'Pick',
            selected: picking,
            onTap: () => provider.setChromaPickMode(!picking),
          ),
          for (final (label, color) in _presets)
            _bigChoice(
              swatch: color,
              label: label,
              selected:
                  s.enabled && s.keyColor.toARGB32() == color.toARGB32(),
              onTap: () => provider.updateChromaKeySettings(
                  enabled: true, keyColor: color, spillReduction: 1.0),
            ),
          if (s.enabled &&
              !_presets.any(
                  (p) => p.$2.toARGB32() == s.keyColor.toARGB32()))
            _bigChoice(
              swatch: s.keyColor,
              label: 'Picked',
              selected: true,
              onTap: () {},
            ),
        ],
      ),
    );
  }

  Widget _pickHint() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.touch_app_rounded, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Tap the green (or blue) background in the preview.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _bigChoice({
    IconData? icon,
    Color? swatch,
    required String label,
    bool selected = false,
    bool busy = false,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 74,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.18)
                : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (swatch != null)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54),
                  ),
                )
              else
                Icon(icon,
                    color: selected ? AppColors.primary : AppColors.textPrimary),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color:
                          selected ? AppColors.primary : AppColors.textSecondary,
                      fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 2: sliders ────────────────────────────────────────────────────

  Widget _slider({
    required String label,
    required String hint,
    required double value,
    required double min,
    required double max,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    final v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: TextStyle(
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary)),
          const Spacer(),
          Text('${((v - min) / (max - min) * 100).round()}',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
        ]),
        Slider(
          value: v,
          min: min,
          max: max,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? (_) => provider.sealUndo() : null,
        ),
        Text(hint,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        const SizedBox(height: 6),
      ],
    );
  }

  // ── Step 3: background ─────────────────────────────────────────────────

  Widget _backgroundRow(VideoEditorProvider provider, ChromaKeySettings s) {
    final active = s.backgroundPath;
    final own = provider.chromaKeyBackgrounds;
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _bgTile(
            selected: active == null,
            onTap: provider.clearChromaBackground,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block_rounded, color: AppColors.textSecondary),
                Text('None',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          _bgTile(
            onTap: () => _pickBackground(provider, false),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_photo_alternate_outlined,
                    color: AppColors.primary),
                Text('Photo',
                    style: TextStyle(color: AppColors.primary, fontSize: 11)),
              ],
            ),
          ),
          _bgTile(
            onTap: () => _pickBackground(provider, true),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library_outlined, color: AppColors.primary),
                Text('Video',
                    style: TextStyle(color: AppColors.primary, fontSize: 11)),
              ],
            ),
          ),
          for (final path in own.reversed)
            _bgTile(
              selected: path == active,
              onTap: () => provider.updateChromaKeySettings(
                  backgroundPath: path,
                  isBackgroundVideo:
                      provider.isChromaKeyBackgroundVideo(path)),
              onLongPress: () => provider.removeChromaKeyBackground(path),
              child: provider.isChromaKeyBackgroundVideo(path)
                  ? _VideoThumb(path: path)
                  : Image(
                      image: ResizeImage(FileImage(File(path)), width: 160),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          for (final asset in _library)
            _bgTile(
              selected: active != null &&
                  active.endsWith('bg_${asset.split('/').last}'),
              onTap: () => provider.setChromaBackgroundAsset(asset),
              child: Image(
                image: ResizeImage(AssetImage(asset), width: 160),
                fit: BoxFit.cover,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bgTile({
    required Widget child,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onLongPress: onLongPress,
        child: Container(
          width: 70,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2.5 : 1),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── Subject ────────────────────────────────────────────────────────────

  Widget _subjectCard(
      VideoEditorProvider provider, ChromaKeySettings s, bool on) {
    final moved = (s.position - const Offset(0.5, 0.5)).distance > 0.001 ||
        (s.scale - 1).abs() > 0.001;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.open_with_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              on
                  ? 'Drag the person in the preview to move them; pinch to '
                      'resize. (${(s.scale * 100).round()}%)'
                  : 'Turn the green screen on to place the person over the '
                      'background.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          if (moved)
            TextButton(
              onPressed: provider.resetChromaSubject,
              child: const Text('Centre'),
            ),
        ],
      ),
    );
  }
}

/// First frame of a background video.
class _VideoThumb extends StatelessWidget {
  final String path;
  const _VideoThumb({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: VideoThumbnailService().extractFirstFrame(path),
      builder: (context, snap) {
        final bytes = snap.data;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              Container(color: AppColors.surface),
            const Center(
              child: Icon(Icons.play_circle_outline_rounded,
                  color: Colors.white70),
            ),
          ],
        );
      },
    );
  }
}
