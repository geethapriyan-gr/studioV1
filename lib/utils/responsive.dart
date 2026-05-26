import 'package:flutter/material.dart';

/// Responsive Design System
/// Adapts all sizes based on device dimensions to prevent overflow
class ResponsiveUtil {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double blockSizeHorizontal;
  static late double blockSizeVertical;

  /// Initialize responsive utilities with BuildContext
  static void init(MediaQueryData mediaQueryData) {
    _mediaQueryData = mediaQueryData;
    screenWidth = mediaQueryData.size.width;
    screenHeight = mediaQueryData.size.height;
    blockSizeHorizontal = screenWidth / 100;
    blockSizeVertical = screenHeight / 100;
  }

  /// Get responsive font size
  static double getFontSize(double baseSize) {
    final scaleFactor = screenWidth / 360; // Base on 360dp phone width
    return (baseSize * scaleFactor).clamp(8.0, baseSize * 1.5);
  }

  /// Get responsive icon size
  static double getIconSize(double baseSize) {
    final scaleFactor = screenWidth / 360;
    final scaled = baseSize * scaleFactor;
    return scaled.clamp(12.0, 48.0);
  }

  /// Get responsive padding/margin
  static double getPadding(double basePadding) {
    final scaleFactor = screenWidth / 360;
    final scaled = basePadding * scaleFactor;
    return scaled.clamp(4.0, basePadding * 2);
  }

  /// Get responsive height
  static double getHeight(double baseHeight) {
    final scaleFactor = screenHeight / 800; // Base on 800dp phone height
    return (baseHeight * scaleFactor).clamp(baseHeight * 0.5, baseHeight * 2);
  }

  /// Get responsive width
  static double getWidth(double baseWidth) {
    final scaleFactor = screenWidth / 360;
    return (baseWidth * scaleFactor).clamp(baseWidth * 0.5, baseWidth * 2);
  }

  /// Get responsive button height
  static double getButtonHeight() {
    if (screenHeight < 600) return 36;
    if (screenHeight < 800) return 40;
    return 44;
  }

  /// Get responsive button width
  static double getButtonWidth(double baseWidth) {
    return (baseWidth * screenWidth / 360)
        .clamp(baseWidth * 0.6, double.infinity);
  }

  /// Get responsive spacing
  static double getSpacing(double baseSpacing) {
    final scaleFactor = screenWidth / 360;
    final scaled = baseSpacing * scaleFactor;
    return scaled.clamp(2.0, baseSpacing * 2.5);
  }

  /// Get responsive border radius
  static double getBorderRadius(double baseRadius) {
    final scaleFactor = screenWidth / 360;
    return (baseRadius * scaleFactor).clamp(2.0, 20.0);
  }

  /// Predefined responsive sizes
  static get iconSizeSmall => getIconSize(12);
  static get iconSizeNormal => getIconSize(18);
  static get iconSizeLarge => getIconSize(24);
  static get iconSizeXL => getIconSize(32);

  /// Font sizes
  static get fontSizeTiny => getFontSize(10);
  static get fontSizeSmall => getFontSize(11);
  static get fontSizeNormal => getFontSize(13);
  static get fontSizeMedium => getFontSize(14);
  static get fontSizeLarge => getFontSize(16);
  static get fontSizeXL => getFontSize(18);
  static get fontSizeXXL => getFontSize(20);

  /// Paddings
  static get paddingXSmall => getPadding(4);
  static get paddingSmall => getPadding(6);
  static get paddingNormal => getPadding(8);
  static get paddingMedium => getPadding(12);
  static get paddingLarge => getPadding(16);

  /// Spacing
  static get spacingXSmall => getSpacing(2);
  static get spacingSmall => getSpacing(4);
  static get spacingNormal => getSpacing(6);
  static get spacingMedium => getSpacing(8);
  static get spacingLarge => getSpacing(12);
  static get spacingXL => getSpacing(16);

  /// Track heights
  static get trackHeightSmall => getHeight(32);
  static get trackHeightNormal => getHeight(48);
  static get trackHeightLarge => getHeight(56);

  /// Button/Icon constraints
  static get minTouchTarget =>
      getHeight(36); // Min touch target for accessibility
  static get buttonMinHeight => getButtonHeight();
  static get buttonMinWidth => getButtonWidth(60);

  /// Check device type
  static bool get isMobile => screenWidth < 600;
  static bool get isTablet => screenWidth >= 600 && screenWidth < 1200;
  static bool get isLandscape =>
      _mediaQueryData.orientation == Orientation.landscape;
}

/// Widget builder for responsive design
/// Wrap your widgets with this builder to initialize ResponsiveUtil
class ResponsiveBuilder extends StatefulWidget {
  final Widget Function(BuildContext context) builder;

  const ResponsiveBuilder({required this.builder, super.key});

  @override
  State<ResponsiveBuilder> createState() => _ResponsiveBuilderState();
}

class _ResponsiveBuilderState extends State<ResponsiveBuilder> {
  @override
  Widget build(BuildContext context) {
    ResponsiveUtil.init(MediaQuery.of(context));
    return widget.builder(context);
  }
}
