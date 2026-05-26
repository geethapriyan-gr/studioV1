import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chroma_key_settings.dart';
import '../services/chroma_key_service.dart';

class ChromaKeyShaderWidgetForWidget extends StatefulWidget {
  final Widget foreground;
  final Widget background;
  final ChromaKeySettings settings;

  const ChromaKeyShaderWidgetForWidget({
    super.key,
    required this.foreground,
    required this.background,
    required this.settings,
  });

  @override
  State<ChromaKeyShaderWidgetForWidget> createState() =>
      _ChromaKeyShaderWidgetForWidgetState();
}

class _ChromaKeyShaderWidgetForWidgetState
    extends State<ChromaKeyShaderWidgetForWidget> {
  ui.Image? _foregroundImage;
  ui.Image? _backgroundImage;
  ui.Image? _renderedImage;
  bool _isLoading = false;
  String? _error;
  final ChromaKeyService _chromaKeyService = ChromaKeyService();

  @override
  void initState() {
    super.initState();
    _captureImages();
  }

  @override
  void didUpdateWidget(covariant ChromaKeyShaderWidgetForWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.settings != widget.settings) {
      _captureImages();
    }
  }

  Future<void> _captureImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Capture foreground widget as image
      _foregroundImage = await _captureWidget(widget.foreground);

      // Capture background widget as image
      _backgroundImage = await _captureWidget(widget.background);

      await _renderChromaKey();
    } catch (e) {
      setState(() {
        _error = 'Error loading or rendering images: $e';
        print(e);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<ui.Image> _captureWidget(Widget widget) async {
    // This is a simplified version - in a real app, you might need a more robust
    // way to capture widget to image. For now, let's just return a placeholder.
    // A more complete implementation would use RenderRepaintBoundary.
    final completer = Completer<ui.Image>();

    // For this example, let's create a simple placeholder image
    const int width = 300;
    const int height = 200;
    final image = await _createPlaceholderImage(width, height);

    completer.complete(image);
    return completer.future;
  }

  Future<ui.Image> _createPlaceholderImage(int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Create a simple gradient background
    const gradient = LinearGradient(
      colors: [Colors.blue, Colors.purple],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final paint = Paint()
      ..shader = gradient.createShader(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), paint);

    return recorder.endRecording().toImage(width, height);
  }

  Future<void> _renderChromaKey() async {
    if (_foregroundImage == null || _backgroundImage == null) {
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Calculate the dimensions for rendering
    final int width = _foregroundImage!.width;
    final int height = _foregroundImage!.height;

    try {
      // Apply chroma key effect
      await _applyChromaKey(canvas, Size(width.toDouble(), height.toDouble()));

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      setState(() {
        _renderedImage?.dispose();
        _renderedImage = image;
      });
    } catch (e) {
      setState(() {
        _error = 'Error rendering chroma key: $e';
        print(e);
      });
    }
  }

  Future<void> _applyChromaKey(Canvas canvas, Size size) async {
    // Try to use the Flutter shader
    if (_foregroundImage != null && _backgroundImage != null) {
      try {
        // Load the shader
        final program = await ui.FragmentProgram.fromAsset(
            'assets/shaders/chroma_key.frag');

        // Create shader with parameters
        final shader = program.fragmentShader()
          ..setImageSampler(0, _foregroundImage!)
          ..setFloat(0, widget.settings.hueMin)
          ..setFloat(1, widget.settings.hueMax)
          ..setFloat(2, widget.settings.saturationMin)
          ..setFloat(3, widget.settings.valueMin)
          ..setFloat(4, widget.settings.spillReduction)
          ..setFloat(5, widget.settings.edgeFeather)
          ..setFloat(6, size.width)
          ..setFloat(7, size.height);

        // Draw the background image
        final bgPaint = Paint()
          ..shader = ImageShader(
            _backgroundImage!,
            TileMode.clamp,
            TileMode.clamp,
            Matrix4.identity().storage,
          );
        canvas.drawRect(Offset.zero & size, bgPaint);

        // Draw the foreground with chroma key effect
        final fgPaint = Paint()..shader = shader;
        canvas.drawRect(Offset.zero & size, fgPaint);
      } catch (shaderError) {
        print('Shader fallback: $shaderError');
        await _renderChromaKeyCPU(canvas, size);
      }
    }
  }

  Future<void> _renderChromaKeyCPU(Canvas canvas, Size size) async {
    final image = await _chromaKeyService.applyChromaKeyCPU(
      _foregroundImage!,
      _backgroundImage!,
      widget.settings,
    );

    if (image != null) {
      final paint = Paint();
      canvas.drawImage(image, Offset.zero, paint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null
              ? Center(
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red)))
              : _renderedImage != null
                  ? CustomPaint(
                      painter: _RenderedImagePainter(_renderedImage!),
                      child: Container(),
                    )
                  : const Center(child: Text('No images to render')),
    );
  }

  @override
  void dispose() {
    _foregroundImage?.dispose();
    _backgroundImage?.dispose();
    _renderedImage?.dispose();
    super.dispose();
  }
}

class _RenderedImagePainter extends CustomPainter {
  final ui.Image image;

  _RenderedImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
