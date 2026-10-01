import '../models/video_project.dart';

/// Fade-in / fade-out envelope for audio overlays, shared by the preview
/// mixer and the exporter (FFmpeg `afade`, linear) so both sound the same.
class AudioFades {
  AudioFades._();

  static const Duration maxLength = Duration(milliseconds: 1500);

  /// Fade length for an overlay of [clipLength]: 1.5 s, or a third of the
  /// overlay when it is shorter than 4.5 s.
  static Duration length(Duration clipLength) {
    final third = clipLength ~/ 3;
    return third < maxLength ? third : maxLength;
  }

  /// Gain (0..1) of [overlay] at timeline [position].
  static double gain(AudioOverlay overlay, Duration position) {
    if (!overlay.fadeIn && !overlay.fadeOut) return 1.0;
    final len = overlay.endTime - overlay.startTime;
    final fade = length(len).inMicroseconds;
    if (fade <= 0) return 1.0;
    final t = (position - overlay.startTime).inMicroseconds;
    var g = 1.0;
    if (overlay.fadeIn && t < fade) g = t / fade;
    final remaining = len.inMicroseconds - t;
    if (overlay.fadeOut && remaining < fade) {
      final out = remaining / fade;
      if (out < g) g = out;
    }
    return g.clamp(0.0, 1.0);
  }
}
