import 'package:flutter/material.dart';
import '../main.dart' show AppColors;

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double scale;
  final bool isSelected;
  final double height;

  WaveformPainter({
    required this.waveformData,
    required this.scale,
    this.isSelected = false,
    this.height = 36,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty || size.width == 0) return;

    final paint = Paint()
      ..color = isSelected ? AppColors.textPrimary : AppColors.audioTrack
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final totalWidth = size.width;
    final centerY = height / 2;
    final maxAmplitude = 0.4 * height;

    // Optimize: Reduce number of samples to draw based on available width
    final maxSamplesToDraw = (totalWidth / 2).ceil(); // 2 pixels per sample
    final step = (waveformData.length / maxSamplesToDraw).ceil();

    if (step <= 1) {
      // Draw all samples if we have few enough
      final pixelsPerSample = totalWidth / waveformData.length;
      for (int i = 0; i < waveformData.length; i++) {
        final x = i * pixelsPerSample;
        final amplitude = waveformData[i];
        final y1 = centerY - (amplitude * maxAmplitude);
        final y2 = centerY + (amplitude * maxAmplitude);
        canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);
      }
    } else {
      // Draw averaged samples for performance
      final pixelsPerStep = totalWidth / (waveformData.length / step);
      int i = 0;

      while (i < waveformData.length - step) {
        // Average amplitude for this step
        double sum = 0;
        for (int j = 0; j < step; j++) {
          sum += waveformData[i + j];
        }
        final avgAmplitude = sum / step;

        final x = (i / step) * pixelsPerStep;
        final y1 = centerY - (avgAmplitude * maxAmplitude);
        final y2 = centerY + (avgAmplitude * maxAmplitude);

        canvas.drawLine(Offset(x, y1), Offset(x, y2), paint);

        i += step;
      }
    }

    // Draw center line
    final centerPaint = Paint()
      ..color = isSelected
          ? AppColors.textPrimary.withOpacity(0.3)
          : AppColors.audioTrack.withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
        Offset(0, centerY), Offset(totalWidth, centerY), centerPaint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    // Only repaint if waveform data or selection state changes
    if (oldDelegate.isSelected != isSelected) return true;
    if (oldDelegate.waveformData.length != waveformData.length) return true;

    // Compare waveform data (optimized for performance)
    const tolerance = 0.01;
    for (int i = 0; i < waveformData.length; i++) {
      if ((oldDelegate.waveformData[i] - waveformData[i]).abs() > tolerance) {
        return true;
      }
    }

    return false;
  }
}

class WaveformWidget extends StatelessWidget {
  final List<double> waveformData;
  final double scale;
  final bool isSelected;
  final double height;

  const WaveformWidget({
    super.key,
    required this.waveformData,
    required this.scale,
    this.isSelected = false,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: WaveformPainter(
        waveformData: waveformData,
        scale: scale,
        isSelected: isSelected,
        height: height,
      ),
      size: Size(double.infinity, height),
    );
  }
}
