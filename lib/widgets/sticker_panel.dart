import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/video_editor_provider.dart';
import '../main.dart' show AppColors;

class StickerPanel extends StatefulWidget {
  const StickerPanel({super.key});

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  final List<String> _stickerAssets = [
    'assets/stickers/angry.png',
    'assets/stickers/april.png',
    'assets/stickers/august.png',
    'assets/stickers/awesome.png',
    'assets/stickers/book.png',
    'assets/stickers/books.png',
    'assets/stickers/buffalo.png',
    'assets/stickers/cheetah.png',
    'assets/stickers/comet.png',
    'assets/stickers/cow.png',
    'assets/stickers/creativity (1).png',
    'assets/stickers/creativity (2).png',
    'assets/stickers/creativity.png',
    'assets/stickers/crocodile.png',
    'assets/stickers/december.png',
    'assets/stickers/drawing-tablet.png',
    'assets/stickers/education.png',
    'assets/stickers/february.png',
    'assets/stickers/feed-your-ideas.png',
    'assets/stickers/flamingo.png',
    'assets/stickers/friday.png',
    'assets/stickers/good-things-are-coming.png',
    'assets/stickers/graduate.png',
    'assets/stickers/hedgehog.png',
    'assets/stickers/horse.png',
    'assets/stickers/january.png',
    'assets/stickers/july.png',
    'assets/stickers/june.png',
    'assets/stickers/march.png',
    'assets/stickers/may.png',
    'assets/stickers/monday.png',
    'assets/stickers/mortarboard.png',
    'assets/stickers/new-ideas-in-process.png',
    'assets/stickers/november.png',
    'assets/stickers/october.png',
    'assets/stickers/online-class.png',
    'assets/stickers/online-education.png',
    'assets/stickers/painting-palette.png',
    'assets/stickers/pencil-case.png',
    'assets/stickers/pig.png',
    'assets/stickers/reading (1).png',
    'assets/stickers/reading.png',
    'assets/stickers/rocket (1).png',
    'assets/stickers/rocket (2).png',
    'assets/stickers/rocket.png',
    'assets/stickers/saturday.png',
    'assets/stickers/Screenshot_2026-04-01_100038-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100047-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100058-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100108-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100118-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100124-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100141-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100146-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100153-removebg-preview (1).png',
    'assets/stickers/Screenshot_2026-04-01_100153-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100159-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100208-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100214-removebg-preview (1).png',
    'assets/stickers/Screenshot_2026-04-01_100214-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100221-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100231-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100237-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100248-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100254-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100304-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100327-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100335-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100350-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100400-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100412-removebg-preview.png',
    'assets/stickers/Screenshot_2026-04-01_100417-removebg-preview.png',
    'assets/stickers/september.png',
    'assets/stickers/sheep.png',
    'assets/stickers/star.png',
    'assets/stickers/study.png',
    'assets/stickers/studying (1).png',
    'assets/stickers/studying (2).png',
    'assets/stickers/studying.png',
    'assets/stickers/sunday.png',
    'assets/stickers/thursday.png',
    'assets/stickers/today-is-the-perfect-day.png',
    'assets/stickers/tuesday.png',
    'assets/stickers/wednesday.png',
    'assets/stickers/yeah (1).png',
    'assets/stickers/yeah.png',
  ];

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VideoEditorProvider>(context);

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemCount: _stickerAssets.length,
              itemBuilder: (context, index) {
                return _buildStickerItem(
                  context,
                  provider,
                  _stickerAssets[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Stickers',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerItem(
    BuildContext context,
    VideoEditorProvider provider,
    String assetPath,
  ) {
    return GestureDetector(
      onTap: () => _onStickerSelected(provider, assetPath),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Center(
          child: Image.asset(
            assetPath,
            width: 64,
            height: 64,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  void _onStickerSelected(VideoEditorProvider provider, String assetPath) {
    // Add sticker to the project at current timeline position
    final start = provider.currentPosition;
    final end = start + const Duration(seconds: 5);
    
    provider.addSticker(
      assetPath: assetPath,
      position: const Offset(0.5, 0.5),
      scale: 1.0,
      rotation: 0.0,
      startTime: start,
      endTime: end,
      opacity: 1.0,
    );

    _closeStickerPanel();
  }

  void _closeStickerPanel() {
    final provider = Provider.of<VideoEditorProvider>(context, listen: false);
    provider.toggleTimeline();
  }
}
