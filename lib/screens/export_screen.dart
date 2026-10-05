import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../main.dart' show AppColors;
import '../models/video_project.dart';
import '../providers/video_editor_provider.dart';
import '../services/video_thumbnail_service.dart';

/// Export quality presets (x264 CRF + speed preset). "Standard" is exactly
/// what the app exported before.
enum ExportQuality {
  small('Small file', 'Smaller, softer', 28, 'ultrafast', 0.55),
  standard('Standard', 'Balanced (recommended)', 23, 'ultrafast', 1.0),
  high('High', 'Sharper, slower', 19, 'veryfast', 1.25);

  final String label;
  final String hint;
  final int crf;
  final String preset;
  final double sizeFactor;

  const ExportQuality(
      this.label, this.hint, this.crf, this.preset, this.sizeFactor);
}

enum _Stage { setup, exporting, done, failed }

/// Full-screen export: settings with a size estimate, a live progress view
/// (frames of the video being rendered), then an automatic save to the
/// gallery with share options.
class ExportScreen extends StatefulWidget {
  final String outputPath;
  const ExportScreen({super.key, required this.outputPath});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  _Stage _stage = _Stage.setup;
  late int _shortSide;
  late int _fps;
  ExportQuality _quality = ExportQuality.standard;
  DateTime? _startedAt;
  String? _resultPath;
  String? _error;
  bool? _savedToGallery;
  String? _galleryError;

  // Live progress preview.
  Timer? _frameTimer;
  Uint8List? _frame;
  File? _frameImage;

  VideoPlayerController? _resultPlayer;

  static const _shortSides = [480, 720, 1080, 1440, 2160];
  static const _fpsOptions = [24, 25, 30, 60];

  VideoEditorProvider get _provider =>
      Provider.of<VideoEditorProvider>(context, listen: false);

  @override
  void initState() {
    super.initState();
    final project = _provider.currentProject;
    final res = project?.outputResolution ?? const Size(1080, 1920);
    final short = res.width < res.height ? res.width : res.height;
    _shortSide = _shortSides.reduce(
        (a, b) => (a - short).abs() <= (b - short).abs() ? a : b);
    _fps = project?.outputFrameRate ?? 30;
    if (!_fpsOptions.contains(_fps)) _fps = 30;
    // After the first frame: _updateFrame may call setState synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFrame());
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _resultPlayer?.dispose();
    super.dispose();
  }

  // ── Settings helpers ────────────────────────────────────────────────────

  Size get _aspectSource {
    final r = _provider.currentProject?.outputResolution;
    if (r == null || r.width <= 0 || r.height <= 0) {
      return const Size(1080, 1920);
    }
    return r;
  }

  /// Output size for [shortSide], keeping the project's aspect ratio.
  Size _sizeFor(int shortSide) {
    final src = _aspectSource;
    final portrait = src.height >= src.width;
    final ratio = portrait ? src.height / src.width : src.width / src.height;
    int even(double v) => (v / 2).round() * 2;
    final long = even(shortSide * ratio);
    return portrait
        ? Size(shortSide.toDouble(), long.toDouble())
        : Size(long.toDouble(), shortSide.toDouble());
  }

  String _resLabel(int shortSide) =>
      shortSide >= 2160 ? '4K' : (shortSide >= 1440 ? '2K' : '${shortSide}p');

  /// Rough output size: x264 at these settings averages ~0.1 bits/pixel.
  double _estimateMb() {
    final size = _sizeFor(_shortSide);
    final seconds = _provider.totalDuration.inMilliseconds / 1000.0;
    final videoKbps =
        size.width * size.height * _fps * 0.1 * _quality.sizeFactor / 1000;
    const audioKbps = 128;
    return (videoKbps + audioKbps) * seconds / 8 / 1024;
  }

  // ── Export ──────────────────────────────────────────────────────────────

