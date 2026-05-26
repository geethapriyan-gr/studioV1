library;

import 'package:flutter/material.dart';
import '../models/transition.dart';
import 'video_transition.dart';

// ──────────────────────────────────────────────
//  Supported curve presets
// ──────────────────────────────────────────────
enum TransitionCurvePreset {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  decelerate,
  bounceOut,
  elasticOut,
}

extension TransitionCurvePresetX on TransitionCurvePreset {
  Curve get curve {
    switch (this) {
      case TransitionCurvePreset.linear:
        return Curves.linear;
      case TransitionCurvePreset.easeIn:
        return Curves.easeIn;
      case TransitionCurvePreset.easeOut:
        return Curves.easeOut;
      case TransitionCurvePreset.easeInOut:
        return Curves.easeInOut;
      case TransitionCurvePreset.decelerate:
        return Curves.decelerate;
      case TransitionCurvePreset.bounceOut:
        return Curves.bounceOut;
      case TransitionCurvePreset.elasticOut:
        return Curves.elasticOut;
    }
  }

  String get displayName {
    switch (this) {
      case TransitionCurvePreset.linear:
        return 'Linear';
      case TransitionCurvePreset.easeIn:
        return 'Ease In';
      case TransitionCurvePreset.easeOut:
        return 'Ease Out';
      case TransitionCurvePreset.easeInOut:
        return 'Ease In-Out';
      case TransitionCurvePreset.decelerate:
        return 'Decelerate';
      case TransitionCurvePreset.bounceOut:
        return 'Bounce';
      case TransitionCurvePreset.elasticOut:
        return 'Elastic';
    }
  }
}

// ──────────────────────────────────────────────
//  TransitionFactory
// ──────────────────────────────────────────────
class TransitionFactory {
  TransitionFactory._();

  static final Map<TransitionType, VideoTransition> _cache = {};

  static VideoTransition getTransition(TransitionType type) {
    return _cache.putIfAbsent(type, () => _create(type));
  }

  static VideoTransition getTransitionByName(String name) {
    final type = Transition.fromName(name);
    return getTransition(type);
  }

  /// The linear progress `linearT` [0 -> 1] is passed directly to the transition.
  /// Standard easing `Curves.easeInOut.transform(t)` is handled INTERNALLY by the
  /// transitions themselves based on production rules.
  static Widget buildWithCurve({
    required TransitionType type,
    required double linearT,
    required Widget childA,
    required Widget childB,
    Curve curve = Curves
        .easeInOut, // Kept for API signature, but easing is forced internally now.
  }) {
    return getTransition(type).build(linearT.clamp(0.0, 1.0), childA, childB);
  }

  static List<VideoTransition> get allTransitions {
    return TransitionType.values.map((t) => getTransition(t)).toList();
  }

  // ------- exact mappings mapping exactly to the 17 new implementations -------
  static VideoTransition _create(TransitionType type) {
    switch (type) {
      case TransitionType.zoom:
        return ZoomTransition();
      case TransitionType.black:
        return BlackTransition();
      case TransitionType.white:
        return WhiteTransition();
      case TransitionType.shake:
        return ShakeTransition();
      case TransitionType.light:
        return LightTransition();
      case TransitionType.pixelate:
        return PixelateTransition();
      case TransitionType.circle:
        return CircleTransition();
      case TransitionType.push:
        return PushTransition();
      case TransitionType.pushRight:
        return PushRightTransition();
      case TransitionType.rotate1:
        return Rotate1Transition();
      case TransitionType.rotate2:
        return Rotate2Transition();
      case TransitionType.blink:
        return BlinkTransition();
      case TransitionType.vertical:
        return VerticalTransition();
      case TransitionType.horizontal:
        return HorizontalTransition();

      // Fallbacks mapping unused/overlapping legacy enum types:
      case TransitionType.crossfade:
        return DissolveTransition();
      case TransitionType.slideLeft:
        return SlideTransitionEffect();
      case TransitionType.slideRight:
        return SlideTransitionEffect();
      case TransitionType.slideUp:
        return VerticalTransition();
      case TransitionType.slideDown:
        return VerticalTransition();
    }
  }
}
