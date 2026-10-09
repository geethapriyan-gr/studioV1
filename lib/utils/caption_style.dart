import 'package:flutter/material.dart';

import '../models/video_project.dart';

/// Looks for auto-captions. Captions are ordinary text items, so every text
/// tool still works on them afterwards.
@immutable
class CaptionStyle {
  final String id;
  final String label;
  final String fontFamily;

  /// Canvas pixels (1920-px-tall design space).
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final Color? boxColor;
  final Color? outlineColor;
  final double outlineWidth;
  final bool shadow;
  final String animIn;

  const CaptionStyle({
    required this.id,
    required this.label,
    this.fontFamily = 'Montserrat',
    this.fontSize = 64,
    this.color = Colors.white,
    this.fontWeight = FontWeight.bold,
    this.boxColor,
    this.outlineColor,
    this.outlineWidth = 0,
    this.shadow = true,
    this.animIn = 'none',
  });

  static const List<CaptionStyle> all = [
    CaptionStyle(
      id: 'classic',
      label: 'Classic',
      outlineColor: Colors.black,
      outlineWidth: 4,
    ),
    CaptionStyle(
      id: 'box',
      label: 'Box',
      fontFamily: 'Roboto',
      fontSize: 58,
      boxColor: Color(0xB3000000),
      shadow: false,
    ),
    CaptionStyle(
      id: 'bold',
      label: 'Bold yellow',
      fontFamily: 'Anton',
      fontSize: 72,
      color: Color(0xFFFFD60A),
      fontWeight: FontWeight.normal,
      outlineColor: Colors.black,
      outlineWidth: 5,
    ),
    CaptionStyle(
      id: 'pop',
      label: 'Pop',
      fontFamily: 'Poppins',
      outlineColor: Colors.black,
      outlineWidth: 4,
      animIn: 'pop',
    ),
  ];

  /// [t] with this look (keeps its text, timing and position).
  TextOverlay applyTo(TextOverlay t) => t.copyWith(
        fontFamily: fontFamily,
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        boxColor: boxColor,
        clearBox: boxColor == null,
        outlineColor: outlineColor,
        clearOutline: outlineColor == null,
        outlineWidth: outlineWidth,
        shadow: shadow,
        animIn: animIn,
        animOut: 'none',
        textAlign: TextAlignEnum.center,
        fontStyle: FontStyleEnum.normal,
      );
}
