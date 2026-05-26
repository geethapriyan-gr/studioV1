import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/video_project.dart';

class TransformableTextOverlayWidget extends StatefulWidget {
  final TextOverlay overlay;
  final Size constraintsSize;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(String id, Offset position, double scale, double rotation)
      onTransformEnd;

  const TransformableTextOverlayWidget({
    super.key,
    required this.overlay,
    required this.constraintsSize,
    required this.isSelected,
    required this.onTap,
    required this.onTransformEnd,
  });

  @override
  State<TransformableTextOverlayWidget> createState() =>
      _TransformableTextOverlayWidgetState();
}

class _TransformableTextOverlayWidgetState
    extends State<TransformableTextOverlayWidget> {
  late Offset _position;
  bool _isDragging = false;
  // Pinch-to-zoom scale factor (relative to the slider-set fontSize)
  double _pinchScale = 1.0;
  double _baseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _position = Offset(
      widget.overlay.position.dx * widget.constraintsSize.width,
      widget.overlay.position.dy * widget.constraintsSize.height,
    );
  }

  @override
  void didUpdateWidget(TransformableTextOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _position = Offset(
        widget.overlay.position.dx * widget.constraintsSize.width,
        widget.overlay.position.dy * widget.constraintsSize.height,
      );
    }
  }

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
    widget.onTap();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _position += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    _commitTransform();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _isDragging = true;
    _baseScale = _pinchScale;
    widget.onTap();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      // Handle pinch-to-zoom
      if (details.pointerCount >= 2) {
        _pinchScale = (_baseScale * details.scale).clamp(0.3, 5.0);
      }
      // Handle drag (single finger or focal point movement)
      _position += details.focalPointDelta;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isDragging = false;
    _commitTransform();
  }

  void _commitTransform() {
    widget.onTransformEnd(
      widget.overlay.id,
      Offset(
        _position.dx / widget.constraintsSize.width,
        _position.dy / widget.constraintsSize.height,
      ),
      _pinchScale,
      widget.overlay.rotation,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Effective font size = slider fontSize * pinch scale
    final effectiveFontSize = widget.overlay.fontSize * _pinchScale;

    return Positioned(
      left: 0,
      top: 0,
      child: Transform.translate(
        offset: _position,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Use scale gesture detector for both drag and pinch-to-zoom
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Container(
            decoration: widget.isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Colors.white70,
                      width: 2.0,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            padding: const EdgeInsets.all(8),
            child: Text(
              widget.overlay.text,
              textAlign: widget.overlay.flutterTextAlign,
              style: GoogleFonts.getFont(
                widget.overlay.fontFamily,
                fontSize: effectiveFontSize,
                color: widget.overlay.color,
                fontWeight: widget.overlay.fontWeight,
                fontStyle: widget.overlay.flutterFontStyle,
                shadows: const [
                  Shadow(
                    offset: Offset(1, 1),
                    color: Colors.black54,
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
