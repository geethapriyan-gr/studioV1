import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/chroma_key_settings.dart';

/// Green-screen helpers shared by the editor preview and the exporter.
///
/// The key itself is FFmpeg's `colorkey` formula (see
/// `shaders/overlay_key.frag`): a pixel becomes transparent the closer its
/// colour is to [ChromaKeySettings.keyColor] ([ChromaKeySettings.similarity]
/// = how close, [ChromaKeySettings.blend] = how soft the edge). "Clean
/// edges" ([ChromaKeySettings.spillReduction] > 0.5) then removes the green
/// or blue tint the screen leaves on the subject, with FFmpeg's `despill`
/// formula.
class ChromaKey {
  ChromaKey._();

  /// Settings for a newly enabled green screen.
  static const ChromaKeySettings defaults = ChromaKeySettings(
    enabled: true,
    keyColor: Color(0xFF00FF00),
    similarity: 0.30,
    blend: 0.10,
    spillReduction: 1.0,
  );

  /// 0 = no edge clean-up, 1 = green screen, 2 = blue screen.
  static int despillMode(ChromaKeySettings s) {
    if (s.spillReduction < 0.5) return 0;
    final c = s.keyColor;
    if (c.g > c.r && c.g > c.b && c.g - math.max(c.r, c.b) > 0.15) return 1;
    if (c.b > c.r && c.b > c.g && c.b - math.max(c.r, c.g) > 0.15) return 2;
    return 0;
  }

  /// Whether "Clean edges" applies to [color] (green or blue screens).
  static bool canDespill(Color color) => despillMode(
          ChromaKeySettings(keyColor: color, spillReduction: 1.0)) !=
      0;

  /// FFmpeg filter matching the preview shader's edge clean-up, or null.
  static String? despillFilter(ChromaKeySettings s) => switch (despillMode(s)) {
        1 => 'despill=type=green:mix=0.5:expand=0:red=0:green=-1:blue=0'
            ':brightness=0',
        2 => 'despill=type=blue:mix=0.5:expand=0:red=0:green=0:blue=-1'
            ':brightness=0',
        _ => null,
      };

  /// Average colour around [uv] (0..1 in the image) of straight-alpha RGBA
  /// pixels.
  static Color sample(Uint8List rgba, int width, int height, Offset uv,
      {int radius = 3}) {
    final cx = (uv.dx.clamp(0.0, 1.0) * (width - 1)).round();
    final cy = (uv.dy.clamp(0.0, 1.0) * (height - 1)).round();
    var r = 0, g = 0, b = 0, n = 0;
    for (int y = math.max(0, cy - radius);
        y <= math.min(height - 1, cy + radius);
        y++) {
      for (int x = math.max(0, cx - radius);
          x <= math.min(width - 1, cx + radius);
          x++) {
        final i = (y * width + x) * 4;
        r += rgba[i];
        g += rgba[i + 1];
        b += rgba[i + 2];
        n++;
      }
    }
    if (n == 0) return const Color(0xFF00FF00);
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  /// Finds the screen colour from the frame's edges (where the green or
  /// blue backdrop usually is). Returns null when the edges are not a
  /// clear green or blue.
  static Color? detect(Uint8List rgba, int width, int height) {
    if (width < 4 || height < 4) return null;
    final band = math.max(1, (math.min(width, height) * 0.08).round());
    var gr = 0, gg = 0, gb = 0, gn = 0;
    var br = 0, bg = 0, bb = 0, bn = 0;
    var total = 0;
    final step = math.max(1, math.min(width, height) ~/ 120);
    for (int y = 0; y < height; y += step) {
      final edgeRow = y < band || y >= height - band;
      for (int x = 0; x < width; x += edgeRow ? step : 1) {
        if (!edgeRow && x >= band && x < width - band) {
          x = width - band - 1;
          continue;
        }
        final i = (y * width + x) * 4;
        final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
        total++;
        if (g > r * 1.15 && g > b * 1.15 && g > 40) {
          gr += r;
          gg += g;
          gb += b;
          gn++;
        } else if (b > r * 1.15 && b > g * 1.15 && b > 40) {
          br += r;
          bg += g;
          bb += b;
          bn++;
        }
      }
    }
    if (total == 0) return null;
    if (gn >= bn && gn > total * 0.25) {
      return Color.fromARGB(255, gr ~/ gn, gg ~/ gn, gb ~/ gn);
    }
    if (bn > gn && bn > total * 0.25) {
      return Color.fromARGB(255, br ~/ bn, bg ~/ bn, bb ~/ bn);
    }
    return null;
  }
}
