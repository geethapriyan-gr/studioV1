// Flutter imports:
import 'package:flutter/widgets.dart';

/// A widget for applying color filters to its child widget.
class ColorFilterGenerator extends StatefulWidget {
  /// Constructor for creating an instance of ColorFilterGenerator.
  const ColorFilterGenerator({
    super.key,
    required this.filters,
    required this.child,
  });

  /// The matrix of filters to apply.
  final List<List<double>> filters;

  /// The child widget to which the filters are applied.
  final Widget child;

  /// Creates the state for the ColorFilterGenerator widget.
  @override
  State<ColorFilterGenerator> createState() => ColorFilterGeneratorState();
}

/// The state class for the `ColorFilterGenerator` widget.
///
/// This class is responsible for managing the state of the
/// `ColorFilterGenerator` widget, which includes handling the generation and
/// application of color filters.
///
/// It extends the `State` class, which means it holds mutable state for the
/// `ColorFilterGenerator` widget.
class ColorFilterGeneratorState extends State<ColorFilterGenerator> {
  late Widget _filteredWidget;

  late List<List<double>> _tempFilters;

  @override
  void initState() {
    super.initState();
    _generateFilteredWidget();
  }

  /// Generates a filtered widget by applying a series of color filters and
  /// tune adjustments to the child widget.
  ///
  /// This method combines the filters and tune adjustments provided in the
  /// widget's properties and applies them sequentially to the child widget.
  /// The resulting widget with all the applied filters is stored in the
  /// `_filteredWidget` variable.
  ///
  /// The filters and tune adjustments are expected to be in the form of color
  /// matrices, which are
  /// applied using the `ColorFiltered` widget.
  ///
  /// The method performs the following steps:
  /// 1. Initializes the `tree` variable with the child widget.
  /// 2. Stores the filters and tune adjustments in temporary variables.
  /// 3. Combines the filters and tune adjustments into a single list of color
  /// matrices.
  /// 4. Iterates through the list of color matrices and applies each one to
  /// the `tree` widget.
  /// 5. Stores the final filtered widget in the `_filteredWidget` variable.
  void _generateFilteredWidget() {
    Widget tree = widget.child;
    _tempFilters = widget.filters;

    var list = [...widget.filters];

    for (int i = 0; i < list.length; i++) {
      tree = ColorFiltered(
        colorFilter: ColorFilter.matrix(list[i]),
        child: tree,
      );
    }
    _filteredWidget = tree;
  }

  /// Refreshes the filter editor by generating the filtered widget and
  /// updating the state.
  void refresh() {
    _generateFilteredWidget();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filters.hashCode != _tempFilters.hashCode) {
      _generateFilteredWidget();
    }
    return _filteredWidget;
  }
}
