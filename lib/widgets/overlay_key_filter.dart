import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/chroma_key_settings.dart';
import '../utils/chroma_key.dart';

/// Removes a key colour (green screen) from its child, live, using the same
/// formula as the exporter's FFmpeg `colorkey` filter.
///
/// Needs Impeller (the default renderer on Android and iOS). Where shader
/// filters are not available the child is shown unkeyed with a small badge,
/// and the export is still keyed.
class OverlayKeyFilter extends StatefulWidget {
  final ChromaKeySettings settings;
  final Widget child;

  const OverlayKeyFilter(
      {super.key, required this.settings, required this.child});

  static Future<ui.FragmentProgram>? _program;

  static Future<ui.FragmentProgram> _load() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/overlay_key.frag');

  @override
  State<OverlayKeyFilter> createState() => _OverlayKeyFilterState();
}

class _OverlayKeyFilterState extends State<OverlayKeyFilter> {
  ui.FragmentShader? _shader;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!ui.ImageFilter.isShaderFilterSupported) {
      _failed = true;
      return;
    }
    OverlayKeyFilter._load().then((program) {
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    }).catchError((Object e) {
      debugPrint('Overlay key shader unavailable: $e');
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) {
      if (!_failed) return widget.child;
      return Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          const Positioned(
            left: 8,
            top: 8,
            child: Tooltip(
              message: 'Green screen shows in the export',
              child: Icon(Icons.filter_vintage, color: Colors.white70, size: 40),
            ),
          ),
        ],
      );
    }
    final s = widget.settings;
    // Float uniforms 0-1 (size) are set by the engine.
    shader
      ..setFloat(2, s.keyColor.r)
      ..setFloat(3, s.keyColor.g)
      ..setFloat(4, s.keyColor.b)
      ..setFloat(5, s.similarity.clamp(0.0, 1.0))
      ..setFloat(6, s.blend.clamp(0.0, 1.0))
      ..setFloat(7, ChromaKey.despillMode(s).toDouble());
    return ImageFiltered(
      imageFilter: ui.ImageFilter.shader(shader),
      child: widget.child,
    );
  }
}
