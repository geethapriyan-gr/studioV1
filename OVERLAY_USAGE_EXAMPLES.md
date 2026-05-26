# Usage Examples: Draggable Media Overlays

## Basic Usage

### 1. Adding an Overlay Video/Image

```dart
// In your UI code or provider
import 'package:file_picker/file_picker.dart';

// Pick a file to add as overlay
final result = await FilePicker.platform.pickFiles(
  type: FileType.media,
);

if (result != null) {
  final file = File(result.files.single.path!);
  
  // Add to provider
  provider.addOverlayClipFromFile(
    file: file,
    mediaType: MediaType.video, // or MediaType.image
  );
}
```

### 2. Programmatic Positioning

```dart
// Get the overlay clip
final overlayClip = provider.currentProject?.overlayClips.first;

if (overlayClip != null) {
  // Update position (normalized 0.0-1.0)
  provider.updateOverlayClipPosition(
    overlayClip.id,
    Offset(0.2, 0.3), // 20% from left, 30% from top
  );
  
  // Update size (normalized 0.0-1.0)
  provider.updateOverlayClipSize(
    overlayClip.id,
    Size(0.4, 0.4), // 40% width, 40% height
  );
  
  // Update opacity
  provider.updateOverlayClipOpacity(
    overlayClip.id,
    0.8, // 80% opaque
  );
}
```

### 3. Selection & Deletion

```dart
// Select an overlay
provider.selectOverlayClip('overlay_clip_123');

// Check what's selected
if (provider.selectedOverlayClipId != null) {
  print('Selected: ${provider.selectedOverlayClipId}');
}

// Deselect
provider.selectOverlayClip(null);

// Delete overlay
if (provider.selectedOverlayClipId != null) {
  provider.removeOverlayClip(provider.selectedOverlayClipId!);
}
```

---

## Complete Example: Picture-in-Picture Layout

```dart
class PictureInPictureExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<VideoEditorProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            // Video Preview (with overlays)
            Expanded(
              child: VideoPreviewWidget(provider: provider),
            ),
            
            // Control Panel
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ElevatedButton(
                    onPressed: () => _addOverlay(context, provider),
                    child: Text('Add Overlay'),
                  ),
                  ElevatedButton(
                    onPressed: () => _removeSelectedOverlay(provider),
                    child: Text('Remove Selected'),
                  ),
                  ElevatedButton(
                    onPressed: () => _resetOverlayPosition(provider),
                    child: Text('Reset Position'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  
  void _addOverlay(BuildContext context, VideoEditorProvider provider) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
    );
    
    if (result != null) {
      final file = File(result.files.single.path!);
      final isVideo = file.path.endsWith('.mp4') || file.path.endsWith('.mov');
      
      provider.addOverlayClipFromFile(
        file: file,
        mediaType: isVideo ? MediaType.video : MediaType.image,
      );
    }
  }
  
  void _removeSelectedOverlay(VideoEditorProvider provider) {
    if (provider.selectedOverlayClipId != null) {
      provider.removeOverlayClip(provider.selectedOverlayClipId!);
      provider.selectOverlayClip(null);
    }
  }
  
  void _resetOverlayPosition(VideoEditorProvider provider) {
    if (provider.selectedOverlayClipId != null) {
      provider.updateOverlayClipPosition(
        provider.selectedOverlayClipId!,
        Offset(0.1, 0.1), // Default position
      );
      
      provider.updateOverlayClipSize(
        provider.selectedOverlayClipId!,
        Size(0.3, 0.3), // Default size
      );
    }
  }
}
```

---

## Advanced Positioning

### Corner Positions

```dart
// Top-left corner
provider.updateOverlayClipPosition(clipId, Offset(0.0, 0.0));

// Top-right corner
provider.updateOverlayClipPosition(clipId, Offset(0.7, 0.0));

// Bottom-left corner
provider.updateOverlayClipPosition(clipId, Offset(0.0, 0.7));

// Bottom-right corner
provider.updateOverlayClipPosition(clipId, Offset(0.7, 0.7));

// Center
provider.updateOverlayClipPosition(clipId, Offset(0.35, 0.35));
```

### Size Variations

```dart
// Small overlay (20% of screen)
provider.updateOverlayClipSize(clipId, Size(0.2, 0.2));

// Medium overlay (40% of screen)
provider.updateOverlayClipSize(clipId, Size(0.4, 0.4));

// Large overlay (60% of screen)
provider.updateOverlayClipSize(clipId, Size(0.6, 0.6));

// Full-size (subtract from edges to stay in bounds)
provider.updateOverlayClipSize(clipId, Size(0.9, 0.9));
```

