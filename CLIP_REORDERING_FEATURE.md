# Video Clip Reordering Feature

## Overview
This feature enables you to change the playback order of video clips in your timeline by using an intuitive drag-and-drop interface. No longer are your clips locked to the order you imported them—you can now easily rearrange them to create the exact sequence you want.

## How It Works

### Basic Concept
When you have multiple clips on the timeline, they play sequentially in the order they appear. The reordering feature allows you to change this sequence without losing any of your clip properties like trimming, effects, or transitions.

### Step-by-Step Instructions

#### 1. **Select a Clip**
   - Tap on any video clip in the timeline to select it
   - The clip will highlight with a brighter color and white border
   - You can see a context menu by **double‑tapping** the clip (long press now starts drag)

#### 2. **Long-Press to Enable Drag**
   - Long-press on the selected clip to activate drag-and-drop mode
   - The clip will display a "Reorder" indicator showing it's in drag mode
   - You'll see a strong highlighted appearance with a larger stroke

#### 3. **Drag to New Position**
   - While holding the long-press, drag the clip to the left or right
   - Visual drop zone indicators (cyan/accent colored vertical lines) appear between clips and at the ends of the timeline
   - These indicators show valid positions where you can drop the clip

#### 4. **Release to Place**
   - Release your finger/mouse at the desired drop position
   - The clip will be inserted at that position
   - All other clips will automatically shift to accommodate the new order
   - The timeline will update instantly with the new playback order

### Visual Feedback

#### While Dragging
- **Feedback Widget**: Shows enlarged purple/accent colored block with "Reorder" label
- **Drop Zones**: Cyan/accent vertical guides appear between clips showing valid positions
- **Empty Slot**: The original clip position becomes semi-transparent/faded
- **Track Highlighting**: The video track shows slight highlighting to indicate it's active

#### After Dropping
- Clips are instantly rearranged in the new order
- All trimming, effects, and transitions are preserved
- Start and end times are automatically recalculated based on the new order
- The video duration remains the same (it's the combined duration of all clips)

## Key Features

✅ **Preserve All Properties**: Trimming, effects, transitions, volume, playback speed, rotation, crop, and all other settings are maintained

✅ **Visual Guides**: Clear indicators show exactly where your clip will be placed

✅ **Smooth Performance**: Optimized reordering that maintains smooth 60fps operation

✅ **Undo Support**: Reordering actions are fully undoable with Ctrl+Z (Cmd+Z on Mac)

✅ **Auto-Save**: Changes are automatically saved to your project

✅ **Non-Destructive**: Original media files are never modified; only the order is changed

## Technical Details

### What Changes
- **Order in Timeline**: Clips are physically reordered in the clip list
- **Start/End Times**: Automatically recalculated so clips play sequentially
- **Trimmed Duration**: Each clip maintains its trimmed content from the original import

### What Stays the Same
- Video file paths
- Image file paths
- Trimming points
- Volume levels
- Playback speed
- Rotation
- Crop rectangles
- Mirroring
- Mute status
- All effects and transitions
- Chroma key settings
- All other clip properties

## Context Menu Hint

When you **double-tap** a clip, an extended context menu appears with:
- **Duplicate**: Create a copy of the clip
- **Extract Audio**: Extract the audio track to a separate audio overlay
- **Drag to Reorder**: (Info section) Reminds you how to drag clips to change their order

## Practical Examples

### Example 1: Move First Clip to End
```
Before: [Clip A] [Clip B] [Clip C]
Process: Drag Clip A to the right past Clip C
After: [Clip B] [Clip C] [Clip A]
```

### Example 2: Reverse Video Order
```
Before: [Intro] [Main Content] [Outro]
Process: Drag Outro to start, then drag Intro to end
After: [Outro] [Main Content] [Intro]
```

### Example 3: Create Flashback Sequence
```
Before: [Scene 1] [Scene 2] [Scene 3] [Flashback]
Process: Drag Flashback between Scene 1 and Scene 2
After: [Scene 1] [Flashback] [Scene 2] [Scene 3]
```

## Tips & Tricks

1. **Quick Swaps**: Need to swap two adjacent clips? Just drag one over the other and release at the edge

2. **Batch Reordering**: You can reorder multiple clips in succession without reloading

3. **Timeline Scrolling**: If your timeline is very long, dragging near the edges will auto-scroll while you're dragging

4. **Undo Chain**: If you make a mistake, use Ctrl+Z (or Cmd+Z) to undo the reorder

5. **Preview Changes**: After reordering, play the timeline to preview the new sequence

6. **Automatic Compression**: Empty gaps between clips are
 automatically eliminated when you reorder

## Troubleshooting

### Clip Won't Drag
- Make sure you're long-pressing (not just tapping)
- The long-press must be held for the full drag operation
- Try pressing for 0.5-1 second before dragging

### Drop Position Unclear
- Look for the cyan/accent colored vertical guides
- These appear between clips and show valid drop zones
- You must release exactly on or near these guides

### Changes Not Saving
- Auto-save is enabled by default
- Check the notification area for save status
- If issues persist, manually save with Ctrl+S

### Performance Issues
- If dragging feels slow, reduce the number of effects or overlays on the timeline
- Close other apps to free up device memory
- Try restarting the app if drag becomes sluggish

## Implementation Details

### Files Modified
1. **lib/providers/video_editor_provider.dart**
   - Added `reorderVideoClips(int sourceIndex, int targetIndex)` method
   - Added `getTargetIndexForDropPosition(Duration dropTime)` helper method
   - Added `getClipIndexById(String clipId)` helper method

2. **lib/widgets/timeline_widget.dart**
   - Modified `_buildVideoTracks()` to detect and handle reordering drops
   - Added `_findTargetClipIndex()` to calculate target position
   - Added `_buildDropZoneIndicators()` to show visual drop zones
   - Enhanced `feedback` widget with "Reorder" indicator
   - Updated context menu with reordering hint

### How It Works Internally

1. **Drag Detection**: LongPressDraggable widget detects when a clip is long-pressed
2. **Visual Feedback**: Feedback widget displays prominently during drag
3. **Drop Zone Calculation**: Drop zones are calculated based on clip boundaries
4. **Target Identification**: When released, the drop position is converted to a target index
5. **Reordering**: The provider reorders clips and recalculates their start/end times
6. **Auto-Save**: Changes are saved automatically using the provider's auto-save mechanism
7. **UI Update**: The timeline refreshes to show the new order

## Future Enhancements

Potential improvements for future versions:
- [ ] Multi-clip selection and bulk reordering
- [ ] Keyboard shortcuts for quick reordering
- [ ] Clip grouping/stacking
- [ ] Animation preview while dragging
- [ ] Snap-to-grid for precise ordering
- [ ] Clip copy while dragging with modifier key

## Support

If you encounter any issues:
1. Check the troubleshooting section above
2. Try undoing the action (Ctrl+Z)
3. Restart the application
4. Check the console for any error messages
5. Verify you have sufficient disk space and memory

---

**Version**: 1.0  
**Last Updated**: March 2026  
**Status**: Stable
