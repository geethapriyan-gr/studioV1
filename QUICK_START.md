# Quick Start: Using Draggable Media Overlays

## ⚡ 30-Second Overview

Your video editor now lets you add **video or image overlays** that sit on top of the main video. You can drag them around and resize them!

---

## 🎯 Step-by-Step Instructions

### Step 1: Add an Overlay
1. In your video editor, use the existing "Add Overlay" button or menu option
2. Select a video file (`.mp4`, `.mov`) or image file (`.jpg`, `.png`)
3. The overlay appears as a small rectangle in the video preview (default: top-left corner)

### Step 2: Move the Overlay
1. **Tap** on the overlay to select it (you'll see a purple/blue border)
2. **Drag** the overlay to move it to your desired position
3. The overlay will stay within the video boundaries

### Step 3: Resize the Overlay
1. With the overlay selected, find the **small circle** in the bottom-right corner
2. **Drag the circle** to make the overlay larger or smaller
3. The entire overlay scales while maintaining aspect ratio

### Step 4: Deselect
1. Tap on the main video background to deselect the overlay
2. The purple border disappears

---

## 💡 Tips & Tricks

### Common Positions

**Picture-in-Picture:**
- Drag to bottom-right corner
- Resize to 20-30% of screen

**Multi-Screen:**
- Add 3-4 overlays
- Position one in each corner
- Resize each to 40-45% of screen width

**Banner/Watermark:**
- Keep at top (dy = 0.0)
- Stretch horizontally (width = 0.8+)
- Small height (0.1-0.15)

### Pro Tips
✨ All changes save automatically  
✨ Works with both videos and images  
✨ Overlays appear below text overlays  
✨ Position is "smart" and works on any screen size  
✨ You can add multiple overlays at once  

---

## 🔍 What You'll See

### Before Selection
```
┌──────────────────────────────────┐
│                                  │
│  Main Video                      │
│  ┌─────────┐                    │
│  │ Overlay │  ← No border       │
│  └─────────┘                    │
│                                  │
└──────────────────────────────────┘
```

### After Tapping Overlay
```
┌──────────────────────────────────┐
│                                  │
│  Main Video                      │
│  ┌═════════┐                    │
│  ║ Overlay ║  ← Purple border   │
│  ╚════════●╝  ← Resize handle   │
│                                  │
└──────────────────────────────────┘
```

---

## ❓ FAQ

**Q: Can I add multiple overlays?**  
Yes! Add as many as you want. They stack on top of each other.

**Q: Does it work with videos AND images?**  
Yes! Both video overlays and image overlays work the same way.

**Q: Are changes saved?**  
Yes! Every move and resize is automatically saved.

**Q: Can I undo if I mess up?**  
Yes! Use your regular undo button (same as video clips).

**Q: What if overlay goes off screen?**  
The overlay is constrained - it can't go outside the boundaries.

**Q: How do I delete an overlay?**  
Currently: Use the provider method or remove from overlay clips list.
Future: Red X button will be added to the selected overlay.

**Q: Why normalized positions (0.0-1.0)?**  
This makes the layout work perfectly on any phone, tablet, or screen!

---

## 📱 Current Limitations (v1.0)

- No opacity slider in UI yet (can be adjusted via code)
- No rotation capability yet
- No blend modes yet
- Close/delete button showing but not functional yet

These will be added in future updates!

---

## 🎬 Real-World Examples

### Reaction Video
1. Main video: Someone watching something
2. Overlay: Small video of their reaction
3. Position in corner using drag & resize

### Tutorial Video
1. Main video: Desktop screen capture
2. Overlay: Picture-in-Picture of instructor
3. Keep instructor in bottom-right corner

### Multi-Camera Footage
1. Main video: Camera angle 1
2. Overlay 1: Camera angle 2 (bottom-right)
3. Overlay 2: Camera angle 3 (bottom-left)

---

## 🎓 Understanding Positions

The overlay position uses a simple coordinate system:

```
0.0 ─────────────────────► 1.0 (left to right)
 │
 │   (0.1, 0.1) = 10% from left, 10% from top
 │   
 │     ┌─────────┐
 │     │ Overlay │
 │     └─────────┘
 │
 ▼
1.0 (top to bottom)
```

**Default Starting Position:** `(0.1, 0.1)` = slightly offset from top-left  
**Default Size:** `(0.3, 0.3)` = 30% width and height

---

## 🚀 What's Next?

Once you've added overlays:
1. Export your video (existing export feature will include overlays)
2. Share your creation!
3. Try different layouts and positions
4. Combine with text overlays for maximum effect

---

## ⚙️ Technical Details (Optional)

If you're a developer and want to use overlays programmatically:

```dart
// Add overlay programmatically
provider.addOverlayClipFromFile(
  file: File('path/to/video.mp4'),
  mediaType: MediaType.video,
);

// Position it
provider.updateOverlayClipPosition(clipId, Offset(0.5, 0.5));

// Resize it
provider.updateOverlayClipSize(clipId, Size(0.4, 0.4));

// Select it for editing
provider.selectOverlayClip(clipId);
```

---

## 📞 Troubleshooting

**Overlay not showing?**
→ Check if overlay was added successfully
→ Make sure media file still exists
→ Verify position is within 0.0-1.0 range

**Can't drag overlay?**
→ Make sure it's selected (should have purple border)
→ Try tapping it again to ensure selection
→ Check if another overlay is blocking it

**Overlay disappears after app restart?**
→ This shouldn't happen! Overlay data is saved
→ Check app logs for errors
→ Try re-adding the overlay

---

## ✅ You're All Set!

Start using overlay video/images in your editor. They'll enhance your video projects with:
- Picture-in-picture effects
- Multi-camera views
- Watermarks and logos
- Reaction videos
- And much more!

Happy editing! 🎬
