import 'package:flutter/material.dart';
import '../main.dart' show AppColors;

class ModernSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String? label;
  final bool showValue;
  final String? unit;

  const ModernSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions = 100,
    required this.onChanged,
    this.onChangeEnd,
    this.label,
    this.showValue = true,
    this.unit,
  });

  @override
  State<ModernSlider> createState() => _ModernSliderState();
}

class _ModernSliderState extends State<ModernSlider> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.label!,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.showValue)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _formatValue(widget.value),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() => _isDragging = true);
                  _updateValue(details.localPosition.dx, constraints.maxWidth);
                },
                onHorizontalDragUpdate: (details) {
                  _updateValue(details.localPosition.dx, constraints.maxWidth);
                },
                onHorizontalDragEnd: (details) {
                  setState(() => _isDragging = false);
                  widget.onChangeEnd?.call(widget.value);
                },
                onTapDown: (details) {
                  _updateValue(details.localPosition.dx, constraints.maxWidth);
                  widget.onChangeEnd?.call(widget.value);
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 40),
                  painter: _SliderPainter(
                    value: widget.value,
                    min: widget.min,
                    max: widget.max,
                    isDragging: _isDragging,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatValue(double value) {
    if (widget.unit != null) {
      return '${value.toStringAsFixed(1)}${widget.unit}';
    }
    if (value.abs() >= 1 || value == 0) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  void _updateValue(double localX, double width) {
    final normalized = (localX / width).clamp(0.0, 1.0);
    final range = widget.max - widget.min;
    final newValue = widget.min + (normalized * range);
    
    double steppedValue;
    if (widget.divisions > 0) {
      final step = range / widget.divisions;
      steppedValue = (newValue / step).round() * step;
    } else {
      steppedValue = newValue;
    }
    
    widget.onChanged(steppedValue.clamp(widget.min, widget.max));
  }
}

class _SliderPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final bool isDragging;

  _SliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    
    final normalizedValue = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // Add small padding to thumbX so it doesn't get clipped at edges
    final padding = 4.0;
    final usableWidth = size.width - (padding * 2);
    final thumbX = padding + (normalizedValue * usableWidth);
    
    // Draw ruler ticks
    final tickSpacing = 10.0;
    final numTicks = (usableWidth / tickSpacing).floor();
    final totalTickWidth = numTicks * tickSpacing;
    final startX = padding + (usableWidth - totalTickWidth) / 2;

    final tickPaintCenter = Paint()
      ..color = AppColors.border.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final tickPaintMajor = Paint()
      ..color = AppColors.border.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= numTicks; i++) {
      double x = startX + i * tickSpacing;
      // Make every 5th tick a major tick
      bool isMajor = i % 5 == 0;
      double tickHeight = isMajor ? 14.0 : 8.0;

      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        isMajor ? tickPaintMajor : tickPaintCenter,
      );
    }
    
    // Draw sliding thumb (glowing line)
    final double thumbHeight = isDragging ? 32.0 : 26.0;

    final thumbShadowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final thumbPaint = Paint()
      ..color = Color.lerp(AppColors.primary, Colors.white, 0.2)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Draw shadow/glow
    canvas.drawLine(
      Offset(thumbX, centerY - thumbHeight / 2),
      Offset(thumbX, centerY + thumbHeight / 2),
      thumbShadowPaint,
    );

    // Draw thumb line
    canvas.drawLine(
      Offset(thumbX, centerY - thumbHeight / 2),
      Offset(thumbX, centerY + thumbHeight / 2),
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.min != min ||
        oldDelegate.max != max;
  }
}
