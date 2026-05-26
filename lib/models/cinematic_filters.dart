class FilterModel {
  final String name;
  final List<double> matrix;

  const FilterModel({
    required this.name,
    required this.matrix,
  });
}

// Identity matrix (no color change)
const List<double> identityMatrix = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
];

// 1. Black & White
const List<double> blackWhiteMatrix = [
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

// 2. Vintage – warm faded old photo tone
const List<double> vintageMatrix = [
  0.9, 0.5, 0.1, 0, 0,
  0.3, 0.8, 0.1, 0, 0,
  0.2, 0.3, 0.7, 0, 0,
  0, 0, 0, 1, 0,
];

// 3. Warm – increase red/orange tone
const List<double> warmMatrix = [
  1.2, 0, 0, 0, 0,
  0, 1.05, 0, 0, 0,
  0, 0, 0.9, 0, 0,
  0, 0, 0, 1, 0,
];

// 4. Cool – increase blue tone
const List<double> coolMatrix = [
  0.9, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1.2, 0, 0,
  0, 0, 0, 1, 0,
];

// 5. Drama – high contrast cinematic look
const List<double> dramaMatrix = [
  1.5, 0, 0, 0, -30,
  0, 1.5, 0, 0, -30,
  0, 0, 1.5, 0, -30,
  0, 0, 0, 1, 0,
];

// 6. Vivid – boost saturation
const List<double> vividMatrix = [
  1.4, -0.2, -0.2, 0, 0,
  -0.2, 1.4, -0.2, 0, 0,
  -0.2, -0.2, 1.4, 0, 0,
  0, 0, 0, 1, 0,
];

// 7. Film – film camera style
const List<double> filmMatrix = [
  1.1, 0.1, 0.1, 0, 0,
  0.1, 1.1, 0.1, 0, 0,
  0.1, 0.1, 1.1, 0, 0,
  0, 0, 0, 1, 0,
];

// 8. Retro – muted tones
const List<double> retroMatrix = [
  0.8, 0.3, 0.1, 0, 0,
  0.2, 0.7, 0.1, 0, 0,
  0.2, 0.3, 0.6, 0, 0,
  0, 0, 0, 1, 0,
];

// 9. Scenery – boost greens and blues
const List<double> sceneryMatrix = [
  1, 0, 0, 0, 0,
  0, 1.3, 0, 0, 0,
  0, 0, 1.2, 0, 0,
  0, 0, 0, 1, 0,
];

// 10. Fog – soft faded look
const List<double> fogMatrix = [
  0.8, 0, 0, 0, 30,
  0, 0.8, 0, 0, 30,
  0, 0, 0.8, 0, 30,
  0, 0, 0, 1, 0,
];

// 11. Polaroid – warm retro camera look
const List<double> polaroidMatrix = [
  1.3, 0.2, 0.2, 0, 0,
  0.1, 1.1, 0.1, 0, 0,
  0.1, 0.1, 0.9, 0, 0,
  0, 0, 0, 1, 0,
];

const List<FilterModel> cinematicFilters = [
  FilterModel(name: 'Original', matrix: identityMatrix),
  FilterModel(name: 'Black & White', matrix: blackWhiteMatrix),
  FilterModel(name: 'Vintage', matrix: vintageMatrix),
  FilterModel(name: 'Warm', matrix: warmMatrix),
  FilterModel(name: 'Cool', matrix: coolMatrix),
  FilterModel(name: 'Drama', matrix: dramaMatrix),
  FilterModel(name: 'Vivid', matrix: vividMatrix),
  FilterModel(name: 'Film', matrix: filmMatrix),
  FilterModel(name: 'Retro', matrix: retroMatrix),
  FilterModel(name: 'Scenery', matrix: sceneryMatrix),
  FilterModel(name: 'Fog', matrix: fogMatrix),
  FilterModel(name: 'Polaroid', matrix: polaroidMatrix),
];