  Future<void> _start() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = _Stage.exporting;
      _startedAt = DateTime.now();
      _error = null;
    });
    _frameTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) => _updateFrame());

    final provider = _provider;
    try {
      await provider.setOutputSettings(
          resolution: _sizeFor(_shortSide), frameRate: _fps);
      final result = await provider.exportVideo(
        outputPath: widget.outputPath,
        crf: _quality.crf,
        preset: _quality.preset,
      );
      _frameTimer?.cancel();
      if (!mounted) return;
      if (result == null || !File(result).existsSync()) {
        setState(() {
          _stage = _Stage.failed;
          _error = provider.exportError ?? 'Export was cancelled.';
        });
        return;
      }
      HapticFeedback.heavyImpact();
      setState(() {
        _stage = _Stage.done;
        _resultPath = result;
      });
      unawaited(_initResultPlayer(result));
      if (Platform.isAndroid || Platform.isIOS) {
        await _saveToGallery(result);
      }
    } catch (e) {
      _frameTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _saveToGallery(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      // Streams the file to the gallery (no full copy in memory).
      await Gal.putVideo(path, album: 'Studio V');
      if (mounted) {
        setState(() {
          _savedToGallery = true;
          _galleryError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _savedToGallery = false;
          _galleryError = e is GalException ? e.type.message : '$e';
        });
      }
    }
  }

  Future<void> _initResultPlayer(String path) async {
    final c = VideoPlayerController.file(File(path));
    _resultPlayer = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel export?'),
        content: const Text('The video rendered so far will be discarded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel export'),
          ),
        ],
      ),
    );
    if (ok == true) await _provider.cancelExport();
  }

  /// Shows a frame near the part of the timeline being rendered.
  Future<void> _updateFrame() async {
    final provider = _provider;
    final project = provider.currentProject;
    if (project == null || project.videoClips.isEmpty) return;
    final total = provider.totalDuration;
    final progress =
        _stage == _Stage.exporting ? provider.exportProgress.clamp(0.0, 1.0) : 0.3;
    final at = Duration(
        milliseconds: (total.inMilliseconds * progress).round());
    VideoClip? clip;
    for (final c in project.videoClips) {
      if (at >= c.startTime && at < c.endTime) clip = c;
    }
    clip ??= project.videoClips.first;
    if (clip.mediaType == MediaType.image && clip.imageFile != null) {
      if (mounted) setState(() => _frameImage = clip!.imageFile);
      return;
    }
    final path = clip.videoFile?.path;
    if (path == null) return;
    final offset = at - clip.startTime;
    final source = clip.trimStart +
        Duration(
            microseconds:
                (offset.inMicroseconds * clip.playbackSpeed).round());
    // Round to 0.5 s so repeated frames come from the thumbnail cache.
    final ms = (source.inMilliseconds ~/ 500) * 500;
    final bytes = await VideoThumbnailService().getThumbnail(
      videoPath: path,
      timeMs: ms,
      maxHeight: 480,
      quality: 70,
    );
    if (bytes != null && mounted) {
      setState(() {
        _frame = bytes;
        _frameImage = null;
      });
    }
  }

  String _stageLabel(double p) {
    if (p < 0.4) return 'Rendering clips';
    if (p < 0.6) return 'Joining clips & transitions';
    if (p < 0.9) return 'Adding text, stickers & effects';
    if (p < 1.0) return 'Mixing audio';
    return 'Finishing';
  }

  String _eta(double p) {
    final started = _startedAt;
    if (started == null || p < 0.03) return 'Estimating time…';
    final elapsed = DateTime.now().difference(started).inSeconds;
    final remaining = (elapsed / p * (1 - p)).round();
    if (remaining < 60) return 'About ${remaining}s left';
    return 'About ${(remaining / 60).ceil()} min left';
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stage != _Stage.exporting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _stage == _Stage.exporting) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(switch (_stage) {
            _Stage.setup => 'Export video',
            _Stage.exporting => 'Exporting…',
            _Stage.done => 'Ready!',
            _Stage.failed => 'Export failed',
          }),
          leading: IconButton(
            icon: Icon(_stage == _Stage.done
                ? Icons.check_rounded
                : Icons.close_rounded),
            onPressed: () => _stage == _Stage.exporting
                ? _cancel()
                : Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            // Every stage fills the screen (the default layout shrinks to the
            // child, which pushed the progress view to the left edge).
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, if (current != null) current],
            ),
            child: switch (_stage) {
              _Stage.setup => _buildSetup(),
              _Stage.exporting => _buildProgress(),
              _Stage.done => _buildDone(),
              _Stage.failed => _buildFailed(),
            },
          ),
        ),
      ),
    );
  }

  Widget _framePreview({double radius = 18}) {
    Widget child;
    if (_frameImage != null) {
      child = Image.file(_frameImage!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (_frame != null) {
      child = Image.memory(_frame!, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      child = ColoredBox(
        color: AppColors.surfaceLight,
        child: Icon(Icons.movie_rounded, color: AppColors.textTertiary),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: SizedBox.expand(
            key: ValueKey(_frame?.hashCode ?? _frameImage?.path), child: child),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            color: AppColors.primaryLight,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      );

  Widget _chip(String label, bool selected, VoidCallback onTap,
      {String? sub}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.2)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.6 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
            if (sub != null)
              Text(sub,
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildSetup() {
    final size = _sizeFor(_shortSide);
    final mb = _estimateMb();
    final seconds = _provider.totalDuration.inMilliseconds / 1000;
    return ListView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        SizedBox(height: 190, child: _framePreview()),
        const SizedBox(height: 14),
        Row(
          children: [
            _stat(Icons.timer_outlined, '${seconds.toStringAsFixed(1)}s'),
            _stat(Icons.aspect_ratio_rounded,
                '${size.width.toInt()}×${size.height.toInt()}'),
            _stat(Icons.sd_storage_outlined,
                '≈ ${mb < 1 ? '<1' : mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB'),
          ],
        ),
        _sectionTitle('Resolution'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _shortSides)
              _chip(_resLabel(s), s == _shortSide,
                  () => setState(() => _shortSide = s),
                  sub: s >= 1440 ? 'slower' : null),
          ],
        ),
        _sectionTitle('Frame rate'),
        Wrap(
          spacing: 8,
          children: [
            for (final f in _fpsOptions)
              _chip('$f fps', f == _fps, () => setState(() => _fps = f)),
          ],
        ),
        _sectionTitle('Quality'),
        Row(
          children: [
            for (final q in ExportQuality.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      right: q == ExportQuality.values.last ? 0 : 8),
                  child: _chip(q.label, q == _quality,
                      () => setState(() => _quality = q),
                      sub: q.hint),
                ),
              ),
          ],
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.rocket_launch_rounded),
            label: Text(
              Platform.isAndroid || Platform.isIOS
                  ? 'Export & save to Gallery'
                  : 'Export',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The file size is an estimate. Keep Studio V open while exporting.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, String text) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryLight),
              const SizedBox(height: 4),
              Text(text,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5)),
            ],
          ),
        ),
      );

  Widget _buildProgress() {
    return Consumer<VideoEditorProvider>(
      key: const ValueKey('progress'),
      builder: (context, p, _) {
        final progress = p.exportProgress.clamp(0.0, 1.0);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Live frame of the part being rendered, inside the ring.
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: ClipOval(child: _framePreview(radius: 0)),
                    ),
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: progress),
                        duration: const Duration(milliseconds: 400),
                        builder: (context, v, _) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 9,
                          strokeCap: StrokeCap.round,
                          color: AppColors.primary,
                          backgroundColor: AppColors.surfaceLight,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${(progress * 100).floor()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _stageLabel(progress),
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(_eta(progress),
                  style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Cancel export'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDone() {
    final player = _resultPlayer;
    final size = _resultPath == null ? 0 : File(_resultPath!).lengthSync();
    return ListView(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        AspectRatio(
          aspectRatio: player != null && player.value.isInitialized
              ? player.value.aspectRatio
              : 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: player != null && player.value.isInitialized
                ? VideoPlayer(player)
                : _framePreview(),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(
              _savedToGallery == false
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_rounded,
              color: _savedToGallery == false
                  ? AppColors.warning
                  : AppColors.success,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                switch (_savedToGallery) {
                  true => 'Saved to your Gallery (Studio V album)',
                  false => 'Exported, but not saved to the Gallery'
                      '${_galleryError == null ? '' : ': $_galleryError'}',
                  null => Platform.isAndroid || Platform.isIOS
                      ? 'Saving to your Gallery…'
                      : 'Exported to $_resultPath',
                },
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${(size / 1048576).toStringAsFixed(1)} MB · '
          '${_sizeFor(_shortSide).width.toInt()}×${_sizeFor(_shortSide).height.toInt()} · $_fps fps',
          style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 22),
        if (_savedToGallery == false && _resultPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton.icon(
              onPressed: () => _saveToGallery(_resultPath!),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Try saving to Gallery again'),
            ),
          ),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _resultPath == null
                ? null
                : () => SharePlus.instance.share(
                    ShareParams(files: [XFile(_resultPath!)])),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26)),
            ),
            child: const Text('Back to editor'),
          ),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Padding(
      key: const ValueKey('failed'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 64),
          const SizedBox(height: 16),
          Text('The export did not finish',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => setState(() => _stage = _Stage.setup),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