---

## Batch Operations

```dart
/// Set up multiple overlays in a grid
void setupGridOverlays(VideoEditorProvider provider) {
  final overlays = provider.currentProject?.overlayClips ?? [];
  
  // Position overlays in a 2x2 grid
  if (overlays.length >= 1) {
    // Top-left
    provider
      .updateOverlayClipPosition(overlays[0].id, Offset(0.0, 0.0))
      .updateOverlayClipSize(overlays[0].id, Size(0.45, 0.45));
  }
  
  if (overlays.length >= 2) {
    // Top-right
    provider
      .updateOverlayClipPosition(overlays[1].id, Offset(0.55, 0.0))
      .updateOverlayClipSize(overlays[1].id, Size(0.45, 0.45));
  }
  
  if (overlays.length >= 3) {
    // Bottom-left
    provider
      .updateOverlayClipPosition(overlays[2].id, Offset(0.0, 0.55))
      .updateOverlayClipSize(overlays[2].id, Size(0.45, 0.45));
  }
  
  if (overlays.length >= 4) {
    // Bottom-right
    provider
      .updateOverlayClipPosition(overlays[3].id, Offset(0.55, 0.55))
      .updateOverlayClipSize(overlays[3].id, Size(0.45, 0.45));
  }
}
```

---

## Animation Example

```dart
import 'package:flutter/animation.dart';

class AnimatedOverlayExample extends StatefulWidget {
  final String overlayClipId;
  final VideoEditorProvider provider;
  
  const AnimatedOverlayExample({
    required this.overlayClipId,
    required this.provider,
  });
  
  @override
  _AnimatedOverlayExampleState createState() => _AnimatedOverlayExampleState();
}

class _AnimatedOverlayExampleState extends State<AnimatedOverlayExample>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    
    _positionAnimation = Tween<Offset>(
      begin: Offset(0.1, 0.1),
      end: Offset(0.6, 0.6),
    ).animate(_controller);
    
    _positionAnimation.addListener(() {
      widget.provider.updateOverlayClipPosition(
        widget.overlayClipId,
        _positionAnimation.value,
      );
    });
    
    _controller.forward();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) => SizedBox.shrink();
}
```

---

## Testing the Feature

```dart
void testOverlayFeatures(VideoEditorProvider provider) {
  // Create test overlay
  final testFile = File('path/to/test_video.mp4');
  provider.addOverlayClipFromFile(
    file: testFile,
    mediaType: MediaType.video,
  );
  
  // Get the overlay
  final overlay = provider.currentProject?.overlayClips.last;
  assert(overlay != null);
  
  // Test position update
  provider.updateOverlayClipPosition(overlay!.id, Offset(0.5, 0.5));
  assert(overlay.overlayPosition == Offset(0.5, 0.5));
  
  // Test size update
  provider.updateOverlayClipSize(overlay.id, Size(0.5, 0.5));
  assert(overlay.overlaySize == Size(0.5, 0.5));
  
  // Test selection
  provider.selectOverlayClip(overlay.id);
  assert(provider.selectedOverlayClipId == overlay.id);
  
  // Test deselection
  provider.selectOverlayClip(null);
  assert(provider.selectedOverlayClipId == null);
  
  print('All overlay tests passed! ✅');
}
```

---

## UI Integration Tips

1. **Always check if overlayClips exist**: `provider.currentProject?.overlayClips.isEmpty ?? true`
2. **Use ValueKey for overlay widgets**: Ensures proper widget identity
3. **Listen to provider changes**: Use `Consumer<VideoEditorProvider>` for reactivity
4. **Handle null values**: Overlays might be deleted during playback
5. **Respect aspect ratios**: Consider original media aspect ratio for quality

---

## Troubleshooting

**Q: Overlay not appearing?**
- Check if overlay clip is in `currentProject?.overlayClips`
- Verify position is within bounds (0.0-1.0)
- Ensure media file still exists

**Q: Overlay position not updating?**
- Verify you're using the correct clip ID
- Check that provider is not building during position update
- Ensure position values are normalized (0.0-1.0)

**Q: Can't interact with overlay?**
- Make sure overlay is selected first
- Check gesture detectors aren't being blocked by parent widgets
- Verify overlay size is large enough to tap (min 5%)
