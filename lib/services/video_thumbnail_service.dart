import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Service for extracting and caching video frame thumbnails for the timeline.
/// Uses a multi-tier cache keyed by (videoPath, timeMs) for instant re-renders.
class VideoThumbnailService {
  // Singleton
  static final VideoThumbnailService _instance = VideoThumbnailService._();
  factory VideoThumbnailService() => _instance;
  VideoThumbnailService._();

  // Cache: "videoPath|timeMs" -> thumbnail bytes
  final Map<String, Uint8List> _cache = {};

  // Track in-flight requests to avoid duplicate extractions
  final Set<String> _inFlight = {};

  // Maximum cache size (entries)
  static const int _maxCacheSize = 500;

  String _cacheKey(String videoPath, int timeMs) => '$videoPath|$timeMs';

  /// Fast single-frame extraction — grabs just the first frame of a video.
  /// Takes ~50-100ms. Used at upload time so the timeline has an instant visual.
  Future<Uint8List?> extractFirstFrame(String videoPath) async {
    // Return cached if available
    final key = _cacheKey(videoPath, 0);
    if (_cache.containsKey(key)) return _cache[key];

    final bytes = await VideoThumbnail.thumbnailData(
      video: videoPath,
      imageFormat: ImageFormat.JPEG,
      timeMs: 0,
      maxHeight: 120,
      quality: 50,
    );

    if (bytes != null) {
      _cache[key] = bytes;
    }
    return bytes;
  }

  /// Get a cached thumbnail, or null if not yet extracted.
  Uint8List? getCached(String videoPath, int timeMs) {
    return _cache[_cacheKey(videoPath, timeMs)];
  }

  /// Extract a single thumbnail asynchronously. Returns cached if available.
  /// [maxHeight] controls quality vs performance tradeoff.
  Future<Uint8List?> getThumbnail({
    required String videoPath,
    required int timeMs,
    int maxHeight = 60,
    int quality = 40,
  }) async {
    final key = _cacheKey(videoPath, timeMs);

    // Return cached
    if (_cache.containsKey(key)) return _cache[key];

    // Skip if already extracting
    if (_inFlight.contains(key)) return null;

    _inFlight.add(key);
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        timeMs: timeMs,
        maxHeight: maxHeight,
        quality: quality,
      );

      if (bytes != null) {
        // Evict oldest entries if cache is full
        if (_cache.length >= _maxCacheSize) {
          final keysToRemove = _cache.keys.take(_cache.length - _maxCacheSize + 50).toList();
          for (final k in keysToRemove) {
            _cache.remove(k);
          }
        }
        _cache[key] = bytes;
      }

      return bytes;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }

  /// Generate thumbnails for a clip across its duration.
  /// Returns the number of frames per second based on available width.
  /// [intervalMs] controls the spacing between frames.
  Future<void> preloadThumbnails({
    required String videoPath,
    required int startMs,
    required int endMs,
    required int intervalMs,
    int maxHeight = 60,
    int quality = 40,
  }) async {
    final times = <int>[];
    for (int t = startMs; t < endMs; t += intervalMs) {
      if (!_cache.containsKey(_cacheKey(videoPath, t))) {
        times.add(t);
      }
    }

    // Extract in batches of 4 for performance
    for (int i = 0; i < times.length; i += 4) {
      final batch = times.skip(i).take(4);
      await Future.wait(batch.map((t) => getThumbnail(
            videoPath: videoPath,
            timeMs: t,
            maxHeight: maxHeight,
            quality: quality,
          )));
    }
  }

  // ─── Pre-generation API (for upload-time frame generation) ────

  // Track video paths that are fully pre-generated
  final Set<String> _fullyPreGenerated = {};

  /// Returns true if all frames for this video's range are already cached.
  bool isFullyCached({
    required String videoPath,
    required int startMs,
    required int endMs,
    int intervalMs = 1000,
  }) {
    if (_fullyPreGenerated.contains(videoPath)) return true;
    for (int t = startMs; t < endMs; t += intervalMs) {
      if (!_cache.containsKey(_cacheKey(videoPath, t))) return false;
    }
    _fullyPreGenerated.add(videoPath);
    return true;
  }

  /// Pre-generates **all** frames for a video in parallel batches.
  ///
  /// Call this right after a video is added to the project, before calling
  /// notifyListeners(). The timeline will then render fully-populated
  /// on its first build — no progressive one-by-one appearance.
  ///
  /// [batchSize] controls how many frames are extracted concurrently.
  /// 6 is a good default: fast enough without flooding the device decoder.
  Future<void> preGenerateAllFrames({
    required String videoPath,
    required int durationMs,
    int startMs = 0,
    int intervalMs = 1000,
    int maxHeight = 120,
    int quality = 50,
    int batchSize = 6,
  }) async {
    // Already fully cached — skip all work
    if (_fullyPreGenerated.contains(videoPath)) return;

    // Build the list of timestamps we still need
    final times = <int>[];
    for (int t = startMs; t < durationMs; t += intervalMs) {
      if (!_cache.containsKey(_cacheKey(videoPath, t))) {
        times.add(t);
      }
    }

    if (times.isEmpty) {
      _fullyPreGenerated.add(videoPath);
      return;
    }

    // Extract in parallel batches of [batchSize]
    for (int i = 0; i < times.length; i += batchSize) {
      final batch = times.skip(i).take(batchSize);
      await Future.wait(
        batch.map((t) => getThumbnail(
              videoPath: videoPath,
              timeMs: t,
              maxHeight: maxHeight,
              quality: quality,
            )),
        eagerError: false, // Don't abort the whole batch on one failure
      );
    }

    _fullyPreGenerated.add(videoPath);
  }

  /// Mark a video path as fully pre-generated (used when frames come from another source)
  void markFullyGenerated(String videoPath) {
    _fullyPreGenerated.add(videoPath);
  }

  /// Whether a video path has had all frames pre-generated
  bool isPreGenerated(String videoPath) => _fullyPreGenerated.contains(videoPath);

  /// Clear all cached thumbnails
  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Clear cached thumbnails for a specific video
  void clearCacheForVideo(String videoPath) {
    _cache.removeWhere((key, _) => key.startsWith('$videoPath|'));
  }

  /// Number of cached entries
  int get cacheSize => _cache.length;

  /// Get all cached thumbnails for a video file within a time range.
  /// Returns frames at [intervalMs] spacing between [startMs] and [endMs].
  /// Returns only frames that are already cached — does NOT trigger extraction.
  List<Uint8List> getFramesForRange({
    required String videoPath,
    required int startMs,
    required int endMs,
    int intervalMs = 1000,
  }) {
    final frames = <Uint8List>[];
    for (int t = startMs; t < endMs; t += intervalMs) {
      final cached = getCached(videoPath, t);
      if (cached != null) {
        frames.add(cached);
      }
    }
    return frames;
  }

  /// Count how many frames are cached for a video file within a time range.
  int getCachedFrameCount({
    required String videoPath,
    required int startMs,
    required int endMs,
    int intervalMs = 1000,
  }) {
    int count = 0;
    for (int t = startMs; t < endMs; t += intervalMs) {
      if (_cache.containsKey(_cacheKey(videoPath, t))) {
        count++;
      }
    }
    return count;
  }

  /// Check if extraction is in-flight for any frame of a video in a range.
  bool isLoadingRange({
    required String videoPath,
    required int startMs,
    required int endMs,
    int intervalMs = 1000,
  }) {
    for (int t = startMs; t < endMs; t += intervalMs) {
      if (_inFlight.contains(_cacheKey(videoPath, t))) {
        return true;
      }
    }
    return false;
  }
}
