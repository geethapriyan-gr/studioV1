/// Filter preset model for color filters
class FilterPreset {
  final String name;
  final List<List<double>> filters;
  final String? description;

  const FilterPreset({
    required this.name,
    required this.filters,
    this.description,
  });
}

/// Color filter addons utilities for generating color matrices
class ColorFilterAddons {
  /// Generates a color overlay filter matrix
  static List<double> colorOverlay(
    double r,
    double g,
    double b,
    double scale,
  ) {
    double invScale = 1 - scale;
    return [
      invScale,
      0,
      0,
      0,
      -r * scale,
      0,
      invScale,
      0,
      0,
      -g * scale,
      0,
      0,
      invScale,
      0,
      -b * scale,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates an RGB scale filter matrix
  static List<double> rgbScale(double r, double g, double b) {
    return [r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
  }

  /// Generates an additive color filter matrix
  static List<double> addictiveColor(double r, double g, double b) {
    return [1, 0, 0, 0, r, 0, 1, 0, 0, g, 0, 0, 1, 0, b, 0, 0, 0, 1, 0];
  }

  /// Generates a grayscale filter matrix
  static List<double> grayscale() {
    const double lumR = 0.2126;
    const double lumG = 0.7152;
    const double lumB = 0.0722;
    return [
      lumR,
      lumG,
      lumB,
      0,
      0,
      lumR,
      lumG,
      lumB,
      0,
      0,
      lumR,
      lumG,
      lumB,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates a sepia filter matrix
  static List<double> sepia(double value) {
    double inv0_607 = 1 - 0.607 * value;
    double inv0_314 = 1 - 0.314 * value;
    double inv0_869 = 1 - 0.869 * value;
    return [
      inv0_607,
      0.769 * value,
      0.189 * value,
      0,
      0,
      0.349 * value,
      inv0_314,
      0.168 * value,
      0,
      0,
      0.272 * value,
      0.534 * value,
      inv0_869,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates a brightness adjustment filter matrix
  static List<double> brightness(double value) {
    value = value <= 0 ? value * 255 : value * 100;
    if (value == 0) {
      return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }
    return [
      1,
      0,
      0,
      0,
      value,
      0,
      1,
      0,
      0,
      value,
      0,
      0,
      1,
      0,
      value,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates a contrast adjustment filter matrix
  static List<double> contrast(double value) {
    double adj = value * 255;
    double factor = (259 * (adj + 255)) / (255 * (259 - adj));
    double offset = 128 * (1 - factor);
    return [
      factor,
      0,
      0,
      0,
      offset,
      0,
      factor,
      0,
      0,
      offset,
      0,
      0,
      factor,
      0,
      offset,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates a saturation adjustment filter matrix
  static List<double> saturation(double value) {
    if (value == 0) {
      return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }
    double x = 1 + (value > 0 ? 3 * value : value);
    double xInverted = 1 - x;
    const double lumR = 0.3086;
    const double lumG = 0.6094;
    const double lumB = 0.082;

    return [
      lumR * xInverted + x,
      lumG * xInverted,
      lumB * xInverted,
      0,
      0,
      lumR * xInverted,
      lumG * xInverted + x,
      lumB * xInverted,
      0,
      0,
      lumR * xInverted,
      lumG * xInverted,
      lumB * xInverted + x,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ];
  }

  /// Generates an invert color filter matrix
  static List<double> invert() {
    const double offset = 255.0;
    return [
      -1,
      0,
      0,
      0,
      offset,
      0,
      -1,
      0,
      0,
      offset,
      0,
      0,
      -1,
      0,
      offset,
      0,
      0,
      0,
      1,
      0
    ];
  }
}

/// Preset filters collection from pro_video_editor
class PresetFilters {
  /// No filter
  static FilterPreset none = const FilterPreset(
    name: 'No Filter',
    filters: [],
    description: 'Original colors',
  );

  /// Clarendon: adds light to lighter areas and dark to darker areas
  static FilterPreset clarendon = FilterPreset(
    name: 'Clarendon',
    filters: [
      ColorFilterAddons.brightness(.1),
      ColorFilterAddons.contrast(.1),
      ColorFilterAddons.saturation(.15),
    ],
    description: 'Bright and contrasty',
  );

  /// Increase red color gradient
  static FilterPreset addictiveRed = FilterPreset(
    name: 'Addictive Red',
    filters: [
      ColorFilterAddons.addictiveColor(50, 0, 0),
    ],
    description: 'Red tinted',
  );

  /// Increase blue color gradient
  static FilterPreset addictiveBlue = FilterPreset(
    name: 'Addictive Blue',
    filters: [
      ColorFilterAddons.addictiveColor(0, 0, 50),
    ],
    description: 'Blue tinted',
  );

  /// Gingham: Vintage-inspired, taking some color out
  static FilterPreset gingham = FilterPreset(
    name: 'Gingham',
    filters: [
      ColorFilterAddons.sepia(.04),
      ColorFilterAddons.contrast(-.15),
    ],
    description: 'Vintage look',
  );

  /// Moon: B/W, increase brightness and decrease contrast
  static FilterPreset moon = FilterPreset(
    name: 'Moon',
    filters: [
      ColorFilterAddons.grayscale(),
      ColorFilterAddons.contrast(-.04),
      ColorFilterAddons.brightness(0.1),
    ],
    description: 'Black & white',
  );

  /// Lark: Brightens and intensifies colours but not red hues
  static FilterPreset lark = FilterPreset(
    name: 'Lark',
    filters: [
      ColorFilterAddons.brightness(0.08),
      ColorFilterAddons.grayscale(),
      ColorFilterAddons.contrast(-.04),
    ],
    description: 'Bright monochrome',
  );

  /// Reyes: a vintage filter, gives your photos a "dusty" look
  static FilterPreset reyes = FilterPreset(
    name: 'Reyes',
    filters: [
      ColorFilterAddons.sepia(0.4),
      ColorFilterAddons.brightness(0.13),
      ColorFilterAddons.contrast(-.05),
    ],
    description: 'Dusty vintage',
  );

  /// Juno: Brightens colors, and intensifies red and yellow hues
  static FilterPreset juno = FilterPreset(
    name: 'Juno',
    filters: [
      ColorFilterAddons.rgbScale(1.01, 1.04, 1),
      ColorFilterAddons.saturation(0.3),
    ],
    description: 'Warm & bright',
  );

  /// Slumber: Desaturates the image as well as adds haze
  static FilterPreset slumber = FilterPreset(
    name: 'Slumber',
    filters: [
      ColorFilterAddons.brightness(.1),
      ColorFilterAddons.saturation(-0.5),
    ],
    description: 'Soft & hazy',
  );

  /// Crema: Adds a creamy look
  static FilterPreset crema = FilterPreset(
    name: 'Crema',
    filters: [
      ColorFilterAddons.rgbScale(1.04, 1, 1.02),
      ColorFilterAddons.saturation(-0.05),
    ],
    description: 'Creamy tone',
  );

  /// Ludwig: A slight hint of desaturation
  static FilterPreset ludwig = FilterPreset(
    name: 'Ludwig',
    filters: [
      ColorFilterAddons.brightness(.05),
      ColorFilterAddons.saturation(-0.03),
    ],
    description: 'Soft classic',
  );

  /// Aden: This filter gives a blue/pink natural look
  static FilterPreset aden = FilterPreset(
    name: 'Aden',
    filters: [
      ColorFilterAddons.colorOverlay(228, 130, 225, 0.13),
      ColorFilterAddons.saturation(-0.2),
    ],
    description: 'Cool tones',
  );

  /// Perpetua: Adding a pastel look
  static FilterPreset perpetua = FilterPreset(
    name: 'Perpetua',
    filters: [
      ColorFilterAddons.rgbScale(1.05, 1.1, 1),
    ],
    description: 'Pastel boost',
  );

  /// Amaro: Adds light to an image
  static FilterPreset amaro = FilterPreset(
    name: 'Amaro',
    filters: [
      ColorFilterAddons.saturation(0.3),
      ColorFilterAddons.brightness(0.15),
    ],
    description: 'Bright & vivid',
  );

  /// Mayfair: Applies a warm pink tone
  static FilterPreset mayfair = FilterPreset(
    name: 'Mayfair',
    filters: [
      ColorFilterAddons.colorOverlay(230, 115, 108, 0.05),
      ColorFilterAddons.saturation(0.15),
    ],
    description: 'Warm pink',
  );

  /// xProII: Professional look with increased warmth
  static FilterPreset xProII = FilterPreset(
    name: 'xPro II',
    filters: [
      ColorFilterAddons.sepia(0.15),
      ColorFilterAddons.saturation(0.2),
      ColorFilterAddons.brightness(0.05),
    ],
    description: 'Professional',
  );

  /// Get all available presets
  static List<FilterPreset> getAllPresets() {
    return [
      none,
      clarendon,
      addictiveRed,
      addictiveBlue,
      gingham,
      moon,
      lark,
      reyes,
      juno,
      slumber,
      crema,
      ludwig,
      aden,
      perpetua,
      amaro,
      mayfair,
      xProII,
    ];
  }
}
