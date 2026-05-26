import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/transition.dart';
import '../providers/video_editor_provider.dart';
import '../models/video_project.dart';

class TransitionEditor extends StatefulWidget {
  final String? selectedClipId;
  final ValueChanged<Transition>? onTransitionSelected;

  const TransitionEditor({
    super.key,
    this.selectedClipId,
    this.onTransitionSelected,
  });

  @override
  State<TransitionEditor> createState() => _TransitionEditorState();
}

class _TransitionEditorState extends State<TransitionEditor> {
  TransitionType _selectedTransitionType = TransitionType.crossfade;
  Duration _transitionDuration = const Duration(milliseconds: 500);

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context);
    final selectedClip = widget.selectedClipId != null
        ? provider.currentProject?.videoClips.firstWhere(
            (clip) => clip.id == widget.selectedClipId,
            orElse: () => VideoClip(
              id: '',
              mediaType: MediaType.video,
              startTime: Duration.zero,
              endTime: const Duration(seconds: 1),
            ),
          )
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Transition',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildTransitionTypes(),
            const SizedBox(height: 16),
            _buildDurationSlider(),
            const SizedBox(height: 16),
            _buildApplyButton(provider, selectedClip),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitionTypes() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.2,
      ),
      itemCount: TransitionType.values.length,
      itemBuilder: (context, index) {
        final type = TransitionType.values[index];
        final isSelected = type == _selectedTransitionType;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedTransitionType = type;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(type.getIcon(), color: Colors.white),
                const SizedBox(height: 4),
                Text(
                  type.getDisplayName().split(' ').first,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDurationSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Duration',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                  ),
            ),
            Text(
              '${_transitionDuration.inMilliseconds}ms',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                  ),
            ),
          ],
        ),
        Slider(
          value: _transitionDuration.inMilliseconds.toDouble(),
          min: 100,
          max: 2000,
          divisions: 19,
          activeColor: Theme.of(context).primaryColor,
          inactiveColor: Colors.grey.withOpacity(0.5),
          onChanged: (value) {
            setState(() {
              _transitionDuration = Duration(milliseconds: value.round());
            });
          },
        ),
      ],
    );
  }

  Widget _buildApplyButton(
    VideoEditorProvider provider,
    dynamic selectedClip,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () {
          if (widget.selectedClipId != null) {
            final nextClipId = _getNextClipId(provider, widget.selectedClipId!);
            if (nextClipId != null) {
              final nextClip = provider.currentProject!.videoClips.firstWhere((c) => c.id == nextClipId);
              final td = _transitionDuration.inMilliseconds.toDouble();
              final currentDur = selectedClip.trimmedDuration.inMilliseconds.toDouble();
              final nextDur = nextClip.trimmedDuration.inMilliseconds.toDouble();
              double safeDur = td;
              if (safeDur > currentDur * 0.4) safeDur = currentDur * 0.4;
              if (safeDur > nextDur * 0.4) safeDur = nextDur * 0.4;
              final safeDuration = Duration(milliseconds: safeDur.toInt());

              final transition = Transition(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                clipId1: widget.selectedClipId!,
                clipId2: nextClipId,
                type: _selectedTransitionType,
                duration: safeDuration,
                startTime: selectedClip.endTime - safeDuration,
              );

              provider.addTransition(transition);
              widget.onTransitionSelected?.call(transition);
            }
          }
        },
        child: const Text(
          'Apply Transition',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String? _getNextClipId(VideoEditorProvider provider, String currentClipId) {
    final project = provider.currentProject;
    if (project == null || project.videoClips.isEmpty) return null;

    final currentIndex =
        project.videoClips.indexWhere((clip) => clip.id == currentClipId);
    if (currentIndex == -1 || currentIndex >= project.videoClips.length - 1) {
      return null;
    }

    return project.videoClips[currentIndex + 1].id;
  }
}

extension on TransitionType {
  IconData getIcon() {
    switch (this) {
      case TransitionType.crossfade:
        return Icons.blur_circular;
      case TransitionType.zoom:
        return Icons.zoom_in;
      case TransitionType.slideLeft:
        return Icons.arrow_back;
      case TransitionType.slideRight:
        return Icons.arrow_forward;
      case TransitionType.slideUp:
        return Icons.arrow_upward;
      case TransitionType.slideDown:
        return Icons.arrow_downward;
      case TransitionType.black:
        return Icons.brightness_1;
      case TransitionType.white:
        return Icons.brightness_5;
      case TransitionType.shake:
        return Icons.vibration;
      case TransitionType.light:
        return Icons.flash_on;
      case TransitionType.pixelate:
        return Icons.grid_on;
      case TransitionType.circle:
        return Icons.circle_outlined;
      case TransitionType.push:
        return Icons.arrow_back;
      case TransitionType.pushRight:
        return Icons.arrow_forward;
      case TransitionType.rotate1:
        return Icons.rotate_right;
      case TransitionType.rotate2:
        return Icons.rotate_left;
      case TransitionType.blink:
        return Icons.visibility;
      case TransitionType.vertical:
        return Icons.swap_vert;
      case TransitionType.horizontal:
        return Icons.swap_horiz;
    }
  }

  String getDisplayName() {
    switch (this) {
      case TransitionType.crossfade:
        return 'Cross Fade';
      case TransitionType.zoom:
        return 'Zoom';
      case TransitionType.slideLeft:
        return 'Slide Left';
      case TransitionType.slideRight:
        return 'Slide Right';
      case TransitionType.slideUp:
        return 'Slide Up';
      case TransitionType.slideDown:
        return 'Slide Down';
      case TransitionType.black:
        return 'Black';
      case TransitionType.white:
        return 'White';
      case TransitionType.shake:
        return 'Shake';
      case TransitionType.light:
        return 'Light';
      case TransitionType.pixelate:
        return 'Pixelate';
      case TransitionType.circle:
        return 'Circle';
      case TransitionType.push:
        return 'Push Left';
      case TransitionType.pushRight:
        return 'Push Right';
      case TransitionType.rotate1:
        return 'Rotate 1';
      case TransitionType.rotate2:
        return 'Rotate 2';
      case TransitionType.blink:
        return 'Blink';
      case TransitionType.vertical:
        return 'Vertical';
      case TransitionType.horizontal:
        return 'Horizontal';
    }
  }
}
