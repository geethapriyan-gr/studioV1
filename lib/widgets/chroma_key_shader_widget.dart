import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chroma_key_settings.dart';
import '../services/chroma_key_service.dart';

class ChromaKeyShaderWidget extends StatefulWidget {
  final String? foregroundPath;
  final String? backgroundPath;
  final ChromaKeySettings settings;
  final Function(ui.Image)? onRendered;

  const ChromaKeyShaderWidget({
    super.key,
    this.foregroundPath,
    this.backgroundPath,
    required this.settings,
    this.onRendered,
  });

  @override
  State<ChromaKeyShaderWidget> createState() => _ChromaKeyShaderWidgetState();
}

class _ChromaKeyShaderWidgetState extends State<ChromaKeyShaderWidget> {
  ui.Image? _foregroundImage;
  ui.Image? _backgroundImage;
  ui.Image? _renderedImage;
  bool _isLoading = false;
  String? _error;
  final ChromaKeyService _chromaKeyService = ChromaKeyService();

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  @override
  void didUpdateWidget(covariant ChromaKeyShaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.foregroundPath != widget.foregroundPath ||
        oldWidget.backgroundPath != widget.backgroundPath ||
        oldWidget.settings != widget.settings) {
      _loadImages();
    }
  }

  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (widget.foregroundPath != null) {
        _foregroundImage = await _loadImage(widget.foregroundPath!);
      }
      if (widget.backgroundPath != null) {
        _backgroundImage = await _loadImage(widget.backgroundPath!);
      }

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

  Future<ui.Image> _loadImage(String path) async {
    try {
      final bytes = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      final networkImage = NetworkImage(path);
      final completer = Completer<ui.Image>();
      networkImage.resolve(const ImageConfiguration()).addListener(
            ImageStreamListener(
              (ImageInfo info, bool _) => completer.complete(info.image),
              onError: (dynamic error, StackTrace? stackTrace) {
                completer.completeError(error);
              },
            ),
          );
      return completer.future;
    }
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
        widget.onRendered?.call(image);
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
          ..setFloat(3, widget.settings.similarity)
          ..setFloat(4, widget.settings.shadowRemoval)
          ..setFloat(5, widget.settings.spillReduction)
          ..setFloat(6, widget.settings.edgeTransition)
          ..setFloat(7, widget.settings.skinProtection)
          ..setFloat(8, size.width)
          ..setFloat(9, size.height);

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
