# Draggable Media Overlay Feature Implementation

## Overview
This implementation adds support for draggable video/image overlays on top of the main video in your Flutter video editor. The overlaid media appears in a smaller size and can be repositioned and resized by dragging on the preview screen.

## What Was Added

### 1. **Extended VideoClip Model** (`lib/models/video_project.dart`)
Added three new fields to the `VideoClip` class to support overlay positioning:
- `overlayPosition`: Normalized position (0.0-1.0) relative to parent
- `overlaySize`: Normalized size (0.0-1.0) relative to parent  
- `overlayOpacity`: Opacity value for the overlay

These fields are automatically serialized to Hive for persistence.

### 2. **DraggableMediaOverlay Widget** (`lib/widgets/draggable_media_overlay_widget.dart`)
A new stateful widget that:
- Displays the overlay media (video or image) with a border
- Supports **drag to move** the overlay across the screen
- Supports **resize handle** (bottom-right corner) to resize the overlay
- Shows a **close button** when selected
- Applies constraints to keep overlays within parent bounds
- Includes shadow and styling for visual feedback

### 3. **Provider Methods** (`lib/providers/video_editor_provider.dart`)
Added three new methods to manage overlay clips:
- `updateOverlayClipPosition(String clipId, Offset newPosition)`: Update position
- `updateOverlayClipSize(String clipId, Size newSize)`: Update size
- `updateOverlayClipOpacity(String clipId, double opacity)`: Update opacity
- `selectOverlayClip(String? clipId)`: Select/deselect overlay for editing

Also added:
- `_selectedOverlayClipId`: Track which overlay is currently selected
- `selectedOverlayClipId` getter: Access the selected overlay ID

### 4. **Video Editor Screen Integration** (`lib/screens/video_editor_screen.dart`)
- Integrated the `DraggableMediaOverlay` widget into the main video preview stack
- Overlays appear between the base video and text overlays in the z-order
- Added gesture handling for positioning and sizing updates
- Overlays update in real-time as you drag and resize them

## How to Use

### Adding an Overlay Clip
```dart
// In your provider or UI code
final clipFile = File('path/to/overlay_video.mp4');
final mediaType = MediaType.video; // or MediaType.image

provider.addOverlayClipFromFile(
  file: clipFile,
  mediaType: mediaType,
);
```

### Positioning an Overlay
1. Tap on the overlay to select it (border becomes highlighted)
2. Drag anywhere on the overlay to move it
3. Drag the circular handle in the bottom-right corner to resize it
4. All changes are automatically saved

### Viewing Overlays
- All overlays in `currentProject.overlayClips` are displayed on the preview
- Position and size are stored and loaded automatically
- Overlays persist between sessions

## Technical Details

```dart
// Example overlay clip structure
VideoClip overlayClip = VideoClip(
  id: 'clip_123',
  mediaType: MediaType.video,
  videoFile: File('...'),
  startTime: Duration.zero,
  endTime: Duration(seconds: 5),
  overlayPosition: Offset(0.1, 0.1),  // 10% from left, 10% from top
  overlaySize: Size(0.3, 0.3),        // 30% width, 30% height
  overlayOpacity: 1.0,
);
```

## Features

✅ **Drag to Move**: Click and drag the overlay anywhere on the screen
✅ **Resize Handle**: Drag the bottom-right corner to resize
✅ **Selection Feedback**: Visual border shows when overlay is selected
✅ **Constraint Boundaries**: Overlays stay within parent bounds
✅ **Auto-Save**: All position/size changes are automatically saved
✅ **Persistent State**: Position data is saved to Hive storage
✅ **Z-Order Support**: Overlays layer properly with text overlays
✅ **Image & Video Support**: Works with both image and video overlays

## File Structure

```
lib/
├── models/
│   └── video_project.dart (extended VideoClip class)
├── widgets/
│   └── draggable_media_overlay_widget.dart (NEW)
├── providers/
│   └── video_editor_provider.dart (added overlay management methods)
└── screens/
    └── video_editor_screen.dart (integrated overlay rendering)
```

## Notes

- Normalized positions range from 0.0 to 1.0, allowing responsive layout on different screen sizes
- The overlay widget handles parent size constraints automatically
- All data is serialized and persists through app restarts
- Overlays are rendered above the main video but below text overlays
