import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../main.dart' show AppColors;
import '../../models/video_project.dart';
import '../../services/video_thumbnail_service.dart';
import 'home_prefs.dart';

const kHomeAccent = Color(0xFFCBAAFF);

/// Light haptic tick, respecting the user's setting.
void homeHaptic(HomePrefs? prefs, {bool heavy = false}) {
  if (prefs != null && !prefs.haptics) return;
  heavy ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final Color? color;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: color ?? Colors.white.withValues(alpha: 0.11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: child,
    );
  }
}

/// Sharp project cover: a frame from the middle of the first clip at a
/// resolution suitable for large grid cards (the old cover was a tiny
/// first-frame timeline thumbnail, upscaled and blurry).
class ProjectCover extends StatefulWidget {
  final VideoProject project;
  final int refreshToken;
  final BoxFit fit;

  const ProjectCover({
    super.key,
    required this.project,
    this.refreshToken = 0,
    this.fit = BoxFit.cover,
  });

  @override
  State<ProjectCover> createState() => _ProjectCoverState();
}

class _ProjectCoverState extends State<ProjectCover> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _requestKey;

  VideoClip? get _firstClip {
    final clips = widget.project.videoClips;
    if (clips.isEmpty) return null;
    return clips.reduce((a, b) => a.startTime <= b.startTime ? a : b);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProjectCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  /// Called from initState/didUpdateWidget, so the synchronous part only
  /// assigns fields (the coming build picks them up); setState is used once
  /// the frame has been extracted.
  Future<void> _load() async {
    final clip = _firstClip;
    if (clip == null ||
        clip.mediaType != MediaType.video ||
        clip.videoFile == null) {
      return;
    }
    final path = clip.videoFile!.path;
    final mid = clip.trimStart + (clip.trimEnd - clip.trimStart) ~/ 2;
    final timeMs = mid.inMilliseconds < 0 ? 0 : mid.inMilliseconds;
    final key = '$path|$timeMs|${widget.refreshToken}';
    if (key == _requestKey) return;
    _requestKey = key;

    final service = VideoThumbnailService();
    final cached = service.getCached(path, timeMs);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _loading = true;
    var bytes = await service.getThumbnail(
      videoPath: path,
      timeMs: timeMs,
      maxHeight: 420,
      quality: 80,
    );
    // Another cover may already be extracting this frame (the service then
    // returns null); wait for its result to land in the cache.
    for (var i = 0; bytes == null && i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || key != _requestKey) return;
      bytes = service.getCached(path, timeMs);
    }
    if (!mounted || key != _requestKey) return;
    setState(() {
      _loading = false;
      if (bytes != null) _bytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clip = _firstClip;
    Widget child;
    if (clip == null) {
      child = const _CoverPlaceholder(icon: Icons.video_library_outlined);
    } else if (clip.mediaType == MediaType.image && clip.imageFile != null) {
      child = Image.file(
        clip.imageFile!,
        fit: widget.fit,
        cacheWidth: 600,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            const _CoverPlaceholder(icon: Icons.broken_image_outlined),
      );
    } else if (_bytes != null) {
      child = Image.memory(_bytes!, fit: widget.fit, gaplessPlayback: true);
    } else if (_loading) {
      child = const _CoverPlaceholder(loading: true);
    } else {
      child = const _CoverPlaceholder(icon: Icons.play_circle_outline);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SizedBox.expand(key: ValueKey(child.runtimeType), child: child),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  final IconData? icon;
  final bool loading;
  const _CoverPlaceholder({this.icon, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.35),
            Colors.black.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 1.6, color: kHomeAccent),
              )
            : Icon(icon, color: Colors.white54, size: 28),
      ),
    );
  }
}

/// Fades and slides a child in once, staggered by [index].
class StaggeredEntry extends StatefulWidget {
  final int index;
  final Widget child;
  final bool animate;

  const StaggeredEntry({
    super.key,
    required this.index,
    required this.child,
    this.animate = true,
  });

  @override
  State<StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 55 * widget.index.clamp(0, 10));
    _delay = Timer(delay, _c.forward);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(curved),
        child: widget.child,
      ),
    );
  }
}

class HomeBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const HomeBadge(this.label, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? Colors.black)
            .withValues(alpha: color == null ? 0.6 : 0.85),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: Colors.white),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Bottom-sheet scaffold shared by the home sheets.
Future<T?> showHomeSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1A1A1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    ),
  );
}

/// Simple text-entry dialog used for renaming and new folders.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'Save',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 50,
        decoration: InputDecoration(hintText: hint, counterText: ''),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: Text(action),
        ),
      ],
    ),
  );
}
