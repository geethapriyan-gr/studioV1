import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';
import '../models/filter_presets.dart';
import '../models/cinematic_filters.dart';
import '../main.dart' show AppColors;
import 'modern_slider.dart';

class FilterEditor extends StatefulWidget {
  const FilterEditor({super.key});

  @override
  State<FilterEditor> createState() => _FilterEditorState();
}

class _FilterEditorState extends State<FilterEditor> {
  late ColorFilter _currentFilter;
  String _selectedAdjustment = 'Brightness';
  String _selectedCinematicFilterName = 'Original';
  double _filterIntensity = 1.0;

  final List<Map<String, dynamic>> _adjustments = [
    {
      'name': 'Brightness',
      'icon': Icons.brightness_6_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Contrast',
      'icon': Icons.contrast_outlined,
      'min': 0.0,
      'max': 2.0,
      'def': 1.0
    },
    {
      'name': 'Saturation',
      'icon': Icons.palette_outlined,
      'min': 0.0,
      'max': 2.0,
      'def': 1.0
    },
    {
      'name': 'Hue',
      'icon': Icons.tune_outlined,
      'min': -180.0,
      'max': 180.0,
      'def': 0.0
    },
    {
      'name': 'Exposure',
      'icon': Icons.exposure_outlined,
      'min': -2.0,
      'max': 2.0,
      'def': 0.0
    },
    {
      'name': 'Highlights',
      'icon': Icons.highlight_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Shadows',
      'icon': Icons.brightness_low_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Warmth',
      'icon': Icons.wb_sunny_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Tint',
      'icon': Icons.gradient_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Temperature',
      'icon': Icons.thermostat_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Sharpness',
      'icon': Icons.blur_off_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Fade',
      'icon': Icons.opacity_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
    {
      'name': 'Luminance',
      'icon': Icons.light_mode_outlined,
      'min': -1.0,
      'max': 1.0,
      'def': 0.0
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentFilter = const ColorFilter();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        final selectedClipId = provider.selectedVideoClipId;
        if (selectedClipId == null) {
          return Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    color: AppColors.textTertiary,
                    size: 32,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Select a clip first',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (provider.currentProject != null) {
          // Read per-clip filter if a clip is selected, otherwise default
          if (provider.clipColorFilters.containsKey(selectedClipId)) {
            _currentFilter = provider.clipColorFilters[selectedClipId]!;
          } else {
            _currentFilter = const ColorFilter();
          }
        }

        return Container(
          color: AppColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Adjust',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              color: AppColors.textTertiary, size: 18),
                          onPressed: () => _resetFilters(provider),
                          tooltip: "Reset All",
                          padding: const EdgeInsets.all(6),
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildCinematicFilterSelector(provider),
                      const SizedBox(height: 12),
                      _buildFilterIntensitySlider(provider),
                      const SizedBox(height: 16),
                      _buildActiveSlider(provider),
                      const SizedBox(height: 16),
                      _buildAdjustmentSelector(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCinematicFilterSelector(VideoEditorProvider provider) {
    final project = provider.currentProject;
    if (project == null) return const SizedBox.shrink();

    VideoClip? activeClip;
    if (provider.selectedVideoClipId != null) {
      activeClip = project.videoClips.cast<VideoClip?>().firstWhere(
            (c) => c?.id == provider.selectedVideoClipId,
            orElse: () => null,
          );
    }
    
    if (activeClip == null) {
      try {
        activeClip = project.videoClips.firstWhere(
          (c) => provider.currentPosition >= c.startTime && provider.currentPosition < c.endTime,
        );
      } catch (e) {
        if (project.videoClips.isNotEmpty) {
           activeClip = project.videoClips.first;
        }
      }
    }

    if (activeClip == null) return const SizedBox.shrink();

    final isImage = activeClip.mediaType == MediaType.image;
    final controller = provider.previewController;

    if (!isImage && (controller == null || !controller.value.isInitialized)) {
      return const SizedBox.shrink();
    }
    if (isImage && activeClip.imageFile == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: cinematicFilters.length,
        itemBuilder: (context, index) {
          final filter = cinematicFilters[index];
          final bool isSelected =
              _selectedCinematicFilterName == filter.name;

          Widget thumb;
          if (isImage) {
            thumb = Image.file(
              activeClip!.imageFile!,
              fit: BoxFit.cover,
              key: ValueKey('thumb_img_${filter.name}_${activeClip.id}'),
            );
          } else {
            thumb = AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: VideoPlayer(
                controller,
                key: ValueKey('thumb_vid_${filter.name}'),
              ),
            );
          }

          thumb = ColorFiltered(
            colorFilter: ui.ColorFilter.matrix(filter.matrix),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumb,
            ),
          );

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCinematicFilterName = filter.name;
              });

              if (filter.name == 'Original') {
                _filterIntensity = 1.0;
                _updateFilter(
                  _currentFilter.copyWith(filterPresetMatrices: const []),
                  provider,
                );
              } else {
                final blended =
                    _blendMatrixWithIdentity(filter.matrix, _filterIntensity);
                provider.applyFilterPreset(
                  FilterPreset(name: filter.name, filters: [blended]),
                );
              }
            },
            child: Container(
              width: 80,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumb,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    filter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterIntensitySlider(VideoEditorProvider provider) {
    final hasFilterPreset =
        _currentFilter.filterPresetMatrices.isNotEmpty;

    if (!hasFilterPreset || _selectedCinematicFilterName == 'Original') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Intensity',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${(_filterIntensity * 100).round()}%',
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
          ModernSlider(
            value: _filterIntensity,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            onChanged: (val) {
              setState(() {
                _filterIntensity = val;
              });

              final filter = cinematicFilters.firstWhere(
                (f) => f.name == _selectedCinematicFilterName,
                orElse: () => cinematicFilters.first,
              );

              if (filter.name == 'Original') {
                _updateFilter(
                  _currentFilter.copyWith(filterPresetMatrices: const []),
                  provider,
                );
              } else {
                final blended =
                    _blendMatrixWithIdentity(filter.matrix, _filterIntensity);
                provider.applyFilterPreset(
                  FilterPreset(name: filter.name, filters: [blended]),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  List<double> _blendMatrixWithIdentity(
      List<double> matrix, double intensity) {
    final List<double> result = List<double>.filled(20, 0.0);
    for (int i = 0; i < 20; i++) {
      final double m = i < matrix.length ? matrix[i] : identityMatrix[i];
      result[i] = identityMatrix[i] + (m - identityMatrix[i]) * intensity;
    }
    return result;
  }

  Widget _buildAdjustmentSelector() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: _adjustments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = _adjustments[index];
          final isSelected = _selectedAdjustment == item['name'];
          return GestureDetector(
            onTap: () => setState(() => _selectedAdjustment = item['name']),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? AppColors.primary : AppColors.surfaceLight,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    item['icon'],
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item['name'],
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontSize: 9,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveSlider(VideoEditorProvider provider) {
    final config =
        _adjustments.firstWhere((e) => e['name'] == _selectedAdjustment);
    final double min = config['min'];
    final double max = config['max'];

    double currentValue = 0.0;

    switch (_selectedAdjustment) {
      case 'Brightness':
        currentValue = _currentFilter.brightness;
        break;
      case 'Contrast':
        currentValue = _currentFilter.contrast;
        break;
      case 'Saturation':
        currentValue = _currentFilter.saturation;
        break;
      case 'Hue':
        currentValue = _currentFilter.hue;
        break;
      case 'Exposure':
        currentValue = _currentFilter.exposure;
        break;
      case 'Highlights':
        currentValue = _currentFilter.highlights;
        break;
      case 'Shadows':
        currentValue = _currentFilter.shadows;
        break;
      case 'Warmth':
        currentValue = _currentFilter.warmth;
        break;
      case 'Tint':
        currentValue = _currentFilter.tint;
        break;
      case 'Temperature':
        currentValue = _currentFilter.temperature;
        break;
      case 'Sharpness':
        currentValue = _currentFilter.sharpness;
        break;
      case 'Fade':
        currentValue = _currentFilter.fade;
        break;
      case 'Luminance':
        currentValue = _currentFilter.luminance;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ModernSlider(
        value: currentValue,
        min: min,
        max: max,
        divisions: 100,
        label: _selectedAdjustment,
        onChanged: (val) {
          ColorFilter newFilter = _currentFilter;
          switch (_selectedAdjustment) {
            case 'Brightness':
              newFilter = newFilter.copyWith(brightness: val);
              break;
            case 'Contrast':
              newFilter = newFilter.copyWith(contrast: val);
              break;
            case 'Saturation':
              newFilter = newFilter.copyWith(saturation: val);
              break;
            case 'Hue':
              newFilter = newFilter.copyWith(hue: val);
              break;
            case 'Exposure':
              newFilter = newFilter.copyWith(exposure: val);
              break;
            case 'Highlights':
              newFilter = newFilter.copyWith(highlights: val);
              break;
            case 'Shadows':
              newFilter = newFilter.copyWith(shadows: val);
              break;
            case 'Warmth':
              newFilter = newFilter.copyWith(warmth: val);
              break;
            case 'Tint':
              newFilter = newFilter.copyWith(tint: val);
              break;
            case 'Temperature':
              newFilter = newFilter.copyWith(temperature: val);
              break;
            case 'Sharpness':
              newFilter = newFilter.copyWith(sharpness: val);
              break;
            case 'Fade':
              newFilter = newFilter.copyWith(fade: val);
              break;
            case 'Luminance':
              newFilter = newFilter.copyWith(luminance: val);
              break;
          }
          _updateFilter(newFilter, provider);
        },
      ),
    );
  }



  void _updateFilter(ColorFilter newFilter, VideoEditorProvider provider) {
    setState(() => _currentFilter = newFilter);
    provider.applyColorFilter(newFilter);
  }

  void _resetFilters(VideoEditorProvider provider) {
    _updateFilter(const ColorFilter(), provider);
  }
}
