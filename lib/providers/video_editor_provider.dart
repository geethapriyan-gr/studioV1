import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import '../models/video_project.dart';
import '../models/chroma_key_settings.dart';
import '../models/editor_panel_mode.dart';
import '../models/transition.dart';
import '../models/video_effect.dart';
import '../models/filter_presets.dart';
import '../services/export_service.dart';
import '../services/chroma_key_service.dart';
import '../services/waveform_service.dart';
import '../services/hive_service.dart';
import '../services/video_thumbnail_service.dart';
import '../utils/track_allocation.dart';

class VideoEditorProvider extends ChangeNotifier {
  VideoProject? _currentProject;
  VideoEditorController? _videoController;
  VideoPlayerController? _previewController;

  // LRU Cache for memory management
  final Map<String, VideoPlayerController> _previewControllers = {};
  final List<String> _lruAccessList = [];
  static const int _maxControllers =
      3; // Keep max 3 videos in memory to prevent crashes

  String? _activeFilePath;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  bool _isLoading = false;
  String? _loadingMessage;

  Timer? _timelineTimer;
  DateTime? _playbackStartTime;
  Duration? _playbackStartPosition;

  String? _activeTransitionId;
  DateTime _lastTransitionSeek = DateTime.fromMillisecondsSinceEpoch(0);
  bool _transitionOpInFlight = false;
  final Set<String> _transitionPrewarmInFlight = {};

  // ── Pre-rendered transition previews ────────────────────────────────────
  // Each transition is rendered once with FFmpeg (the exporter's own filters)
  // into a short clip. The preview plays that clip during the transition
  // window instead of compositing it live, so it looks exactly like the
  // export and never has to decode two full-resolution files at once.
  final Map<String, String> _transitionRenderFiles = {}; // signature -> file
  final Set<String> _failedTransitionRenders = {};
  final List<String> _transitionRenderQueue = []; // transition ids
  String? _transitionRenderingSignature;
  double _transitionRenderProgress = 0.0;
  DateTime _lastRenderProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _transitionRenderDebounce;
  int _transitionRenderGeneration = 0;

  VideoPlayerController? _transitionClipController;
  String? _transitionClipPath;
  Future<void>? _transitionClipLoad;
  String? _renderedTransitionShownId;
  bool _renderedTransitionEnterInFlight = false;

  bool _audioSyncInProgress = false;
  DateTime _lastAudioSync = DateTime.fromMillisecondsSinceEpoch(0);
  // Audio sync interval - reduced back to 80ms for smoother audio
  static const int _audioSyncIntervalMs = 80;
  bool _pendingForcedAudioSync = false;

  Timer? _autoSaveTimer;
  bool _isAutoSaving = false;
  DateTime? _lastAutoSaved;
  Timer? _seekPauseTimer;
  bool _timelinePausedForBackground = false;
  String? _activePreviewClipId;
  bool _previewSyncInFlight = false;
  int _seekSyncSerial = 0;
  Timer? _deferredSeekSyncTimer;
  bool _playbackRecoveryInFlight = false;
  int _playbackRecoverySerial = 0;

  static const int _maxPlaybackSyncAttempts = 4;
  static const Duration _playbackSyncRetryDelay = Duration(milliseconds: 120);
  static const Duration _videoDriftTolerance = Duration(milliseconds: 350);

  /// How early the incoming clip's controller of a transition is initialized
  /// and parked on its first frame. High-resolution files need well over a
  /// second to open a decoder, so this has to lead the transition generously.
  static const Duration _transitionControllerPrewarmLead =
      Duration(milliseconds: 3000);

  final List<VideoProject> _undoStack = [];
  final List<VideoProject> _redoStack = [];
  static const int _maxHistory = 50;

  bool _isExporting = false;
  bool _isReversing = false;
  double _exportProgress = 0.0;
  String? _exportError;

  bool _showTimeline = true;
  bool _showFilters = false;
  bool _showTextEditor = false;
  bool _showAudioEditor = false;
  bool _showCropEditor = false;
  bool _showRotateEditor = false;
  bool _showTrimEditor = false;

  // Editor panel mode enum - replaces multiple showX booleans
  EditorPanelMode _editorPanelMode = EditorPanelMode.none;

  // Chroma key state - current clip's chroma key settings being edited
  ChromaKeySettings? _currentChromaKeySettings;

  /// Get the current editor panel mode
  EditorPanelMode get editorPanelMode => _editorPanelMode;

  /// Get current chroma key settings for the selected clip
  ChromaKeySettings? get currentChromaKeySettings => _currentChromaKeySettings;

  /// Check if chroma key is enabled for current clip
  bool get isChromaKeyEnabled {
    if (_currentProject == null || _selectedVideoClipId == null) return false;
    try {
      final clip = _currentProject!.videoClips.firstWhere(
        (c) => c.id == _selectedVideoClipId,
      );
      return clip.chromaKeySettings?.enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  // Trim mode: 'left', 'right', or 'both'
  String _trimMode = 'both';

  String? _selectedTextOverlayId;

  String? _selectedAudioOverlayId;
  String? _selectedVideoClipId;
  String? _selectedOverlayClipId;
  String? _selectedStickerId;
  int? _selectedAudioTrackIndex;

  int? get selectedAudioTrackIndex => _selectedAudioTrackIndex;

  void selectAudioTrack(int trackIndex) {
    _selectedAudioTrackIndex = trackIndex;
    notifyListeners();
  }

  // Preview text overlay for live typing preview
  TextOverlay? _previewTextOverlay;

  double _videoMasterVolume = 1.0;
  double _audioMasterVolume = 1.0;

  final Uuid _uuid = const Uuid();
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, double> _lastSetOverlayVolume = {};
  final Map<String, List<double>> _waveformCache = {};
  final Map<String, String> _audioSourceConfigCache = {};

  Future<void> _configureAudioPlayerSource(
      AudioPlayer player, AudioOverlay overlay) async {
    final clipStart = overlay.audioStartOffset;
    final clipDuration = overlay.endTime - overlay.startTime;
    final clipEnd = clipStart +
        (clipDuration < Duration.zero ? Duration.zero : clipDuration);
    final cacheKey =
        '${overlay.audioFile.path}|${clipStart.inMilliseconds}|${clipEnd.inMilliseconds}';

    if (_audioSourceConfigCache[overlay.id] == cacheKey) {
      return;
    }

    try {
      final clippingSource = ClippingAudioSource(
        child: AudioSource.file(overlay.audioFile.path),
        start: clipStart,
        end: clipEnd,
      );
      await player.setAudioSource(clippingSource);
      _audioSourceConfigCache[overlay.id] = cacheKey;
    } catch (e) {
      debugPrint('Error setting clipping audio source for ${overlay.id}: $e');
    }
  }

  // Per-clip color filters: key is clipId, value is the filter for that clip
  final Map<String, ColorFilter> _clipColorFilters = {};

  /// Get the per-clip color filter map (read-only access)
  Map<String, ColorFilter> get clipColorFilters =>
      Map.unmodifiable(_clipColorFilters);

  // Track management for multiple overlay and audio tracks
  int get overlayTrackCount {
    if (_currentProject == null || _currentProject!.overlayClips.isEmpty) {
      return 1;
    }
    return computeTrackAllocation<VideoClip>(
      items: _currentProject!.overlayClips,
      getId: (c) => c.id,
      getStartTime: (c) => c.startTime,
      getEndTime: (c) => c.endTime,
    ).trackCount;
  }

  int get audioTrackCount {
    if (_currentProject == null || _currentProject!.audioOverlays.isEmpty) {
      return 1;
    }
    return computeTrackAllocation<AudioOverlay>(
      items: _currentProject!.audioOverlays,
      getId: (a) => a.id,
      getStartTime: (a) => a.startTime,
      getEndTime: (a) => a.endTime,
    ).trackCount;
  }

  int get textTrackCount {
    if (_currentProject == null || _currentProject!.textOverlays.isEmpty) {
      return 1;
    }
    return computeTrackAllocation<TextOverlay>(
      items: _currentProject!.textOverlays,
      getId: (t) => t.id,
      getStartTime: (t) => t.startTime,
      getEndTime: (t) => t.endTime,
    ).trackCount;
  }

  int get stickerTrackCount {
    if (_currentProject == null || _currentProject!.stickers.isEmpty) {
      return 1;
    }
    return computeTrackAllocation<StickerModel>(
      items: _currentProject!.stickers,
      getId: (s) => s.id,
      getStartTime: (s) => s.startTime,
      getEndTime: (s) => s.endTime,
    ).trackCount;
  }

  void _updateTrackCountsFromProject() {}

  void addOverlayTrack() {}

  void addAudioTrack() {}

  VideoProject? get currentProject => _currentProject;
  VideoEditorController? get videoController => _videoController;
  VideoPlayerController? get previewController => _previewController;
  String? get activeFilePath => _activeFilePath;

  /// Id of the clip the active preview controller has been synced to.
  String? get activePreviewClipId => _activePreviewClipId;

  /// True while transition previews are being rendered in the background.
  bool get isRenderingTransitions =>
      _transitionRenderingSignature != null || _transitionRenderQueue.isNotEmpty;

  /// Progress (0..1) of the transition currently being rendered.
  double get transitionRenderProgress => _transitionRenderProgress;

  /// Transitions still waiting to be rendered, including the current one.
  int get transitionRendersPending =>
      _transitionRenderQueue.length +
      (_transitionRenderingSignature != null ? 1 : 0);

  /// True when [transitionId] has an up-to-date pre-rendered clip.
  bool hasRenderedTransition(String transitionId) {
    for (final t in _currentProject?.transitions ?? const <Transition>[]) {
      if (t.id == transitionId) return _renderedFileFor(t) != null;
    }
    return false;
  }

  /// The player showing the pre-rendered clip of [transitionId], when that
  /// clip is what the preview should display right now.
  VideoPlayerController? renderedTransitionControllerFor(String transitionId) {
    final controller = _transitionClipController;
    if (_renderedTransitionShownId != transitionId ||
        controller == null ||
        !controller.value.isInitialized) {
      return null;
    }
    return controller;
  }

  /// Timeline position extrapolated from the playback clock right now.
  /// [currentPosition] only advances on the ~33 ms timeline timer; this is
  /// smooth enough to drive per-frame animations such as transition previews.
  Duration get smoothPosition {
    final start = _playbackStartTime;
    final startPosition = _playbackStartPosition;
    if (!_isPlaying ||
        _timelineTimer == null ||
        start == null ||
        startPosition == null) {
      return _currentPosition;
    }
    final position = startPosition + DateTime.now().difference(start);
    if (position < _currentPosition) return _currentPosition;
    final max = totalDuration;
    return position > max ? max : position;
  }

  /// While the user drags the timeline during playback, playback is
  /// suspended internally but still reported as "playing" so the UI does not
  /// flicker; it resumes from the new position when the drag ends.
  bool get isPlaying => _isPlaying || _resumePlaybackAfterScrub;
  bool get isScrubbing => _isScrubbing;

  bool _isScrubbing = false;
  bool _resumePlaybackAfterScrub = false;

  /// Called when the user starts dragging the timeline.
  ///
  /// Playing video while seeking it dozens of times per second is what made
  /// the preview freeze and buffer: every scroll event re-seeked a running
  /// decoder. Instead, pause once, show frames while scrubbing, and resume
  /// once from the final position.
  Future<void> beginScrub() async {
    if (_isScrubbing) return;
    _isScrubbing = true;
    if (_isPlaying) {
      _resumePlaybackAfterScrub = true;
      _seekSyncSerial++;
      _playbackRecoverySerial++;
      _playbackRecoveryInFlight = false;
      _seekPauseTimer?.cancel();
      _deferredSeekSyncTimer?.cancel();
      _isPlaying = false;
      _stopTimelineClock();
      _activePreviewClipId = null;
      _activeTransitionId = null;
      await _pauseAllPreviewControllers(mute: false);
      await _pauseAllAudioPlayers();
    }
  }

  /// Called when the timeline drag (including its fling) has settled.
  Future<void> endScrub() async {
    if (!_isScrubbing) return;
    _isScrubbing = false;
    if (_resumePlaybackAfterScrub) {
      _resumePlaybackAfterScrub = false;
      if (!_isPlaying) {
        await togglePlayback();
      }
    }
  }
  Duration get currentPosition => _currentPosition;
  bool get isLoading => _isLoading;
  String? get loadingMessage => _loadingMessage;

  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;
  String? get exportError => _exportError;
  bool get isReversing => _isReversing;
  bool get isAutoSaving => _isAutoSaving;
  DateTime? get lastAutoSaved => _lastAutoSaved;

  bool get showTimeline => _showTimeline;
  bool get showFilters => _showFilters;
  bool get showTextEditor => _showTextEditor;
  bool get showAudioEditor => _showAudioEditor;
  bool get showCropEditor => _showCropEditor;
  bool get showRotateEditor => _showRotateEditor;
  bool _showStickerPanel = false;

  bool get showStickerPanel => _showStickerPanel;
  bool get showTrimEditor => _showTrimEditor;
  String get trimMode => _trimMode;

  String? get selectedTextOverlayId => _selectedTextOverlayId;
  String? get selectedAudioOverlayId => _selectedAudioOverlayId;
  String? get selectedVideoClipId => _selectedVideoClipId;
  String? get selectedOverlayClipId => _selectedOverlayClipId;
  String? get selectedStickerId => _selectedStickerId;

  /// Returns true if any component (video, overlay, text, audio, sticker) is currently selected on the timeline
  bool get hasTimelineSelection =>
      _selectedVideoClipId != null ||
      _selectedAudioOverlayId != null ||
      _selectedStickerId != null ||
      _selectedTextOverlayId != null ||
      _selectedOverlayClipId != null;

  List<StickerModel> get currentStickers {
    if (_currentProject == null) return [];
    return _currentProject!.getStickersAtTime(_currentPosition);
  }

  double get videoMasterVolume => _videoMasterVolume;
  double get audioMasterVolume => _audioMasterVolume;

  TextOverlay? get previewTextOverlay => _previewTextOverlay;

  void setTextPreview(
    String text,
    double fontSize,
    Color color, {
    String fontFamily = 'Roboto',
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    TextAlign textAlign = TextAlign.center,
  }) {
    if (text.isEmpty) {
      _previewTextOverlay = null;
    } else {
      // Convert Flutter types to our enum types
      final fontStyleEnum = fontStyle == FontStyle.italic
          ? FontStyleEnum.italic
          : FontStyleEnum.normal;
      TextAlignEnum textAlignEnum;

      switch (textAlign) {
        case TextAlign.left:
          textAlignEnum = TextAlignEnum.left;
          break;
        case TextAlign.center:
          textAlignEnum = TextAlignEnum.center;
          break;
        case TextAlign.right:
          textAlignEnum = TextAlignEnum.right;
          break;
        case TextAlign.justify:
          textAlignEnum = TextAlignEnum.justify;
          break;
        case TextAlign.start:
          textAlignEnum = TextAlignEnum.start;
          break;
        case TextAlign.end:
          textAlignEnum = TextAlignEnum.end;
          break;
        default:
          textAlignEnum = TextAlignEnum.center;
      }

      _previewTextOverlay = TextOverlay(
        id: 'preview',
        text: text,
        position: const Offset(0.5, 0.5),
        startTime: Duration.zero,
        endTime: const Duration(seconds: 1),
        fontSize: fontSize,
        color: color,
        fontFamily: fontFamily,
        fontWeight: fontWeight,
        fontStyle: fontStyleEnum,
        textAlign: textAlignEnum,
      );
    }
    notifyListeners();
  }

  void clearTextPreview() {
    _previewTextOverlay = null;
    notifyListeners();
  }

  // --- MEMORY & FILE SAFETY METHODS ---

  Future<File> _importFileToAppDocs(File sourceFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = p.basename(sourceFile.path);
    final uniqueName = '${_uuid.v4()}_$fileName';
    final newPath = p.join(appDir.path, uniqueName);
    final newFile = await sourceFile.copy(newPath);
    return newFile;
  }

  Future<void> _healProjectPaths(VideoProject project) async {
    final appDir = await getApplicationDocumentsDirectory();
    final fixedClips = <VideoClip>[];

    for (final clip in project.videoClips) {
      File? video = clip.videoFile;
      File? image = clip.imageFile;

      if (video != null && !video.existsSync()) {
        final filename = p.basename(video.path);
        final potentialPath = p.join(appDir.path, filename);
        // Try exact match in new sandbox container
        if (File(potentialPath).existsSync()) {
          video = File(potentialPath);
        } else {
          // If UUID prefix makes it hard to find, we might need more logic,
          // but usually the filename persists if we copied it there.
          // For now, if we can't find it, we keep the old path and let it fail gracefully or user re-imports.
        }
      }

      if (image != null && !image.existsSync()) {
        final filename = p.basename(image.path);
        final potentialPath = p.join(appDir.path, filename);
        if (File(potentialPath).existsSync()) {
          image = File(potentialPath);
        }
      }

      fixedClips.add(clip.copyWith(videoFile: video, imageFile: image));
    }

    final fixedAudio = <AudioOverlay>[];
    for (final overlay in project.audioOverlays) {
      File audio = overlay.audioFile;
      if (!audio.existsSync()) {
        final filename = p.basename(audio.path);
        final potentialPath = p.join(appDir.path, filename);
        if (File(potentialPath).existsSync()) {
          audio = File(potentialPath);
        }
      }
      fixedAudio.add(overlay.copyWith(audioFile: audio));
    }

    _currentProject = project.copyWith(
      videoClips: fixedClips,
      audioOverlays: fixedAudio,
    );
  }

  Future<void> _manageControllerMemory(String newPath) async {
    if (_previewControllers.containsKey(newPath)) {
      _lruAccessList.remove(newPath);
      _lruAccessList.add(newPath);
      return;
    }

    if (_lruAccessList.length >= _maxControllers) {
      final oldestPath = _lruAccessList.removeAt(0);
      final controller = _previewControllers.remove(oldestPath);

      if (_activeFilePath == oldestPath && controller != null) {
        if (_lruAccessList.isNotEmpty) {
          _previewControllers[oldestPath] = controller;
          _lruAccessList.add(oldestPath);

          final secondOldest = _lruAccessList.removeAt(0);
          final c2 = _previewControllers.remove(secondOldest);
          await c2?.dispose();
        }
      } else {
        await controller?.dispose();
      }
    }
    _lruAccessList.add(newPath);
  }

  // --- CORE LOGIC ---

  Future<void> setVideoMasterVolume(double v) async {
    final newVal = v.clamp(0.0, 1.0);
    if (_videoMasterVolume == newVal) return;
    recordUndo();
    _videoMasterVolume = newVal;
    await _applyPreviewVolumeForCurrentPosition();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> setProjectName(String name) async {
    if (_currentProject == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || _currentProject!.name == trimmed) return;
    recordUndo();
    _currentProject =
        _currentProject!.copyWith(name: trimmed, lastModified: DateTime.now());
    await _autoSaveProject();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> setAudioMasterVolume(double v) async {
    final newVal = v.clamp(0.0, 1.0);
    if (_audioMasterVolume == newVal) return;
    recordUndo();
    _audioMasterVolume = newVal;
    if (_currentProject != null) {
      for (final overlay in _currentProject!.audioOverlays) {
        final p = _audioPlayers[overlay.id];
        if (p != null) {
          await p
              .setVolume((overlay.volume * _audioMasterVolume).clamp(0.0, 1.0));
        }
      }
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Duration get totalDuration {
    if (_currentProject == null) {
      return Duration.zero;
    }
    final clipsDuration = _currentProject!.videoClips.isEmpty
        ? Duration.zero
        : _currentProject!.calculateTotalDuration();

    Duration overlaysDuration = Duration.zero;
    for (final a in _currentProject!.audioOverlays) {
      if (a.endTime > overlaysDuration) overlaysDuration = a.endTime;
    }

    // Also check text overlays end time
    Duration textOverlaysDuration = Duration.zero;
    for (final t in _currentProject!.textOverlays) {
      if (t.endTime > textOverlaysDuration) textOverlaysDuration = t.endTime;
    }

    // Return the maximum of all content durations
    final maxDuration = [clipsDuration, overlaysDuration, textOverlaysDuration]
        .reduce((a, b) => a > b ? a : b);
    return maxDuration;
  }

  /// Returns the duration of video clips only (excluding overlays).
  /// This is used to constrain overlay positions within video bounds.
  Duration get videoClipsDuration {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) {
      return Duration.zero;
    }
    return _currentProject!.calculateTotalDuration();
  }

  Future<void> _switchActivePreviewController(String filePath) async {
    if (_activeFilePath == filePath && _previewController != null) return;

    unawaited(_manageControllerMemory(filePath));

    if (!_previewControllers.containsKey(filePath)) {
      final controller = VideoPlayerController.file(
        File(filePath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setVolume(0.0);
      _previewControllers[filePath] = controller;
    }

    final old = _previewController;
    old?.removeListener(_videoPositionListener);
    if (old != null && old.value.isInitialized) {
      await old.pause();
      await old.setVolume(0.0);
    }

    _previewController = _previewControllers[filePath];
    _activeFilePath = filePath;
    _previewController?.addListener(_videoPositionListener);
    notifyListeners();
  }

  /// Ensure a preview controller exists for [filePath] without switching the
  /// active preview controller. This is used for transition previews where
  /// two clips must be visible at once.
  Future<VideoPlayerController?> ensurePreviewController(
      String filePath) async {
    if (!_previewControllers.containsKey(filePath)) {
      // Evict before registering the new controller: once it is in the map
      // the LRU treats it as known and nothing is ever released, which leaves
      // one hardware decoder per clip alive (fatal with 4K footage).
      await _manageControllerMemory(filePath);
      final controller = VideoPlayerController.file(
        File(filePath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setVolume(0.0);
      final existing = _previewControllers[filePath];
      if (existing != null) {
        // Another caller created it while we were initializing.
        await controller.dispose();
        return existing;
      }
      _previewControllers[filePath] = controller;
    }
    return _previewControllers[filePath];
  }

  Future<void> _pauseAllPreviewControllers({bool mute = true}) async {
    final controllers = <VideoPlayerController>{
      if (_previewController != null) _previewController!,
      ..._previewControllers.values,
      if (_transitionClipController != null) _transitionClipController!,
    };

    for (final controller in controllers) {
      if (!controller.value.isInitialized) continue;
      await controller.pause().timeout(
            const Duration(milliseconds: 800),
            onTimeout: () {},
          );
      if (mute) {
        await controller.setVolume(0.0).timeout(
              const Duration(milliseconds: 800),
              onTimeout: () {},
            );
      }
    }
  }

  Future<void> moveAudioOverlay(String overlayId, Duration newStartTime,
      {int? trackIndex}) async {
    if (_currentProject == null) return;
    final index =
        _currentProject!.audioOverlays.indexWhere((o) => o.id == overlayId);
    if (index == -1) return;
    final overlay = _currentProject!.audioOverlays[index];
    final duration = overlay.endTime - overlay.startTime;

    // Only clamp start time to not be negative
    // Audio overlays CAN extend beyond video duration
    Duration clampedStart = newStartTime;
    if (clampedStart < Duration.zero) clampedStart = Duration.zero;

    // Check if there's already a clip in the target track at the same time range
    int finalTrackIndex = trackIndex ?? overlay.trackIndex;
    bool hasOverlap = _currentProject!.audioOverlays
        .where((audio) =>
            audio.id != overlayId && audio.trackIndex == finalTrackIndex)
        .any((audio) => _audioOverlaps(audio, clampedStart, duration));

    // If there's an overlap, create a new track
    if (hasOverlap) {
      finalTrackIndex = _findAvailableAudioTrackIndex();
    }

    final updated = overlay.copyWith(
      startTime: clampedStart,
      endTime: clampedStart + duration,
      trackIndex: finalTrackIndex,
    );
    recordUndo();
    _currentProject = _currentProject!.updateAudioOverlay(overlayId, updated);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Check if two audio overlays overlap in time
  bool _audioOverlaps(
      AudioOverlay existingAudio, Duration newStart, Duration newDuration) {
    final newEnd = newStart + newDuration;
    return !(newEnd <= existingAudio.startTime ||
        newStart >= existingAudio.endTime);
  }

  /// Find the next available audio track index
  int _findAvailableAudioTrackIndex() {
    if (_currentProject == null || _currentProject!.audioOverlays.isEmpty) {
      return 0;
    }

    // Find the highest track index currently used
    int maxTrackIndex = _currentProject!.audioOverlays
        .map((audio) => audio.trackIndex)
        .reduce((a, b) => a > b ? a : b);

    return maxTrackIndex + 1;
  }

  Duration get projectDuration =>
      _currentProject?.calculateTotalDuration() ?? Duration.zero;
  Duration get videoDuration =>
      _previewController?.value.duration ?? Duration.zero;

  void cutVideoClip(String clipId) {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    final originalClip = _currentProject!.videoClips[clipIndex];
    final cutPosition = _currentPosition;
    if (cutPosition <= originalClip.startTime ||
        cutPosition >= originalClip.endTime) {
      return;
    }
    final firstDuration = cutPosition - originalClip.startTime;
    // Split point inside the source window that is actually played/exported
    // (trimStart-based, speed-aware) so both halves show the same frames in
    // preview and export as the original clip did.
    final firstSourceEnd = originalClip.trimStart +
        sourceLengthForTimeline(firstDuration, originalClip.playbackSpeed);
    final firstClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: originalClip.startTime,
      endTime: cutPosition,
      sourceStart: originalClip.sourceStart,
      sourceEnd: firstSourceEnd,
      trimStart: originalClip.trimStart,
      trimEnd: firstSourceEnd,
    );
    final secondClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: cutPosition,
      endTime: originalClip.endTime,
      sourceStart: firstSourceEnd,
      sourceEnd: originalClip.sourceEnd,
      trimStart: firstSourceEnd,
      trimEnd: originalClip.trimEnd,
    );
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips.removeAt(clipIndex);
    updatedClips.insert(clipIndex, firstClip);
    updatedClips.insert(clipIndex + 1, secondClip);
    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Extend (or shrink) an **image** clip's duration by updating sourceEnd.
  ///
  /// Unlike videos, image clips have no inherent length so sourceEnd can grow
  /// to any positive value.  Call this from the right-trim handle instead of
  /// [trimVideoClip] for image-type clips.
  void extendImageClipDuration(String clipId, Duration newTrimEnd) {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];
    if (originalClip.mediaType != MediaType.image) return;

    // Minimum 100 ms duration
    if (newTrimEnd <=
        originalClip.trimStart + const Duration(milliseconds: 100)) {
      return;
    }

    // Timeline lengths (window / speed) — same formula as the exporter.
    final oldDuration = originalClip.endTime - originalClip.startTime;
    final newDuration = timelineLengthForSource(
        newTrimEnd - originalClip.trimStart, originalClip.playbackSpeed);
    final durationDiff = newDuration - oldDuration;

    final updatedClip = originalClip.copyWith(
      trimEnd: newTrimEnd,
      sourceEnd: newTrimEnd,
      endTime: originalClip.startTime + newDuration,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    // Shift all subsequent clips by the duration change
    for (int i = clipIndex + 1; i < updatedClips.length; i++) {
      final c = updatedClips[i];
      updatedClips[i] = c.copyWith(
        startTime: c.startTime + durationDiff,
        endTime: c.endTime + durationDiff,
      );
    }

    _currentProject = _currentProject!.copyWith(
      videoClips: updatedClips,
      totalDuration: _currentProject!.calculateTotalDuration(),
    );
    // No recordUndo during drag — only on drag end
    notifyListeners();
  }

  Future<void> trimVideoClip(
      String clipId, Duration startTrim, Duration endTrim) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    // For image clips, delegate to extendImageClipDuration for right-trim
    if (originalClip.mediaType == MediaType.image &&
        startTrim == originalClip.trimStart &&
        endTrim != originalClip.trimEnd) {
      extendImageClipDuration(clipId, endTrim);
      return;
    }

    // Strictly enforce trim boundaries to not exceed source boundaries
    if (startTrim < originalClip.sourceStart ||
        startTrim >=
            originalClip.sourceEnd - const Duration(milliseconds: 100) ||
        endTrim <=
            originalClip.sourceStart + const Duration(milliseconds: 100) ||
        endTrim > originalClip.sourceEnd) {
      return;
    }

    if (startTrim >= endTrim) {
      return;
    }

    // Timeline lengths (source window / speed) — same formula as the exporter.
    final oldDuration = originalClip.endTime - originalClip.startTime;
    final newDuration =
        timelineLengthForSource(endTrim - startTrim, originalClip.playbackSpeed);

    final updatedClip = originalClip.copyWith(
      trimStart: startTrim,
      trimEnd: endTrim,
      endTime: originalClip.startTime + newDuration,
    );

    final durationDiff = newDuration - oldDuration;
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    for (int i = clipIndex + 1; i < updatedClips.length; i++) {
      final c = updatedClips[i];
      updatedClips[i] = c.copyWith(
        startTime: c.startTime + durationDiff,
        endTime: c.endTime + durationDiff,
      );
    }

    // recordUndo() is called by the drag-end handler in the UI, not here,
    // so we don't duplicate an undo entry for every drag frame.
    _currentProject = _currentProject!.copyWith(
      videoClips: updatedClips,
      totalDuration: _currentProject!.calculateTotalDuration(),
    );

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Trim a clip that lives in the overlay track.  This behaves nearly
  /// identically to [trimVideoClip] but updates the overlayClips list and
  /// adjusts subsequent overlays so that timing remains contiguous.
  Future<void> trimOverlayClip(
      String clipId, Duration startTrim, Duration endTrim) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.overlayClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final isImage = originalClip.mediaType == MediaType.image || originalClip.imageFile != null;

    VideoClip updatedClip;

    if (startTrim != originalClip.trimStart) {
      // Left-edge drag
      final delta = startTrim - originalClip.trimStart;
      final newStartTime = originalClip.startTime + delta;

      if (isImage) {
        if (newStartTime < Duration.zero || newStartTime >= originalClip.endTime - const Duration(milliseconds: 100)) {
          return;
        }
        final newDuration = originalClip.endTime - newStartTime;
        updatedClip = originalClip.copyWith(
          startTime: newStartTime,
          endTime: originalClip.endTime,
          trimStart: Duration.zero,
          trimEnd: newDuration,
          sourceEnd: newDuration,
        );
      } else {
        // Video overlay
        if (startTrim < originalClip.sourceStart ||
            startTrim >= originalClip.trimEnd - const Duration(milliseconds: 100)) {
          return;
        }
        final newDuration = originalClip.trimEnd - startTrim;
        updatedClip = originalClip.copyWith(
          startTime: newStartTime,
          trimStart: startTrim,
          endTime: newStartTime + newDuration,
        );
      }
    } else if (endTrim != originalClip.trimEnd) {
      // Right-edge drag
      if (isImage) {
        final delta = endTrim - originalClip.trimEnd;
        final newEndTime = originalClip.endTime + delta;
        if (newEndTime <= originalClip.startTime + const Duration(milliseconds: 100)) {
          return;
        }
        final newDuration = newEndTime - originalClip.startTime;
        updatedClip = originalClip.copyWith(
          startTime: originalClip.startTime,
          endTime: newEndTime,
          trimStart: Duration.zero,
          trimEnd: newDuration,
          sourceEnd: newDuration,
        );
      } else {
        // Video overlay
        if (endTrim <= originalClip.trimStart + const Duration(milliseconds: 100) ||
            endTrim > originalClip.sourceEnd) {
          return;
        }
        final newDuration = endTrim - originalClip.trimStart;
        updatedClip = originalClip.copyWith(
          trimEnd: endTrim,
          endTime: originalClip.startTime + newDuration,
        );
      }
    } else {
      return;
    }

    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);

    _scheduleAutoSave();
    notifyListeners();
  }

  void reorderVideoClip(String clipId, Duration dropTime) {
    if (_currentProject == null) return;
    final clips = List<VideoClip>.from(_currentProject!.videoClips);
    final currentIndex = clips.indexWhere((c) => c.id == clipId);
    if (currentIndex == -1) return;
    final moving = clips.removeAt(currentIndex);
    int insertIndex = clips.length;
    for (int i = 0; i < clips.length; i++) {
      final c = clips[i];
      final mid = c.startTime + (c.endTime - c.startTime) ~/ 2;
      if (dropTime < mid) {
        insertIndex = i;
        break;
      }
    }
    clips.insert(insertIndex, moving);
    Duration cursor = Duration.zero;
    final repacked = <VideoClip>[];
    for (final c in clips) {
      final dur = c.endTime - c.startTime;
      final updated = c.copyWith(startTime: cursor, endTime: cursor + dur);
      repacked.add(updated);
      cursor += dur;
    }
    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: repacked);
    _scheduleAutoSave();
    notifyListeners();
  }

  void mergeVideoClips(String firstClipId, String secondClipId) {
    if (_currentProject == null) return;
    final firstIndex = _currentProject!.videoClips
        .indexWhere((clip) => clip.id == firstClipId);
    final secondIndex = _currentProject!.videoClips
        .indexWhere((clip) => clip.id == secondClipId);
    if (firstIndex == -1 || secondIndex == -1) return;
    if ((firstIndex - secondIndex).abs() != 1) return;
    final firstClip = _currentProject!.videoClips[firstIndex];
    final secondClip = _currentProject!.videoClips[secondIndex];
    if (firstClip.mediaType != MediaType.video ||
        secondClip.mediaType != MediaType.video) {
      return;
    }
    if (firstClip.videoFile == null || secondClip.videoFile == null) return;
    if (firstClip.videoFile!.path != secondClip.videoFile!.path) return;
    if (firstClip.endTime != secondClip.startTime) return;
    final mergedClip = VideoClip(
      id: _uuid.v4(),
      mediaType: MediaType.video,
      videoFile: firstClip.videoFile,
      startTime: firstClip.startTime,
      endTime: secondClip.endTime,
      sourceStart: firstClip.sourceStart,
      sourceEnd: secondClip.sourceEnd,
    );
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    final minIndex = firstIndex < secondIndex ? firstIndex : secondIndex;
    final maxIndex = firstIndex > secondIndex ? firstIndex : secondIndex;
    updatedClips.removeAt(maxIndex);
    updatedClips.removeAt(minIndex);
    updatedClips.insert(minIndex, mergedClip);
    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> extractAudioFromVideoClip(String clipId) async {
    if (_currentProject == null) return;
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    if (clip.mediaType != MediaType.video || clip.videoFile == null) return;

    // Extract audio from video
    final audioPath = await extractAudioFromVideo(clipId);
    if (audioPath == null) {
      print('Failed to extract audio from video clip');
      return;
    }

    // Add extracted audio as audio overlay
    final audioFile = File(audioPath);
    await addAudioOverlay(
      audioFile: audioFile,
      startTime: clip.startTime,
      endTime: clip.endTime,
      audioStartOffset: Duration.zero,
      volume: 1.0,
      fadeIn: false,
      fadeOut: false,
    );

    // Mute the original video clip to prevent echo
    recordUndo();
    final mutedClip = clip.copyWith(isMuted: true);
    _currentProject = _currentProject!.updateVideoClip(clipId, mutedClip);
    _scheduleAutoSave();
    notifyListeners();

    print(
        'Successfully extracted audio from video clip, added to audio track, and muted original clip');
  }

  void duplicateVideoClip(String clipId) {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    // Calculate the end time of the last clip in the timeline
    Duration timelineEnd = Duration.zero;
    for (final clip in _currentProject!.videoClips) {
      if (clip.endTime > timelineEnd) {
        timelineEnd = clip.endTime;
      }
    }

    // Create a duplicate clip with new ID, ensuring source properties are copied
    final duplicatedClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: timelineEnd,
      endTime: timelineEnd + originalClip.duration,
      sourceStart: originalClip.sourceStart,
      sourceEnd: originalClip.sourceEnd,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips.add(duplicatedClip);

    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  void deleteVideoClip(String clipId) {
    if (_currentProject == null) return;
    final updatedClips =
        _currentProject!.videoClips.where((clip) => clip.id != clipId).toList();
    if (_selectedVideoClipId == clipId) {
      _selectedVideoClipId = null;
    }
    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  void moveVideoClip(String clipId, Duration newStartTime) {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    final originalClip = _currentProject!.videoClips[clipIndex];
    final clipDuration = originalClip.endTime - originalClip.startTime;
    const maxTimelineDuration = Duration(hours: 1);
    final maxStartTime = maxTimelineDuration - clipDuration;
    Duration desiredStart = newStartTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;
    if (desiredStart > maxStartTime) desiredStart = maxStartTime;

    final updatedClip = originalClip.copyWith(
      startTime: desiredStart,
      endTime: desiredStart + clipDuration,
    );
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;
    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  bool get hasProject => _currentProject != null;
  bool get hasVideoController => _videoController != null;

  Future<void> setOutputSettings({Size? resolution, int? frameRate}) async {
    if (_currentProject == null) return;
    final newRes = resolution ?? _currentProject!.outputResolution;
    final newFps = frameRate ?? _currentProject!.outputFrameRate;
    if (newRes == _currentProject!.outputResolution &&
        newFps == _currentProject!.outputFrameRate) {
      return;
    }
    recordUndo();
    _currentProject = _currentProject!.copyWith(
      outputResolution: newRes,
      outputFrameRate: newFps,
      lastModified: DateTime.now(),
    );
    await _autoSaveProject();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> setAspectRatio(double ratio) async {
    if (_currentProject == null) return;
    Size newRes;
    if (ratio < 0.9) {
      newRes = const Size(1080, 1920);
    } else if (ratio > 1.1) {
      newRes = const Size(1920, 1080);
    } else {
      newRes = const Size(1080, 1080);
    }
    if (_currentProject!.outputResolution == newRes) return;
    recordUndo();
    _currentProject = _currentProject!.copyWith(
      outputResolution: newRes,
      lastModified: DateTime.now(),
    );
    await _autoSaveProject();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> setOriginalResolution() async {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) return;
    final firstClip = _currentProject!.videoClips.firstWhere(
      (c) => c.mediaType == MediaType.video && c.videoFile != null,
      orElse: () => _currentProject!.videoClips.first,
    );

    if (firstClip.mediaType == MediaType.video && firstClip.videoFile != null) {
      final path = firstClip.videoFile!.path;
      var controller = _previewControllers[path];
      if (controller == null) {
        controller = VideoPlayerController.file(File(path));
        await controller.initialize();
      }

      if (controller.value.isInitialized) {
        final videoSize = controller.value.size;
        final aspectRatio = controller.value.aspectRatio;
        double finalW = videoSize.width;
        double finalH = videoSize.height;
        if (aspectRatio < 1.0 && finalW > finalH) {
          finalW = videoSize.height;
          finalH = videoSize.width;
        } else if (aspectRatio > 1.0 && finalH > finalW) {
          finalW = videoSize.height;
          finalH = videoSize.width;
        }
        if (finalW % 2 != 0) finalW -= 1;
        if (finalH % 2 != 0) finalH -= 1;
        final originalSize = Size(finalW, finalH);

        if (!_previewControllers.containsKey(path)) {
          await controller.dispose();
        }

        if (_currentProject!.outputResolution == originalSize) return;
        recordUndo();
        _currentProject = _currentProject!.copyWith(
          outputResolution: originalSize,
          lastModified: DateTime.now(),
        );
        await _autoSaveProject();
        _scheduleAutoSave();
        notifyListeners();
      }
    }
  }

  Future<void> createNewProject(String name) async {
    _currentProject = VideoProject(
      id: _uuid.v4(),
      name: name,
    );
    _resetControllers();
    _undoStack.clear();
    _redoStack.clear();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> closeProject() async {
    await _disposeControllers();
    _currentProject = null;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }

  void _scheduleAutoSave() {
    // Every edit goes through here: re-render transitions it may affect.
    _scheduleTransitionRenders();
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _autoSaveProject();
    });
  }

  Future<void> loadVideoFile(File videoFile) async {
    try {
      _isLoading = true;
      _loadingMessage = 'Importing video...';
      notifyListeners();

      var savedFile = await _importFileToAppDocs(videoFile);

      // Validate video codec and re-encode if necessary
      final isCompatible = await _validateVideoCodec(savedFile);
      if (!isCompatible) {
        _exportError =
            'Incompatible video codec. Re-encoding video for compatibility...';
        _loadingMessage = 'Re-encoding for device compatibility...';
        notifyListeners();

        final reencoded = await _reencodeVideoForCompatibility(savedFile);
        if (reencoded == null) {
          throw Exception(
              'Failed to re-encode video: Device hardware decoder cannot process this video format. Try using a different video file or convert it using H.264 codec.');
        }
        savedFile = reencoded;
      }

      final path = savedFile.path;
      await _manageControllerMemory(path);

      var controller = _previewControllers[path];
      if (controller == null) {
        controller = VideoPlayerController.file(
          savedFile,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        await controller.initialize();
        await controller.setVolume(0.0);
        _previewControllers[path] = controller;
      }

      final videoSize = controller.value.size;
      var aspectRatio = controller.value.aspectRatio;
      final rotationDeg = controller.value.rotationCorrection;
      // rotationCorrection is the clockwise degrees needed to display the video
      // correctly.  If it's 90 or 270 we know the native orientation is portrait.
      bool rotated = (rotationDeg % 180) != 0;
      if (rotated) {
        aspectRatio = 1 / aspectRatio;
      }

      double finalW = videoSize.width;
      double finalH = videoSize.height;

      // ensure width/height orientation matches the logical aspect ratio
      if (rotated) {
        // swap dimensions to keep output resolution in portrait when
        // rotation indicates portrait
        finalW = videoSize.height;
        finalH = videoSize.width;
      } else {
        if (aspectRatio < 1.0 && finalW > finalH) {
          finalW = videoSize.height;
          finalH = videoSize.width;
        } else if (aspectRatio > 1.0 && finalH > finalW) {
          finalW = videoSize.height;
          finalH = videoSize.width;
        }
      }

      if (finalW % 2 != 0) finalW -= 1;
      if (finalH % 2 != 0) finalH -= 1;

      Duration nextStart = Duration.zero;
      if (_currentProject != null && _currentProject!.videoClips.isNotEmpty) {
        for (final c in _currentProject!.videoClips) {
          if (c.endTime > nextStart) nextStart = c.endTime;
        }
      }

      final videoClip = VideoClip(
        id: _uuid.v4(),
        mediaType: MediaType.video,
        videoFile: savedFile,
        startTime: nextStart,
        endTime: nextStart + controller.value.duration,
        sourceStart: Duration.zero,
        sourceEnd: controller.value.duration,
        trimStart: Duration.zero,
        trimEnd: controller.value.duration,
      );

      if (_currentProject == null) {
        _currentProject = VideoProject(
          id: _uuid.v4(),
          name: 'New Project',
          videoClips: [videoClip],
          totalDuration: const Duration(hours: 1),
          outputResolution: Size(finalW, finalH),
        );
      } else {
        if (_currentProject!.videoClips.isEmpty) {
          _currentProject =
              _currentProject!.copyWith(outputResolution: Size(finalW, finalH));
        }
        _currentProject = _currentProject!.addVideoClip(videoClip);
      }

      if (_previewController == null) {
        await _switchActivePreviewController(path);
      }

      // Pre-warm preview surface and cache initial frame for instant, stutter-free playback
      _loadingMessage = 'Preparing media preview...';
      notifyListeners();
      try {
        await _previewController?.seekTo(Duration.zero);
        await VideoThumbnailService().extractFirstFrame(path);
      } catch (_) {}

      // Short buffer delay to allow GPU texture and ExoPlayer decoder to settle
      await Future.delayed(const Duration(milliseconds: 500));

      _isLoading = false;
      _loadingMessage = null;
      await _autoSaveProject();
      _scheduleAutoSave();
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _loadingMessage = null;
      String errorMsg = _parseVideoError(e.toString());
      _exportError = errorMsg;
      notifyListeners();
      rethrow;
    }
  }

  /// Validate if the video codec is compatible with the device
  Future<bool> _validateVideoCodec(File videoFile) async {
    try {
      // Try to initialize the controller with a 15-second timeout for large/4K media
      final testController = VideoPlayerController.file(videoFile);
      await testController.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          testController.dispose();
          throw TimeoutException('Video codec validation timeout');
        },
      );

      final isValid = testController.value.isInitialized;
      testController.dispose();
      return isValid;
    } catch (e) {
      // If initialization fails, video codec is likely incompatible
      return false;
    }
  }

  /// Re-encode video to ensure device compatibility using FFmpeg
  Future<File?> _reencodeVideoForCompatibility(File videoFile) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          p.join(appDir.path, 'videos', 'reencoded_$timestamp.mp4');

      // Ensure output directory exists
      await Directory(p.dirname(outputPath)).create(recursive: true);

      // FFmpeg command to re-encode with compatible settings
      // Use baseline H.264 profile for maximum compatibility
      final session = await FFmpegKit.execute(
          '-i "${videoFile.path}" -c:v libx264 -profile:v baseline -crf 23 -c:a aac -b:a 128k "$outputPath"');

      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return File(outputPath);
      } else {
        final logs = await session.getLogsAsString();
        debugPrint('FFmpeg re-encoding failed: $logs');
        return null;
      }
    } catch (e) {
      debugPrint('Video re-encoding error: $e');
      return null;
    }
  }

  /// Parse and provide helpful error messages for video codec issues
  String _parseVideoError(String errorMessage) {
    if (errorMessage.contains('MediaCodec') ||
        errorMessage.contains('ExoPlaybackException')) {
      return 'Video codec error: Your device cannot play this video format. '
          'This may be due to:\n• Incompatible video codec or profile\n• Hardware decoder limitation\n• Corrupted video file\n\n'
          'Solution: The app will automatically attempt to re-encode the video. '
          'If this fails, please use a different video file or convert it to MP4 with H.264 codec.';
    } else if (errorMessage.contains('Timeout')) {
      return 'Video loading timed out. The file may be corrupted or too large. Try a smaller video file.';
    } else if (errorMessage.contains('Permission')) {
      return 'Permission denied. Cannot access the video file. Please check file permissions.';
    } else if (errorMessage.contains('Format')) {
      return 'Unsupported video format. Please use MP4 with H.264 codec.';
    }
    return 'Failed to load video: $errorMessage';
  }

  /// Logical size of a still image for [outputResolution] (uses [FileImage] so EXIF orientation is applied).
  Future<Size?> _readImageDisplaySize(File file) async {
    try {
      final completer = Completer<Size>();
      final stream = FileImage(file).resolve(const ImageConfiguration());
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          if (!completer.isCompleted) {
            completer.complete(Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            ));
          }
          stream.removeListener(listener);
        },
        onError: (Object error, StackTrace? stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace ?? StackTrace.empty);
          }
        },
      );
      stream.addListener(listener);
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      try {
        final data = await file.readAsBytes();
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        final w = frame.image.width.toDouble();
        final h = frame.image.height.toDouble();
        frame.image.dispose();
        codec.dispose();
        return Size(w, h);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> loadImageFile(File imageFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      final savedFile = await _importFileToAppDocs(imageFile);

      final decoded = await _readImageDisplaySize(savedFile);
      double finalW = decoded?.width ?? 1920.0;
      double finalH = decoded?.height ?? 1080.0;
      if (finalW % 2 != 0) finalW -= 1;
      if (finalH % 2 != 0) finalH -= 1;

      Duration nextStart = Duration.zero;
      if (_currentProject != null && _currentProject!.videoClips.isNotEmpty) {
        for (final c in _currentProject!.videoClips) {
          if (c.endTime > nextStart) nextStart = c.endTime;
        }
      }

      const imageDuration = Duration(seconds: 3);
      final imageClip = VideoClip(
        id: _uuid.v4(),
        mediaType: MediaType.image,
        imageFile: savedFile,
        startTime: nextStart,
        endTime: nextStart + imageDuration,
        sourceStart: Duration.zero,
        sourceEnd: imageDuration,
        trimStart: Duration.zero,
        trimEnd: imageDuration,
      );

      if (_currentProject == null) {
        _currentProject = VideoProject(
          id: _uuid.v4(),
          name: 'New Project',
          videoClips: [imageClip],
          totalDuration: const Duration(hours: 1),
          outputResolution: Size(finalW, finalH),
        );
      } else {
        if (_currentProject!.videoClips.isEmpty) {
          _currentProject =
              _currentProject!.copyWith(outputResolution: Size(finalW, finalH));
        }
        _currentProject = _currentProject!.addVideoClip(imageClip);
      }

      _isLoading = false;
      await _autoSaveProject();
      _scheduleAutoSave();
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _exportError = 'Failed to load image: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> togglePlayback() async {
    if (!_isPlaying && _resumePlaybackAfterScrub) {
      // Pause pressed while scrubbing a playing video: just don't resume.
      _resumePlaybackAfterScrub = false;
      notifyListeners();
      return;
    }
    if (_isPlaying) {
      _seekSyncSerial++;
      _playbackRecoverySerial++;
      _playbackRecoveryInFlight = false;
      _seekPauseTimer?.cancel();
      _deferredSeekSyncTimer?.cancel();
      _isPlaying = false;
      _stopTimelineClock();
      _activePreviewClipId = null;
      _activeTransitionId = null;
      notifyListeners();
      await _pauseAllPreviewControllers();
      await _pauseAllAudioPlayers();
    } else {
      final serial = ++_seekSyncSerial;
      _seekPauseTimer?.cancel();
      _deferredSeekSyncTimer?.cancel();

      // Reset position to zero if at the end of the timeline
      final maxDuration = totalDuration;
      if (_currentPosition >= maxDuration && maxDuration > Duration.zero) {
        _currentPosition = Duration.zero;
        _updateTimelineClock();
      }

      _isPlaying = true;
      notifyListeners();

      var canStartTimeline = true;

      final clip = _renderedTransitionAt(_currentPosition) != null
          ? null // the rendered transition clip takes over on the first tick
          : _clipAtTimeline(_currentPosition);
      if (clip != null) {
        if (clip.mediaType == MediaType.video && clip.videoFile != null) {
          final synced = await _syncVideoForRequestedPlayback(
            clip,
            serial: serial,
          );
          if (serial != _seekSyncSerial) return;
          if (synced) {
            _activePreviewClipId = clip.id;
          } else {
            _isPlaying = false;
            _activePreviewClipId = null;
            canStartTimeline = false;
            await _pauseAllPreviewControllers();
            await _pauseAllAudioPlayers();
            notifyListeners();
            return;
          }
        } else {
          await _previewController?.pause();
          await _previewController?.setVolume(0.0);
          if (clip.mediaType == MediaType.image) {
            _activePreviewClipId = clip.id;
          }
        }
      }

      if (_isPlaying && canStartTimeline) {
        _startTimelineClock();
        unawaited(_syncAudioPlayback(force: true));
      }
    }
    _startPositionListener();
    unawaited(_syncAudioPlayback(force: true));
    notifyListeners();
  }

  Future<bool> _syncVideoForRequestedPlayback(
    VideoClip clip, {
    required int serial,
  }) async {
    for (var attempt = 0; attempt < _maxPlaybackSyncAttempts; attempt++) {
      if (serial != _seekSyncSerial || !_isPlaying) return false;

      final synced = await _forceSyncPreviewToTimeline(
        clip,
        play: true,
        forceSeek: true,
        refreshController: Platform.isAndroid && attempt > 0,
        isCurrent: () => serial == _seekSyncSerial && _isPlaying,
      );
      if (synced) return true;

      if (attempt < _maxPlaybackSyncAttempts - 1) {
        await Future<void>.delayed(_playbackSyncRetryDelay);
      }
    }
    return false;
  }

  /// Pre-loads audio players and starts playback for active overlays
  Future<void> _prepareAudioForPlayback() async {
    if (_currentProject == null) return;

    final now = _currentPosition;
    for (final overlay in _currentProject!.audioOverlays) {
      try {
        final active = now >= overlay.startTime && now < overlay.endTime;
        if (!active) continue;

        var player = _audioPlayers[overlay.id];
        if (player == null) {
          try {
            player = AudioPlayer();
            _audioPlayers[overlay.id] = player;
          } catch (e) {
            continue;
          }
        }
        await _configureAudioPlayerSource(player, overlay);

        // Set volume
        final effectiveVolume =
            (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
        await player.setVolume(effectiveVolume);

        // Calculate position and play
        final elapsedInOverlay = now - overlay.startTime;

        final playerDur = player.duration;
        if (playerDur != null && elapsedInOverlay >= playerDur) {
          if (player.playing) {
            await player.pause();
          }
          continue;
        }

        final clampedPos = elapsedInOverlay < Duration.zero ? Duration.zero : elapsedInOverlay;

        const driftTolerance = Duration(milliseconds: 350);
        if (!player.playing || (player.position - clampedPos).abs() > driftTolerance) {
          await player.seek(clampedPos);
        }
        if (_isPlaying && !player.playing) {
          await player.play();
        }
      } catch (e) {
        debugPrint('Error preparing audio overlay ${overlay.id}: $e');
      }
    }
  }

  void _videoPositionListener() {
    // Timeline position is driven by the wall clock only. The listener is kept
    // so the VideoPlayer widget repaints; do not write back to [_currentPosition].
  }

  bool _isPositionInAnyClip(Duration position) {
    if (_currentProject == null) return false;
    const eps = Duration(milliseconds: 5);
    return _currentProject!.videoClips.any((clip) =>
        ((position - clip.startTime).abs() <= eps) ||
        (position >= clip.startTime && position < (clip.endTime - eps)));
  }

  Future<void> _applyPreviewVolumeForCurrentPosition() async {
    if (_previewController == null || _currentProject == null) return;
    final now = _currentPosition;
    double targetVolume = 0.0;
    final clip = _clipAtTimeline(now);
    if (clip != null && clip.mediaType == MediaType.video) {
      if (clip.isMuted) {
        targetVolume = 0.0;
      } else {
        final clipVol = clip.volume;
        targetVolume = (clipVol * _videoMasterVolume).clamp(0.0, 1.0);
      }
    }
    await _previewController!.setVolume(targetVolume);
  }

  void _startPositionListener() {
    _previewController?.removeListener(_videoPositionListener);
    _previewController?.addListener(_videoPositionListener);
  }

  /// Safe playback speed (guards against 0 / negative values).
  static double _safeSpeed(double speed) =>
      (speed.isNaN || speed <= 0) ? 1.0 : speed;

  /// Length a clip occupies on the timeline for a given source window.
  /// This is the same formula the exporter uses (source window / speed), so
  /// preview and export always agree on clip length.
  static Duration timelineLengthForSource(Duration source, double speed) {
    return Duration(
        microseconds: (source.inMicroseconds / _safeSpeed(speed)).round());
  }

  /// Amount of source media consumed by [timeline] of playback at [speed].
  static Duration sourceLengthForTimeline(Duration timeline, double speed) {
    return Duration(
        microseconds: (timeline.inMicroseconds * _safeSpeed(speed)).round());
  }

  /// Maps a timeline position to a position inside the clip's source file.
  ///
  /// The source window of a clip is [VideoClip.trimStart]..[VideoClip.trimEnd]
  /// — exactly what the exporter reads (`-ss trimStart -t trimmedDuration`) —
  /// and the clip's playback speed is honoured, so the preview shows the same
  /// frames that end up in the exported file.
  @visibleForTesting
  static Duration calculateSourcePositionForTimeline(
    VideoClip clip,
    Duration timelinePosition,
  ) {
    final offsetWithinClip = timelinePosition - clip.startTime;
    if (offsetWithinClip <= Duration.zero) return clip.trimStart;
    return clip.trimStart +
        sourceLengthForTimeline(offsetWithinClip, clip.playbackSpeed);
  }

  @visibleForTesting
  static Duration clampSourcePositionForVideo(
    Duration sourcePosition,
    Duration videoDuration,
  ) {
    if (videoDuration <= Duration.zero || sourcePosition <= Duration.zero) {
      return Duration.zero;
    }
    const frameEps = Duration(milliseconds: 1);
    final lastFrame =
        videoDuration > frameEps ? videoDuration - frameEps : Duration.zero;
    if (sourcePosition >= videoDuration) return lastFrame;
    return sourcePosition;
  }

  static Duration transitionPreviewVisualStart(
    Transition transition,
    VideoClip clip2,
  ) {
    return clip2.startTime;
  }

  static Duration transitionPreviewVisualEnd(
    Transition transition,
    VideoClip clip2,
  ) {
    return transitionPreviewVisualStart(transition, clip2) +
        transition.duration;
  }

  static Duration transitionPreviewPrewarmStart(
    Transition transition,
    VideoClip clip1,
    VideoClip clip2, {
    Duration minimumLead = const Duration(milliseconds: 800),
  }) {
    final lead =
        transition.duration > minimumLead ? transition.duration : minimumLead;
    final visualStart = transitionPreviewVisualStart(transition, clip2);
    var start = visualStart - lead;

    if (start < clip1.startTime) start = clip1.startTime;
    if (start > clip1.endTime) start = clip1.endTime;
    if (start > visualStart) start = visualStart;
    return start;
  }

  static double transitionPreviewProgress(
    Duration position,
    Transition transition,
    VideoClip clip2,
  ) {
    final durationMs = transition.duration.inMilliseconds;
    if (durationMs <= 0) return 1.0;

    final start = transitionPreviewVisualStart(transition, clip2);
    return ((position - start).inMilliseconds / durationMs).clamp(0.0, 1.0);
  }

  static bool isTransitionPreviewActiveAt(
    Duration position,
    Transition transition,
    VideoClip clip2,
  ) {
    final start = transitionPreviewVisualStart(transition, clip2);
    final end = transitionPreviewVisualEnd(transition, clip2);
    return position >= start && position < end;
  }

  static bool isTransitionPreviewPrewarmAt(
    Duration position,
    Transition transition,
    VideoClip clip1,
    VideoClip clip2, {
    Duration minimumLead = const Duration(milliseconds: 800),
  }) {
    final start = transitionPreviewPrewarmStart(
      transition,
      clip1,
      clip2,
      minimumLead: minimumLead,
    );
    final end = transitionPreviewVisualEnd(transition, clip2);
    return position >= start && position < end;
  }

  @visibleForTesting
  static bool shouldHoldTimelineForVideoSync({
    required bool isPlayingRequested,
    required bool controllerInitialized,
    required bool controllerPlaying,
    required bool controllerBuffering,
    required Duration controllerPosition,
    required Duration expectedPosition,
    Duration driftTolerance = const Duration(milliseconds: 1200),
  }) {
    if (!isPlayingRequested) return false;
    if (!controllerInitialized) return true;

    if (!controllerPlaying && !controllerBuffering) return true;
    final drift = (controllerPosition - expectedPosition).abs();
    if (controllerBuffering && drift > const Duration(milliseconds: 500)) {
      return true;
    }
    return drift > driftTolerance;
  }

  String? _resolvePlaybackPath(VideoClip clip) {
    if (clip.mediaType != MediaType.video || clip.videoFile == null) {
      return null;
    }
    if (clip.isReversed &&
        clip.reversedFilePath != null &&
        File(clip.reversedFilePath!).existsSync()) {
      return clip.reversedFilePath!;
    }
    return clip.videoFile!.path;
  }

  Future<void> _discardPreviewController(String filePath) async {
    final controller = _previewControllers.remove(filePath);
    _lruAccessList.remove(filePath);
    if (identical(_previewController, controller) ||
        _activeFilePath == filePath) {
      _previewController?.removeListener(_videoPositionListener);
      _previewController = null;
      _activeFilePath = null;
    }
    await controller?.dispose();
  }

  Future<bool> _forceSyncPreviewToTimeline(
    VideoClip clip, {
    required bool play,
    bool forceSeek = false,
    bool allowControllerRecovery = true,
    bool refreshController = false,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return false;
    if (_previewSyncInFlight) {
      for (var i = 0; i < 20 && _previewSyncInFlight; i++) {
        if (isCurrent != null && !isCurrent()) return false;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (_previewSyncInFlight) return false;
    }
    if (isCurrent != null && !isCurrent()) return false;
    if (clip.mediaType != MediaType.video) return false;

    final videoPath = _resolvePlaybackPath(clip);
    if (videoPath == null) return false;

    _previewSyncInFlight = true;
    try {
      // Re-creating a controller throws away the decoder and its buffers
      // (seconds of "buffering" on phones). Only do it when the existing
      // controller is actually broken — never just because a seek was slow
      // or went backwards.
      if (refreshController &&
          Platform.isAndroid &&
          _isControllerBroken(videoPath)) {
        await _discardPreviewController(videoPath);
      }

      var synced = await _syncPreviewControllerOnce(
        clip,
        videoPath,
        play: play,
        forceSeek: forceSeek,
        isCurrent: isCurrent,
      );
      if (synced || !allowControllerRecovery) return synced;

      if (isCurrent != null && !isCurrent()) return false;
      if (!_isControllerBroken(videoPath)) return false;
      await _discardPreviewController(videoPath);
      synced = await _syncPreviewControllerOnce(
        clip,
        videoPath,
        play: play,
        forceSeek: true,
        isCurrent: isCurrent,
      );
      return synced;
    } finally {
      _previewSyncInFlight = false;
    }
  }

  /// True when the cached controller for [videoPath] is missing, failed to
  /// initialize or reported a playback error.
  bool _isControllerBroken(String videoPath) {
    final controller = _previewControllers[videoPath];
    if (controller == null) return false;
    final value = controller.value;
    return !value.isInitialized || value.hasError;
  }

  /// Waits until a seek has actually been completed by the native player
  /// (it is no longer buffering). Returns false only when the request was
  /// superseded or the controller broke — a slow seek is not a failure.
  Future<bool> _waitForSeekToLand(
    VideoPlayerController controller, {
    bool Function()? isCurrent,
    Duration timeout = const Duration(milliseconds: 3000),
  }) async {
    // The buffering event for a seek arrives asynchronously; give it a moment.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final deadline = DateTime.now().add(timeout);
    var readyPolls = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (isCurrent != null && !isCurrent()) return false;
      final value = controller.value;
      if (!value.isInitialized || value.hasError) return false;
      if (!value.isBuffering) {
        readyPolls++;
        if (readyPolls >= 2) return true;
      } else {
        readyPolls = 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return true;
  }

  Future<bool> _syncPreviewControllerOnce(
    VideoClip clip,
    String videoPath, {
    required bool play,
    required bool forceSeek,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return false;
    if (_activeFilePath != videoPath || _previewController == null) {
      await _switchActivePreviewController(videoPath);
    }
    if (isCurrent != null && !isCurrent()) return false;

    final controller = _previewController;
    if (controller == null || !controller.value.isInitialized) return false;

    final sourcePosition =
        calculateSourcePositionForTimeline(clip, _currentPosition);
    final videoDuration = controller.value.duration;
    if (sourcePosition >= videoDuration && videoDuration > Duration.zero) {
      await controller.pause();
      await controller.setVolume(0.0);
      return true;
    }

    final target = clampSourcePositionForVideo(sourcePosition, videoDuration);
    final currentNativePosition = controller.value.position;
    final driftMs = (currentNativePosition - target).inMilliseconds.abs();

    if (forceSeek || driftMs > 120 || !controller.value.isPlaying) {
      // Seeking a player while it is running (especially backwards) makes
      // ExoPlayer/AVPlayer show stale frames and stall. Pause, seek, and wait
      // until the decoder has landed on the new position before playing.
      if (controller.value.isPlaying) {
        await controller.pause();
      }
      await controller.seekTo(target);
      final landed = await _waitForSeekToLand(controller, isCurrent: isCurrent);
      if (!landed) return false;
    }
    if (isCurrent != null && !isCurrent()) return false;

    await _applyPreviewVolumeForCurrentPosition();
    if (clip.playbackSpeed != controller.value.playbackSpeed) {
      await controller.setPlaybackSpeed(clip.playbackSpeed);
    }
    if (isCurrent != null && !isCurrent()) return false;

    if (!play) return true;

    await controller.play();
    await _waitForControllerPlaybackStart(
      controller,
      target,
      isCurrent: isCurrent,
    );
    if (isCurrent != null && !isCurrent()) return false;

    final value = controller.value;
    if (!value.isInitialized || value.hasError) return false;
    return value.isPlaying || value.isBuffering;
  }

  Future<bool> _waitForControllerPlaybackStart(
    VideoPlayerController controller,
    Duration target, {
    bool Function()? isCurrent,
  }) async {
    var lastPosition = controller.value.position;
    final duration = controller.value.duration;
    final targetNearEnd = duration > const Duration(milliseconds: 250) &&
        target >= duration - const Duration(milliseconds: 250);

    for (var i = 0; i < 8; i++) {
      if (isCurrent != null && !isCurrent()) return false;
      await Future<void>.delayed(const Duration(milliseconds: 75));
      if (isCurrent != null && !isCurrent()) return false;

      final value = controller.value;
      if (!value.isInitialized) return false;
      final drift = (value.position - target).abs();
      final moved = (value.position - lastPosition).abs() >
          const Duration(milliseconds: 20);

      if (targetNearEnd &&
          value.position >= duration - const Duration(milliseconds: 250)) {
        return true;
      }
      if (value.isPlaying &&
          !value.isBuffering &&
          drift <= _videoDriftTolerance) {
        return true;
      }
      if (value.isPlaying &&
          moved &&
          drift <= const Duration(milliseconds: 700)) {
        return true;
      }

      lastPosition = value.position;
    }

    final value = controller.value;
    return value.isInitialized &&
        value.isPlaying &&
        !value.isBuffering &&
        (value.position - target).abs() <= _videoDriftTolerance;
  }

  Future<void> seekTo(Duration position) async {
    final previousPosition = _currentPosition;

    // Clamp position to not exceed total duration
    final maxDuration = totalDuration;
    if (position > maxDuration) {
      position = maxDuration;
    }
    if (position < Duration.zero) {
      position = Duration.zero;
    }

    _currentPosition = position;
    _updateTimelineClock();
    _activePreviewClipId = null;
    _activeTransitionId = null;

    final serial = ++_seekSyncSerial;
    final resumeWhenSynced = _isPlaying;
    if (resumeWhenSynced) {
      for (final p in _audioPlayers.values) {
        unawaited(p.pause());
      }
      _stopTimelineClock();
    }

    _scheduleDeferredSeekSync(
      serial,
      previousPosition,
      resumeWhenSynced: resumeWhenSynced,
    );
    unawaited(_syncAudioPlayback(force: true));
    notifyListeners();
  }

  Duration? _mapSourceToTimeline(Duration sourcePosition) {
    if (_currentProject == null) return null;
    final activePath = _activeFilePath;
    if (activePath == null) return null;
    const eps = Duration(milliseconds: 5);

    // Find the current active clip first
    final currentClip = _clipAtTimeline(_currentPosition);
    if (currentClip != null &&
        currentClip.mediaType == MediaType.video &&
        currentClip.videoFile != null &&
        currentClip.videoFile!.path == activePath) {
      // Check if sourcePosition is within the current clip's source range
      if ((sourcePosition - currentClip.sourceStart).abs() <= eps) {
        return currentClip.startTime;
      }
      if (sourcePosition >= currentClip.sourceStart &&
          sourcePosition < (currentClip.sourceEnd - eps)) {
        final offset = sourcePosition - currentClip.sourceStart;
        return currentClip.startTime + offset;
      }
    }

    // Fallback: If no active clip or sourcePosition not in current clip, check all clips
    for (final clip in _currentProject!.videoClips) {
      if (clip.mediaType != MediaType.video || clip.videoFile == null) continue;
      if (clip.videoFile!.path != activePath) continue;
      if ((sourcePosition - clip.sourceStart).abs() <= eps) {
        return clip.startTime;
      }
    }
    for (final clip in _currentProject!.videoClips) {
      if (clip.mediaType != MediaType.video || clip.videoFile == null) continue;
      if (clip.videoFile!.path != activePath) continue;
      if (sourcePosition >= clip.sourceStart &&
          sourcePosition < (clip.sourceEnd - eps)) {
        final offset = sourcePosition - clip.sourceStart;
        return clip.startTime + offset;
      }
    }
    return null;
  }

  VideoClip? _clipById(String clipId) {
    final project = _currentProject;
    if (project == null) return null;
    try {
      return project.videoClips.firstWhere((clip) => clip.id == clipId);
    } catch (_) {
      return null;
    }
  }

  VideoClip? _clipAtTimeline(Duration position) {
    if (_currentProject == null) return null;
    const eps = Duration(milliseconds: 5);
    for (final clip in _currentProject!.videoClips) {
      if ((position - clip.startTime).abs() <= eps) return clip;
    }
    for (final clip in _currentProject!.videoClips) {
      if (position >= clip.startTime && position < (clip.endTime - eps)) {
        return clip;
      }
    }
    return null;
  }

  void updatePosition(Duration position) {
    unawaited(seekTo(position));
  }

  void _scheduleDeferredSeekSync(
    int serial,
    Duration previousPosition, {
    required bool resumeWhenSynced,
    int attempt = 0,
  }) {
    _deferredSeekSyncTimer?.cancel();
    _seekPauseTimer?.cancel();
    // While scrubbing, coalesce seeks so the decoder can actually show a
    // frame instead of being re-seeked on every scroll event.
    final delay = resumeWhenSynced
        ? const Duration(milliseconds: 80)
        : (_isScrubbing
            ? const Duration(milliseconds: 50)
            : const Duration(milliseconds: 16));
    _deferredSeekSyncTimer = Timer(delay, () {
      unawaited(_runDeferredSeekSync(
        serial,
        previousPosition,
        resumeWhenSynced: resumeWhenSynced,
        attempt: attempt,
      ));
    });
  }

  Future<void> _runDeferredSeekSync(
    int serial,
    Duration previousPosition, {
    required bool resumeWhenSynced,
    required int attempt,
  }) async {
    if (serial != _seekSyncSerial) return;

    // Inside a rendered transition the preview shows the rendered clip.
    final renderedTransition = _renderedTransitionAt(_currentPosition);
    if (renderedTransition != null) {
      if (_isPlaying) {
        // The first timeline tick enters the rendered clip at this offset.
        if (_renderedTransitionShownId != renderedTransition.id) {
          _renderedTransitionShownId = null;
        }
        _activePreviewClipId = null;
        final rendered = _transitionClipController;
        if (rendered != null && rendered.value.isInitialized) {
          await rendered.pause();
        }
        if (serial != _seekSyncSerial) return;
        if (resumeWhenSynced) _startTimelineClock();
      } else {
        await _previewController?.pause();
        await _previewController?.setVolume(0.0);
        final shown =
            await _showRenderedTransitionStill(renderedTransition, serial);
        if (serial != _seekSyncSerial) return;
        if (!shown) _renderedTransitionShownId = null;
      }
      unawaited(_syncAudioPlayback(force: true));
      notifyListeners();
      return;
    }
    if (_renderedTransitionShownId != null) {
      _renderedTransitionShownId = null;
      final rendered = _transitionClipController;
      if (rendered != null && rendered.value.isInitialized) {
        unawaited(rendered.pause());
        unawaited(rendered.setVolume(0.0));
      }
    }

    final clip = _clipAtTimeline(_currentPosition);
    var needsVideoSync = false;
    var videoSynced = false;

    if (clip == null) {
      await _previewController?.setVolume(0.0);
      _activePreviewClipId = null;
    } else if (clip.mediaType == MediaType.image) {
      await _pauseAllPreviewControllers();
      _activePreviewClipId = clip.id;
    } else if (clip.mediaType == MediaType.video && clip.videoFile != null) {
      needsVideoSync = true;
      final isBackwardSeek = previousPosition - _currentPosition >
          const Duration(milliseconds: 500);
      final synced = await _forceSyncPreviewToTimeline(
        clip,
        play: _isPlaying,
        forceSeek: true,
        refreshController:
            Platform.isAndroid && (isBackwardSeek || attempt > 1),
        isCurrent: () => serial == _seekSyncSerial,
      );
      if (serial != _seekSyncSerial) return;
      if (synced) {
        _activePreviewClipId = clip.id;
        videoSynced = true;
      } else if (_isPlaying) {
        _activePreviewClipId = null;
        if (attempt < _maxPlaybackSyncAttempts - 1) {
          _scheduleDeferredSeekSync(
            serial,
            previousPosition,
            resumeWhenSynced: resumeWhenSynced,
            attempt: attempt + 1,
          );
          return;
        }
        await _pauseAllPreviewControllers();
        _isPlaying = false;
        notifyListeners();
        return;
      }
    }

    if (serial != _seekSyncSerial) return;
    if (resumeWhenSynced && _isPlaying) {
      if (needsVideoSync && !videoSynced) return;
      _startTimelineClock();
    }
    unawaited(_syncAudioPlayback(force: true));
    notifyListeners();
  }

  Future<void> cropVideoClip(String clipId, Rect cropRect) async {
    if (_currentProject == null) return;
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(cropRect: cropRect);
    recordUndo();
    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateVideoClipVolume(String clipId, double volume) async {
    if (_currentProject == null) return;
    final newVol = volume.clamp(0.0, 1.0);
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updated = clip.copyWith(volume: newVol);
    recordUndo();
    _currentProject = _currentProject!.updateVideoClip(clipId, updated);
    await _applyPreviewVolumeForCurrentPosition();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> rotateVideoClip(String clipId, double rotation,
      {bool skipUndo = false}) async {
    if (_currentProject == null) return;
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(rotation: rotation);
    if (!skipUndo) {
      recordUndo();
    }
    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> toggleVideoClipMirror(String clipId) async {
    if (_currentProject == null) return;
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(isMirrored: !clip.isMirrored);
    recordUndo();
    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> setVideoClipPlaybackSpeed(String clipId, double speed) async {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;
    final clip = _currentProject!.videoClips[clipIndex];
    // The exporter renders a clip as (source window / speed) seconds, so the
    // clip's timeline length changes with speed; later clips shift with it.
    final updatedClip = clip.copyWith(
      playbackSpeed: speed,
      endTime: clip.startTime +
          timelineLengthForSource(clip.trimEnd - clip.trimStart, speed),
    );
    recordUndo();
    _currentProject = _currentProject!.copyWith(
      videoClips: _replaceAndRipple(clipIndex, clip, updatedClip),
    );

    // Apply playback speed immediately if this is the current clip
    if (clipId == _selectedVideoClipId && _previewController != null) {
      await _previewController!.setPlaybackSpeed(speed);
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> toggleVideoClipReverse(String clipId,
      {Function(double)? onProgress}) async {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;
    final clip = _currentProject!.videoClips[clipIndex];

    _isReversing = true;
    notifyListeners();

    try {
      // If already reversed, just toggle the flag (keep the reversed file)
      if (clip.isReversed) {
        final updatedClip = clip.copyWith(isReversed: false);
        recordUndo();
        _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
        _scheduleAutoSave();
        return;
      }

      // If there's already a reversed file, use it
      if (clip.reversedFilePath != null &&
          File(clip.reversedFilePath!).existsSync()) {
        final updatedClip = clip.copyWith(isReversed: true);
        recordUndo();
        _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
        _scheduleAutoSave();
        return;
      }

      // Need to process the video with FFmpeg
      final reversedPath =
          await processVideoReverse(clipId, onProgress: onProgress);
      if (reversedPath != null) {
        // Update the clip with reversed file info
        final updatedClip = clip.copyWith(
          isReversed: true,
          reversedFilePath: reversedPath,
        );
        recordUndo();
        _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);

        // Clear any cached controller for this clip to ensure fresh start
        // This prevents jerky playback when playing the reversed video immediately
        _previewControllers.remove(reversedPath);
        _lruAccessList.remove(reversedPath);

        _scheduleAutoSave();
        print('toggleVideoClipReverse: Successfully set reversed flag');
      } else {
        print('toggleVideoClipReverse: FFmpeg processing failed!');
      }
    } finally {
      _isReversing = false;
      notifyListeners();
    }
  }

  /// Extract audio from a video clip using FFmpeg
  Future<String?> extractAudioFromVideo(String clipId,
      {Function(double)? onProgress}) async {
    if (_currentProject == null) return null;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return null;

    final clip = _currentProject!.videoClips[clipIndex];
    if (clip.videoFile == null) {
      print('extractAudioFromVideo: No video file attached to clip');
      return null;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final audioPath = p.join(appDir.path,
          'extracted_audio_${clip.id}_${DateTime.now().millisecondsSinceEpoch}.mp3');

      final inputPath = clip.videoFile!.path;
      print('extractAudioFromVideo: Input path: $inputPath');
      print('extractAudioFromVideo: Output path: $audioPath');

      // FFmpeg command to extract audio from video (only first audio track)
      final command =
          '-y -i "$inputPath" -vn -acodec libmp3lame -q:a 2 -map 0:a:0 "$audioPath"';
      print('extractAudioFromVideo: Command: $command');

      // Execute FFmpeg command
      final session = await FFmpegKit.execute(command);

      print('extractAudioFromVideo: FFmpeg session completed');

      // Check if the output file was created successfully
      final outputFile = File(audioPath);
      if (outputFile.existsSync()) {
        final fileSize = await outputFile.length();
        if (fileSize > 1024) {
          onProgress?.call(1.0);
          print(
              'extractAudioFromVideo: Success! File exists with size: $fileSize bytes');
          return audioPath;
        }
      }

      final returnCodeFuture = session.getReturnCode();
      final ReturnCode? returnCode = await returnCodeFuture;
      print('extractAudioFromVideo: Return code: $returnCode');

      if (returnCode != null && ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
        print(
            'extractAudioFromVideo: Success via ReturnCode! Returning path: $audioPath');
        return audioPath;
      }

      print(
          'extractAudioFromVideo: FFmpeg failed - file not found or too small, return code: $returnCode');
      return null;
    } catch (e) {
      print('extractAudioFromVideo: Exception: $e');
      return null;
    }
  }

  /// Process a video clip to create a reversed version using FFmpeg
  Future<String?> processVideoReverse(String clipId,
      {Function(double)? onProgress}) async {
    if (_currentProject == null) return null;
    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return null;

    final clip = _currentProject!.videoClips[clipIndex];
    if (clip.videoFile == null) {
      print('processVideoReverse: No video file attached to clip');
      return null;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final reversedPath = p.join(appDir.path,
          'reversed_${clip.id}_${DateTime.now().millisecondsSinceEpoch}.mp4');

      // FFmpeg command to reverse video and audio
      // Note: We use the original video file as input, not the reversed one
      final inputPath = clip.videoFile!.path;
      print('processVideoReverse: Input path: $inputPath');
      print('processVideoReverse: Output path: $reversedPath');

      final command =
          '-y -i "$inputPath" -vf reverse -af areverse -c:v libx264 -preset fast -crf 23 "$reversedPath"';
      print('processVideoReverse: Command: $command');

      // Get video duration for progress calculation
      Duration videoDuration = Duration.zero;
      if (_previewController != null &&
          _previewController!.value.isInitialized) {
        videoDuration = _previewController!.value.duration;
      }
      print('processVideoReverse: Video duration: $videoDuration');

      // Use FFmpegKit.execute to wait for completion
      final session = await FFmpegKit.execute(command);

      print('processVideoReverse: FFmpeg session completed');

      // Get statistics for progress - getStatistics returns List<Statistics>
      final statsList = await session.getStatistics();
      if (statsList.isNotEmpty && videoDuration.inMilliseconds > 0) {
        final statistics = statsList.first;
        final progress =
            (statistics.getTime() / 1000.0) / videoDuration.inMilliseconds;
        final clampedProgress = progress.clamp(0.0, 1.0);
        onProgress?.call(clampedProgress);
      }

      // Check if the output file was created successfully
      // This is more reliable than checking returnCode which can be null
      final outputFile = File(reversedPath);
      if (outputFile.existsSync()) {
        // Verify the file has content (at least 1KB for a valid video)
        final fileSize = await outputFile.length();
        if (fileSize > 1024) {
          onProgress?.call(1.0);
          print(
              'processVideoReverse: Success! File exists with size: $fileSize bytes');
          return reversedPath;
        }
      }

      // getReturnCode also returns a Future
      final returnCodeFuture = session.getReturnCode();
      final ReturnCode? returnCode = await returnCodeFuture;
      print('processVideoReverse: Return code: $returnCode');

      // Fallback: check ReturnCode if file check fails
      if (returnCode != null && ReturnCode.isSuccess(returnCode)) {
        onProgress?.call(1.0);
        print(
            'processVideoReverse: Success via ReturnCode! Returning path: $reversedPath');
        return reversedPath;
      }

      print(
          'processVideoReverse: FFmpeg failed - file not found or too small, return code: $returnCode');
      return null;
    } catch (e) {
      print('processVideoReverse: Exception: $e');
      return null;
    }
  }

  Future<void> _applyClipPlaybackSpeed(VideoClip clip) async {
    if (_previewController != null && clip.mediaType == MediaType.video) {
      await _previewController!.setPlaybackSpeed(clip.playbackSpeed);
    }
  }

  Future<void> toggleVideoClipMute(String clipId) async {
    if (_currentProject == null) return;
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(isMuted: !clip.isMuted);
    recordUndo();
    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);
    await _applyPreviewVolumeForCurrentPosition();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> addTextOverlay({
    required String text,
    required Offset position,
    required Duration startTime,
    required Duration endTime,
    double fontSize = 24.0,
    Color color = Colors.white,
    String fontFamily = 'Roboto',
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    TextAlign textAlign = TextAlign.center,
  }) async {
    if (_currentProject == null) return;

    // Convert Flutter types to our enum types
    final fontStyleEnum = fontStyle == FontStyle.italic
        ? FontStyleEnum.italic
        : FontStyleEnum.normal;
    TextAlignEnum textAlignEnum;

    switch (textAlign) {
      case TextAlign.left:
        textAlignEnum = TextAlignEnum.left;
        break;
      case TextAlign.center:
        textAlignEnum = TextAlignEnum.center;
        break;
      case TextAlign.right:
        textAlignEnum = TextAlignEnum.right;
        break;
      case TextAlign.justify:
        textAlignEnum = TextAlignEnum.justify;
        break;
      case TextAlign.start:
        textAlignEnum = TextAlignEnum.start;
        break;
      case TextAlign.end:
        textAlignEnum = TextAlignEnum.end;
        break;
      default:
        textAlignEnum = TextAlignEnum.center;
    }

    final overlay = TextOverlay(
      id: _uuid.v4(),
      text: text,
      position: position,
      fontSize: fontSize,
      color: color,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      fontStyle: fontStyleEnum,
      textAlign: textAlignEnum,
      startTime: startTime,
      endTime: endTime,
    );
    recordUndo();
    _currentProject = _currentProject!.addTextOverlay(overlay);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateTextOverlay(
    String overlayId, {
    String? text,
    Offset? position,
    double? fontSize,
    Color? color,
    String? fontFamily,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextAlign? textAlign,
    Duration? startTime,
    Duration? endTime,
    double? rotation,
    double? opacity,
  }) async {
    if (_currentProject == null) return;
    final overlay =
        _currentProject!.textOverlays.firstWhere((o) => o.id == overlayId);

    // Convert Flutter types to our enum types if provided
    FontStyleEnum? fontStyleEnum;
    if (fontStyle != null) {
      fontStyleEnum = fontStyle == FontStyle.italic
          ? FontStyleEnum.italic
          : FontStyleEnum.normal;
    }

    TextAlignEnum? textAlignEnum;
    if (textAlign != null) {
      switch (textAlign) {
        case TextAlign.left:
          textAlignEnum = TextAlignEnum.left;
          break;
        case TextAlign.center:
          textAlignEnum = TextAlignEnum.center;
          break;
        case TextAlign.right:
          textAlignEnum = TextAlignEnum.right;
          break;
        case TextAlign.justify:
          textAlignEnum = TextAlignEnum.justify;
          break;
        case TextAlign.start:
          textAlignEnum = TextAlignEnum.start;
          break;
        case TextAlign.end:
          textAlignEnum = TextAlignEnum.end;
          break;
        default:
          textAlignEnum = TextAlignEnum.center;
      }
    }

    final updatedOverlay = overlay.copyWith(
      text: text,
      position: position,
      fontSize: fontSize,
      color: color,
      fontFamily: fontFamily,
      fontWeight: fontWeight,
      fontStyle: fontStyleEnum,
      textAlign: textAlignEnum,
      startTime: startTime,
      endTime: endTime,
      rotation: rotation,
      opacity: opacity,
    );
    recordUndo();
    _currentProject =
        _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeTextOverlay(String overlayId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeTextOverlay(overlayId);
    if (_selectedTextOverlayId == overlayId) {
      _selectedTextOverlayId = null;
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> addAudioOverlay({
    required File audioFile,
    required Duration startTime,
    required Duration endTime,
    Duration audioStartOffset = Duration.zero,
    double volume = 1.0,
    bool fadeIn = false,
    bool fadeOut = false,
    int? trackIndex,
  }) async {
    if (_currentProject == null) return;

    // Use selected audio track index if provided, otherwise use the provider's selected track or default to 0
    int finalTrackIndex = trackIndex ?? _selectedAudioTrackIndex ?? 0;

    // Check if there's already a clip in the target track at the same time range
    bool hasOverlap = _currentProject!.audioOverlays
        .where((audio) => audio.trackIndex == finalTrackIndex)
        .any((audio) => _audioOverlaps(audio, startTime, endTime - startTime));

    // If there's an overlap, create a new track
    if (hasOverlap) {
      finalTrackIndex = _findAvailableAudioTrackIndex();
    }

    // Debug print to verify track index
    print('Adding audio overlay to track index: $finalTrackIndex');

    // Copy audio file to app documents directory for persistent access
    // This ensures the audio file remains available even after the picker closes
    final savedAudioFile = await _importFileToAppDocs(audioFile);

    final overlay = AudioOverlay(
      id: _uuid.v4(),
      audioFile: savedAudioFile,
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: audioStartOffset,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      trackIndex: finalTrackIndex,
    );

    // Immediately create and initialize audio player for this overlay
    try {
      final player = AudioPlayer();
      _audioPlayers[overlay.id] = player;
      await player.setFilePath(savedAudioFile.path);

      // Set volume
      await player.setVolume((volume * _audioMasterVolume).clamp(0.0, 1.0));

      // Pre-cache waveform data
      final waveform = await WaveformService.generateWaveform(
        savedAudioFile.path,
        samples: 100,
      );
      _waveformCache[overlay.id] = waveform;

      // If currently playing and we're at a position where this audio should play,
      // start playing it immediately
      if (_isPlaying &&
          _currentPosition >= startTime &&
          _currentPosition < endTime) {
        final elapsedInOverlay = _currentPosition - startTime;
        final audioPos = audioStartOffset + elapsedInOverlay;
        await player.seek(audioPos);
        await player.play();
      }
    } catch (e) {
      // Continue even if player creation fails - will be created on playback
    }

    recordUndo();
    _currentProject = _currentProject!.addAudioOverlay(overlay);

    // Sync audio playback immediately after adding
    if (_isPlaying) {
      await _syncAudioPlayback(force: true);
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateAudioOverlay(
    String overlayId, {
    File? audioFile,
    Duration? startTime,
    Duration? endTime,
    Duration? audioStartOffset,
    double? volume,
    bool? fadeIn,
    bool? fadeOut,
  }) async {
    if (_currentProject == null) return;
    final overlay =
        _currentProject!.audioOverlays.firstWhere((o) => o.id == overlayId);

    File? savedAudioFile;
    if (audioFile != null) {
      savedAudioFile = await _importFileToAppDocs(audioFile);
      final oldPlayer = _audioPlayers.remove(overlayId);
      if (oldPlayer != null) {
        try {
          await oldPlayer.stop();
          await oldPlayer.dispose();
        } catch (_) {}
      }
      _waveformCache.remove(overlayId);
      _lastSetOverlayVolume.remove(overlayId);
      _audioSourceConfigCache.remove(overlayId);
    }

    final updatedOverlay = overlay.copyWith(
      audioFile: savedAudioFile ?? overlay.audioFile,
      startTime: startTime,
      endTime: endTime,
      audioStartOffset: audioStartOffset,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
    );
    _audioSourceConfigCache.remove(overlayId);
    recordUndo();
    _currentProject =
        _currentProject!.updateAudioOverlay(overlayId, updatedOverlay);
    final player = _audioPlayers[overlayId];
    if (player != null) {
      if (volume != null) {
        await player.setVolume((volume * _audioMasterVolume).clamp(0.0, 1.0));
      }
      if (_isPlaying) {
        unawaited(_syncAudioPlayback(force: true));
      }
    } else if (_isPlaying) {
      unawaited(_syncAudioPlayback(force: true));
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeAudioOverlay(String overlayId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeAudioOverlay(overlayId);
    if (_selectedAudioOverlayId == overlayId) {
      _selectedAudioOverlayId = null;
    }
    final player = _audioPlayers.remove(overlayId);
    if (player != null) {
      try {
        await player.stop();
        await player.dispose();
      } catch (_) {}
    }
    _waveformCache.remove(overlayId);
    _lastSetOverlayVolume.remove(overlayId);
    _audioSourceConfigCache.remove(overlayId);
    if (_isPlaying) {
      unawaited(_syncAudioPlayback(force: true));
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  void cutAudioOverlay(String overlayId) {
    if (_currentProject == null) return;
    final index =
        _currentProject!.audioOverlays.indexWhere((o) => o.id == overlayId);
    if (index == -1) return;
    final original = _currentProject!.audioOverlays[index];
    final cutPosition = _currentPosition;
    if (cutPosition <= original.startTime || cutPosition >= original.endTime) {
      return;
    }
    final firstDuration = cutPosition - original.startTime;
    final secondOffset = original.audioStartOffset + firstDuration;
    final firstPart = AudioOverlay(
      id: _uuid.v4(),
      audioFile: original.audioFile,
      startTime: original.startTime,
      endTime: cutPosition,
      audioStartOffset: original.audioStartOffset,
      volume: original.volume,
      fadeIn: original.fadeIn,
      fadeOut: false,
    );
    final secondPart = AudioOverlay(
      id: _uuid.v4(),
      audioFile: original.audioFile,
      startTime: cutPosition,
      endTime: original.endTime,
      audioStartOffset: secondOffset,
      volume: original.volume,
      fadeIn: false,
      fadeOut: original.fadeOut,
    );
    final overlays = List<AudioOverlay>.from(_currentProject!.audioOverlays);
    overlays.removeAt(index);
    overlays.insert(index, firstPart);
    overlays.insert(index + 1, secondPart);
    recordUndo();
    _currentProject = _currentProject!.copyWith(audioOverlays: overlays);
    _selectedAudioOverlayId = secondPart.id;
    final oldPlayer = _audioPlayers.remove(overlayId);
    if (oldPlayer != null) {
      unawaited(() async {
        try {
          await oldPlayer.stop();
          await oldPlayer.dispose();
        } catch (_) {}
      }());
    }
    _audioSourceConfigCache.remove(overlayId);
    _lastSetOverlayVolume.remove(overlayId);
    _waveformCache.remove(overlayId);
    if (_isPlaying) {
      unawaited(_syncAudioPlayback(force: true));
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  void cutOverlayClip(String clipId) {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.overlayClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    final originalClip = _currentProject!.overlayClips[clipIndex];
    final cutPosition = _currentPosition;
    if (cutPosition <= originalClip.startTime ||
        cutPosition >= originalClip.endTime) {
      return;
    }
    final firstDuration = cutPosition - originalClip.startTime;
    final secondDuration = originalClip.endTime - cutPosition;
    final isImage = originalClip.mediaType == MediaType.image;
    // Overlay preview and export both play trimStart..trimEnd, so each half
    // keeps its own part of that window.
    final firstSourceEnd = originalClip.trimStart + firstDuration;
    final firstClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: originalClip.startTime,
      endTime: cutPosition,
      sourceStart: isImage ? Duration.zero : originalClip.sourceStart,
      sourceEnd: isImage ? firstDuration : firstSourceEnd,
      trimStart: isImage ? Duration.zero : originalClip.trimStart,
      trimEnd: isImage ? firstDuration : firstSourceEnd,
    );
    final secondClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: cutPosition,
      endTime: originalClip.endTime,
      sourceStart: isImage ? Duration.zero : firstSourceEnd,
      sourceEnd: isImage ? secondDuration : originalClip.sourceEnd,
      trimStart: isImage ? Duration.zero : firstSourceEnd,
      trimEnd: isImage ? secondDuration : originalClip.trimEnd,
    );
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips.removeAt(clipIndex);
    updatedClips.insert(clipIndex, firstClip);
    updatedClips.insert(clipIndex + 1, secondClip);
    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _selectedOverlayClipId = secondClip.id;
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> applyColorFilter(ColorFilter filter) async {
    if (_currentProject == null) return;
    recordUndo();
    // Apply filter to the selected clip specifically
    final clipId = _selectedVideoClipId;
    if (clipId != null) {
      _clipColorFilters[clipId] = filter;
    } else {
      // No clip selected: apply to project-wide filter as fallback
      _currentProject = _currentProject!.copyWith(colorFilter: filter);
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> applyFilterPreset(FilterPreset preset) async {
    if (_currentProject == null) return;
    recordUndo();
    // Apply preset to the selected clip specifically
    final clipId = _selectedVideoClipId;
    if (clipId != null) {
      final existingFilter = _clipColorFilters[clipId] ?? const ColorFilter();
      _clipColorFilters[clipId] = existingFilter.copyWith(
        filterPresetMatrices: preset.filters,
      );
    } else {
      // No clip selected: apply to project-wide filter as fallback
      final updatedFilter = _currentProject!.colorFilter.copyWith(
        filterPresetMatrices: preset.filters,
      );
      _currentProject = _currentProject!.copyWith(colorFilter: updatedFilter);
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<String?> exportVideo({
    required String outputPath,
    int crf = 23,
    String preset = 'ultrafast',
    Function(double)? onProgress,
  }) async {
    if (_currentProject == null) return null;
    try {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportError = null;
      notifyListeners();

      // Free preview controllers before export to avoid OOM during FFmpeg processing.
      // Save the active path so we can restore after export.
      final savedActivePath = _activeFilePath;
      var lastNotifiedPercent = -1;
      var lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
      if (_isPlaying) await togglePlayback();
      for (final entry in _previewControllers.entries) {
        try {
          entry.value.removeListener(_videoPositionListener);
          await entry.value.dispose();
        } catch (_) {}
      }
      _previewControllers.clear();
      _lruAccessList.clear();
      _previewController = null;
      _activeFilePath = null;

      final resultPath = await ExportService.exportProject(
        _currentProject!,
        outputPath,
        crf: crf,
        preset: preset,
        videoMasterVolume: _videoMasterVolume,
        audioMasterVolume: _audioMasterVolume,
        clipColorFilters: Map.from(_clipColorFilters),
        onProgress: (p) {
          _exportProgress = p;
          onProgress?.call(p);
          // Rebuilding the whole editor for every FFmpeg statistics callback
          // competes with the encoder for CPU; refresh at most ~8x/second or
          // when the visible percentage changes.
          final now = DateTime.now();
          final percent = (p * 100).floor();
          if (percent != lastNotifiedPercent &&
              now.difference(lastProgressNotify) >=
                  const Duration(milliseconds: 120)) {
            lastNotifiedPercent = percent;
            lastProgressNotify = now;
            notifyListeners();
          }
        },
      );
      // Restore preview controller after export
      if (savedActivePath != null) {
        try {
          await _switchActivePreviewController(savedActivePath);
        } catch (_) {}
      }

      if (resultPath == null) {
        throw StateError(
            'Native export failed or not implemented for this platform');
      }
      _isExporting = false;
      _exportProgress = 1.0;
      notifyListeners();
      return resultPath;
    } catch (e) {
      _isExporting = false;
      // A user-cancelled export is not an error.
      _exportError = ExportService.wasCancelled ? null : 'Export failed: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> cancelExport() async {
    final cancelled = await ExportService.cancelExport();
    if (cancelled) {
      _isExporting = false;
      notifyListeners();
    }
    return cancelled;
  }

  /// When switching to timeline, filters, text, etc., dismiss sticker panel and chroma editor
  /// so they do not stay active (chroma has panel priority and would otherwise stay on screen).
  void _closeStickerAndChromaPanels() {
    _showStickerPanel = false;
    if (_editorPanelMode == EditorPanelMode.chromaKey) {
      _editorPanelMode = EditorPanelMode.none;
    }
  }

  void toggleTimeline() {
    if (_showTimeline) return;
    _showTimeline = true;
    _closeStickerAndChromaPanels();
    _showFilters = false;
    _showTextEditor = false;
    _showAudioEditor = false;
    _showCropEditor = false;
    _showRotateEditor = false;
    notifyListeners();
  }

  void toggleFilters() {
    if (_showFilters) return;
    _showFilters = true;
    _closeStickerAndChromaPanels();
    _showTimeline = false;
    _showTextEditor = false;
    _showAudioEditor = false;
    _showCropEditor = false;
    _showRotateEditor = false;
    notifyListeners();
  }

  void toggleTextEditor() {
    if (_showTextEditor) return;
    _showTextEditor = true;
    _closeStickerAndChromaPanels();
    _showTimeline = false;
    _showFilters = false;
    _showAudioEditor = false;
    _showCropEditor = false;
    _showRotateEditor = false;
    notifyListeners();
  }

  void toggleAudioEditor() {
    if (_showAudioEditor) return;
    _showAudioEditor = true;
    _closeStickerAndChromaPanels();
    _showTimeline = false;
    _showFilters = false;
    _showTextEditor = false;
    _showCropEditor = false;
    _showRotateEditor = false;
    notifyListeners();
  }

  void toggleCropEditor() {
    if (_showCropEditor) return;
    _showCropEditor = true;
    _closeStickerAndChromaPanels();
    _showTimeline = false;
    _showFilters = false;
    _showTextEditor = false;
    _showAudioEditor = false;
    _showRotateEditor = false;
    notifyListeners();
  }

  // Rotation is now combined with Crop editor - this function toggles crop editor
  void toggleRotateEditor() {
    toggleCropEditor();
  }

  void toggleTrimEditor({String? mode}) {
    if (mode != null) {
      _trimMode = mode;
      _showTrimEditor = true;
      _closeStickerAndChromaPanels();
      _showTimeline = false;
      _showFilters = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    } else {
      _showTrimEditor = !_showTrimEditor;
      if (_showTrimEditor) {
        _closeStickerAndChromaPanels();
        _showTimeline = false;
        _showFilters = false;
        _showTextEditor = false;
        _showAudioEditor = false;
        _showCropEditor = false;
        _showRotateEditor = false;
      }
    }
    notifyListeners();
  }

  void toggleStickerPanel() {
    if (_showStickerPanel) return;
    _showStickerPanel = true;
    if (_editorPanelMode == EditorPanelMode.chromaKey) {
      _editorPanelMode = EditorPanelMode.none;
    }
    _showTimeline = false;
    _showFilters = false;
    _showTextEditor = false;
    _showAudioEditor = false;
    _showCropEditor = false;
    _showRotateEditor = false;
    _showTrimEditor = false;
    notifyListeners();
  }

  void setTrimMode(String mode) {
    _trimMode = mode;
    if (!_showTrimEditor) {
      _showTrimEditor = true;
      _closeStickerAndChromaPanels();
      _showTimeline = false;
      _showFilters = false;
      _showTextEditor = false;
      _showAudioEditor = false;
      _showCropEditor = false;
      _showRotateEditor = false;
    }
    notifyListeners();
  }

  /// Replaces [clipIndex] with [updatedClip] and shifts every later clip on
  /// the main track by the change in timeline length, so the timeline stays
  /// contiguous exactly like the exported video.
  List<VideoClip> _replaceAndRipple(
      int clipIndex, VideoClip originalClip, VideoClip updatedClip) {
    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;
    final durationDiff = (updatedClip.endTime - updatedClip.startTime) -
        (originalClip.endTime - originalClip.startTime);
    if (durationDiff != Duration.zero) {
      for (int i = clipIndex + 1; i < updatedClips.length; i++) {
        final c = updatedClips[i];
        updatedClips[i] = c.copyWith(
          startTime: c.startTime + durationDiff,
          endTime: c.endTime + durationDiff,
        );
      }
    }
    return updatedClips;
  }

  /// The trim editor expresses handle positions as
  /// `clip.startTime + fraction * (sourceEnd - sourceStart)`; convert that back
  /// into an absolute position inside the source file.
  static Duration _trimEditorPositionToSource(
      VideoClip clip, Duration trimPosition) {
    var source = clip.sourceStart + (trimPosition - clip.startTime);
    if (source < clip.sourceStart) source = clip.sourceStart;
    if (source > clip.sourceEnd) source = clip.sourceEnd;
    return source;
  }

  /// Applies left trim - keeps only the right portion, deletes left portion
  Future<void> applyLeftTrim(String clipId, Duration trimPosition) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    final newTrimStart = _trimEditorPositionToSource(originalClip, trimPosition);
    if (newTrimStart >=
        originalClip.trimEnd - const Duration(milliseconds: 100)) {
      return; // Can't trim everything
    }

    final newLength = timelineLengthForSource(
        originalClip.trimEnd - newTrimStart, originalClip.playbackSpeed);
    final updatedClip = originalClip.copyWith(
      endTime: originalClip.startTime + newLength,
      sourceStart: newTrimStart,
      trimStart: newTrimStart,
    );

    recordUndo();
    _currentProject = _currentProject!.copyWith(
        videoClips: _replaceAndRipple(clipIndex, originalClip, updatedClip));
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies right trim - keeps only the left portion, deletes right portion
  Future<void> applyRightTrim(String clipId, Duration trimPosition) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    final newTrimEnd = _trimEditorPositionToSource(originalClip, trimPosition);
    if (newTrimEnd <=
        originalClip.trimStart + const Duration(milliseconds: 100)) {
      return; // Can't trim everything
    }

    final newLength = timelineLengthForSource(
        newTrimEnd - originalClip.trimStart, originalClip.playbackSpeed);
    final updatedClip = originalClip.copyWith(
      endTime: originalClip.startTime + newLength,
      sourceEnd: newTrimEnd,
      trimEnd: newTrimEnd,
    );

    recordUndo();
    _currentProject = _currentProject!.copyWith(
        videoClips: _replaceAndRipple(clipIndex, originalClip, updatedClip));
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies left trim at cursor position - deletes everything before cursor, keeps from cursor onwards
  Future<void> applyLeftTrimAtCursor(String clipId) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];
    final cursorPosition = _currentPosition;
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    // Source frame under the cursor (same mapping as preview and export)
    final newTrimStart =
        calculateSourcePositionForTimeline(originalClip, cursorPosition);

    // Keep the remaining right portion at the clip's original timeline start
    final newTimelineStart = originalClip.startTime;
    final newEndTime =
        originalClip.startTime + (originalClip.endTime - cursorPosition);

    final updatedClip = originalClip.copyWith(
      startTime: newTimelineStart,
      endTime: newEndTime,
      sourceStart: newTrimStart,
      trimStart: newTrimStart,
    );

    recordUndo();
    _currentProject = _currentProject!.copyWith(
      videoClips: _replaceAndRipple(clipIndex, originalClip, updatedClip),
    );

    // Update cursor position to the start of the trimmed clip
    _currentPosition = newTimelineStart;
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies right trim at cursor position - deletes everything after cursor
  Future<void> applyRightTrimAtCursor(String clipId) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];
    final cursorPosition = _currentPosition;
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    final newTrimEnd =
        calculateSourcePositionForTimeline(originalClip, cursorPosition);

    final updatedClip = originalClip.copyWith(
      endTime: cursorPosition,
      sourceEnd: newTrimEnd,
      trimEnd: newTrimEnd,
    );

    recordUndo();
    _currentProject = _currentProject!.copyWith(
        videoClips: _replaceAndRipple(clipIndex, originalClip, updatedClip));
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies left trim at cursor position for overlay clips - deletes everything before cursor, keeps from cursor onwards
  Future<void> applyLeftTrimAtCursorForOverlay(String clipId) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.overlayClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final cursorPosition = _currentPosition;
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    final VideoClip updatedClip;
    if (originalClip.mediaType == MediaType.image) {
      final remaining = originalClip.endTime - cursorPosition;
      updatedClip = originalClip.copyWith(
        startTime: cursorPosition,
        endTime: originalClip.endTime,
        sourceStart: Duration.zero,
        sourceEnd: remaining,
        trimStart: Duration.zero,
        trimEnd: remaining,
      );
    } else {
      // Overlay preview and export both read trimStart..trimEnd.
      final newTrimStart = originalClip.trimStart + offsetWithinClip;
      updatedClip = originalClip.copyWith(
        startTime: cursorPosition,
        endTime: originalClip.endTime,
        sourceStart: newTrimStart,
        trimStart: newTrimStart,
      );
    }

    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies right trim at cursor position for overlay clips - deletes everything after cursor, keeps from start to cursor
  Future<void> applyRightTrimAtCursorForOverlay(String clipId) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.overlayClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final cursorPosition = _currentPosition;
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    final VideoClip updatedClip;
    if (originalClip.mediaType == MediaType.image) {
      updatedClip = originalClip.copyWith(
        endTime: cursorPosition,
        sourceStart: Duration.zero,
        sourceEnd: offsetWithinClip,
        trimStart: Duration.zero,
        trimEnd: offsetWithinClip,
      );
    } else {
      final newTrimEnd = originalClip.trimStart + offsetWithinClip;
      updatedClip = originalClip.copyWith(
        endTime: cursorPosition,
        sourceEnd: newTrimEnd,
        trimEnd: newTrimEnd,
      );
    }

    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies trim (split) - removes the part between the two handles and
  /// keeps the parts before and after it as two separate clips (the removed
  /// section is left as a gap on the timeline, as before).
  Future<void> applyTrimSplit(
      String clipId, Duration startTrim, Duration endTrim) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];
    final speed = originalClip.playbackSpeed;

    // Source positions of the two handles
    final firstSourceEnd =
        _trimEditorPositionToSource(originalClip, startTrim);
    final secondSourceStart =
        _trimEditorPositionToSource(originalClip, endTrim);

    if (firstSourceEnd - originalClip.trimStart <
            const Duration(milliseconds: 100) ||
        originalClip.trimEnd - secondSourceStart <
            const Duration(milliseconds: 100) ||
        secondSourceStart < firstSourceEnd) {
      return; // Parts too short
    }

    // First clip: from the clip start up to the first handle
    final firstClip = originalClip.copyWith(
      id: _uuid.v4(),
      endTime: originalClip.startTime +
          timelineLengthForSource(firstSourceEnd - originalClip.trimStart, speed),
      sourceEnd: firstSourceEnd,
      trimEnd: firstSourceEnd,
    );

    // Second clip: from the second handle to the end, placed where that
    // content sat on the timeline before the middle part was removed.
    final secondStart = originalClip.startTime +
        timelineLengthForSource(secondSourceStart - originalClip.trimStart, speed);
    final secondClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: secondStart,
      endTime: secondStart +
          timelineLengthForSource(originalClip.trimEnd - secondSourceStart, speed),
      sourceStart: secondSourceStart,
      trimStart: secondSourceStart,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips.removeAt(clipIndex);
    updatedClips.insert(clipIndex, firstClip);
    updatedClips.insert(clipIndex + 1, secondClip);

    recordUndo();
    _currentProject = _currentProject!.copyWith(
      videoClips: updatedClips,
      totalDuration: _currentProject!.calculateTotalDuration(),
    );
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateTextOverlayPosition(
      String overlayId, Offset newPosition) async {
    if (_currentProject == null) return;
    final overlayIndex =
        _currentProject!.textOverlays.indexWhere((o) => o.id == overlayId);
    if (overlayIndex == -1) return;
    final overlay = _currentProject!.textOverlays[overlayIndex];
    final updatedOverlay = overlay.copyWith(position: newPosition);
    _currentProject =
        _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    notifyListeners();
  }

  Future<void> moveTextOverlay(String overlayId, Duration newStartTime) async {
    if (_currentProject == null) return;
    final overlayIndex =
        _currentProject!.textOverlays.indexWhere((o) => o.id == overlayId);
    if (overlayIndex == -1) return;
    final overlay = _currentProject!.textOverlays[overlayIndex];
    final duration = overlay.endTime - overlay.startTime;
    final maxVideoDuration = videoClipsDuration;

    // Clamp start time to keep overlay within video bounds
    Duration clampedStart = newStartTime;
    if (clampedStart < Duration.zero) clampedStart = Duration.zero;

    // Ensure overlay doesn't extend beyond video duration
    if (maxVideoDuration > Duration.zero) {
      final maxStart = maxVideoDuration - duration;
      if (maxStart > Duration.zero && clampedStart > maxStart) {
        clampedStart = maxStart;
      } else if (maxStart <= Duration.zero) {
        // If overlay is longer than video, start at 0
        clampedStart = Duration.zero;
      }
    }

    final clampedEndTime = clampedStart + duration;
    final updatedOverlay = overlay.copyWith(
      startTime: clampedStart,
      endTime: clampedEndTime,
    );
    recordUndo();
    _currentProject =
        _currentProject!.updateTextOverlay(overlayId, updatedOverlay);
    _scheduleAutoSave();
    notifyListeners();
  }

  void selectTextOverlay(String? overlayId) {
    _selectedTextOverlayId = overlayId;
    if (overlayId != null) {
      _selectedAudioOverlayId = null;
      _selectedVideoClipId = null;
      _selectedOverlayClipId = null;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectAudioOverlay(String? overlayId) {
    _selectedAudioOverlayId = overlayId;
    if (overlayId != null) {
      _selectedTextOverlayId = null;
      _selectedVideoClipId = null;
      _selectedOverlayClipId = null;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectVideoClip(String? clipId) {
    _selectedVideoClipId = clipId;
    if (clipId != null) {
      _selectedAudioOverlayId = null;
      _selectedTextOverlayId = null;
      _selectedOverlayClipId = null;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectOverlayClip(String? clipId) {
    _selectedOverlayClipId = clipId;
    if (clipId != null) {
      _selectedVideoClipId = null;
      _selectedAudioOverlayId = null;
      _selectedTextOverlayId = null;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectSticker(String? stickerId) {
    _selectedStickerId = stickerId;
    if (stickerId != null) {
      _selectedVideoClipId = null;
      _selectedAudioOverlayId = null;
      _selectedTextOverlayId = null;
      _selectedOverlayClipId = null;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedTextOverlayId = null;
    _selectedAudioOverlayId = null;
    _selectedVideoClipId = null;
    _selectedOverlayClipId = null;
    _selectedStickerId = null;
    notifyListeners();
  }

  Future<void> addSticker({
    required String assetPath,
    Offset position = const Offset(0.5, 0.5),
    double scale = 1.0,
    double rotation = 0.0,
    required Duration startTime,
    required Duration endTime,
    double opacity = 1.0,
  }) async {
    if (_currentProject == null) return;
    final sticker = StickerModel(
      id: _uuid.v4(),
      assetPath: assetPath,
      position: position,
      scale: scale,
      rotation: rotation,
      startTime: startTime,
      endTime: endTime,
      opacity: opacity,
    );
    recordUndo();
    _currentProject = _currentProject!.addSticker(sticker);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateSticker(
    String stickerId, {
    String? assetPath,
    Offset? position,
    double? scale,
    double? rotation,
    Duration? startTime,
    Duration? endTime,
    double? opacity,
  }) async {
    if (_currentProject == null) return;
    final sticker =
        _currentProject!.stickers.firstWhere((s) => s.id == stickerId);
    final updatedSticker = sticker.copyWith(
      assetPath: assetPath,
      position: position,
      scale: scale,
      rotation: rotation,
      startTime: startTime,
      endTime: endTime,
      opacity: opacity,
    );
    recordUndo();
    _currentProject = _currentProject!.updateSticker(stickerId, updatedSticker);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> moveSticker(String stickerId, Duration newStartTime) async {
    if (_currentProject == null) return;
    final stickerIndex =
        _currentProject!.stickers.indexWhere((s) => s.id == stickerId);
    if (stickerIndex == -1) return;
    final sticker = _currentProject!.stickers[stickerIndex];
    final duration = sticker.endTime - sticker.startTime;
    final maxVideoDuration = totalDuration;

    // Clamp start time to keep sticker within bounds
    Duration clampedStart = newStartTime;
    if (clampedStart < Duration.zero) clampedStart = Duration.zero;

    if (maxVideoDuration > Duration.zero) {
      final maxStart = maxVideoDuration - duration;
      if (maxStart > Duration.zero && clampedStart > maxStart) {
        clampedStart = maxStart;
      } else if (maxStart <= Duration.zero) {
        clampedStart = Duration.zero;
      }
    }

    final clampedEndTime = clampedStart + duration;
    final updatedSticker = sticker.copyWith(
      startTime: clampedStart,
      endTime: clampedEndTime,
    );
    recordUndo();
    _currentProject = _currentProject!.updateSticker(stickerId, updatedSticker);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeSticker(String stickerId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeSticker(stickerId);
    if (_selectedStickerId == stickerId) {
      _selectedStickerId = null;
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  List<TextOverlay> get currentTextOverlays {
    if (_currentProject == null) return [];
    final overlays = _currentProject!.getTextOverlaysAtTime(_currentPosition);
    if (_previewTextOverlay != null) {
      overlays.add(_previewTextOverlay!);
    }
    return overlays;
  }

  List<AudioOverlay> get currentAudioOverlays {
    if (_currentProject == null) return [];
    return _currentProject!.getAudioOverlaysAtTime(_currentPosition);
  }

  List<Transition> get currentTransitions {
    if (_currentProject == null) return [];
    return _currentProject!.transitions.where((t) {
      final clip2 = _clipById(t.clipId2);
      return clip2 != null &&
          isTransitionPreviewActiveAt(_currentPosition, t, clip2);
    }).toList();
  }

  List<VideoEffect> get currentVideoEffects {
    if (_currentProject == null) return [];
    return _currentProject!.videoEffects
        .where((e) =>
            _currentPosition >= e.startTime &&
            _currentPosition < e.startTime + e.duration)
        .toList();
  }

  Future<void> addTransition(Transition transition) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.addTransition(transition);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateTransition(String transitionId, Transition updated) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.updateTransition(transitionId, updated);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeTransition(String transitionId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeTransition(transitionId);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> addVideoEffect(VideoEffect effect) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.addVideoEffect(effect);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateVideoEffect(String effectId, VideoEffect updated) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.updateVideoEffect(effectId, updated);
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeVideoEffect(String effectId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeVideoEffect(effectId);
    _scheduleAutoSave();
    notifyListeners();
  }

  bool get isInGap {
    if (!_isPositionInAnyClip(_currentPosition)) return true;
    final clip = _clipAtTimeline(_currentPosition);
    if (clip == null) return true;
    if (clip.mediaType == MediaType.image) return false;
    if (clip.mediaType == MediaType.video && clip.videoFile != null) {
      const eps = Duration(milliseconds: 5);
      final sourcePosition =
          calculateSourcePositionForTimeline(clip, _currentPosition);
      final path = clip.videoFile!.path;
      final controller = _previewControllers[path];
      final dur = controller?.value.duration ?? Duration.zero;
      return sourcePosition >= (dur - eps);
    }
    return true;
  }

  VideoClip? get currentVideoClip {
    return _clipAtTimeline(_currentPosition);
  }

  void _resetControllers() {
    _videoController = null;
    _previewController = null;
    _activeFilePath = null;
    _previewControllers.clear();
    _lruAccessList.clear(); // Clear LRU list too
    _isPlaying = false;
    _isScrubbing = false;
    _resumePlaybackAfterScrub = false;
    _playbackRecoverySerial++;
    _playbackRecoveryInFlight = false;
    _transitionPrewarmInFlight.clear();
    _currentPosition = Duration.zero;
    _selectedTextOverlayId = null;
    _selectedAudioOverlayId = null;
    _selectedVideoClipId = null;
    _selectedOverlayClipId = null;
    _selectedStickerId = null;
  }

  Future<void> _disposeControllers() async {
    _stopTimelineClock();
    _clearTransitionRenders();
    _seekPauseTimer?.cancel();
    _deferredSeekSyncTimer?.cancel();
    _previewController?.removeListener(_videoPositionListener);
    await _videoController?.dispose();
    for (final c in _previewControllers.values) {
      await c.dispose();
    }
    _previewControllers.clear();
    _lruAccessList.clear(); // Clear LRU list too
    _activeFilePath = null;
    for (final p in _audioPlayers.values) {
      await p.dispose();
    }
    _audioPlayers.clear();
    _waveformCache.clear();
    _resetControllers();
  }

  void _startTimelineClock() {
    _stopTimelineClock();
    _playbackStartTime = DateTime.now();
    _playbackStartPosition = _currentPosition;
    _timelineTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!_isPlaying) {
        timer.cancel();
        return;
      }
      final maxDuration = totalDuration;
      final elapsed = DateTime.now().difference(_playbackStartTime!);
      final newPosition = _playbackStartPosition! + elapsed;
      if (newPosition >= maxDuration) {
        _currentPosition = maxDuration;
        _isPlaying = false;
        _stopTimelineClock();
        _previewController?.pause();
        for (final p in _audioPlayers.values) {
          unawaited(p.pause());
        }
      } else {
        _currentPosition = newPosition;
      }

      _handleTimelineAdvance();
      notifyListeners();
    });
  }

  void _stopTimelineClock() {
    _timelineTimer?.cancel();
    _timelineTimer = null;
    _playbackStartTime = null;
    _playbackStartPosition = null;
  }

  void _updateTimelineClock() {
    if (_isPlaying && _timelineTimer != null) {
      _playbackStartTime = DateTime.now();
      _playbackStartPosition = _currentPosition;
    }
  }

  void _handleTimelineAdvance() {
    final maxDuration = totalDuration;
    if (_currentPosition >= maxDuration) {
      if (_currentPosition > maxDuration) _currentPosition = maxDuration;
      if (_isPlaying) {
        _isPlaying = false;
        _stopTimelineClock();
        _previewController?.pause();
        for (final p in _audioPlayers.values) {
          unawaited(p.pause());
        }
      }
      return;
    }

    _prewarmUpcomingTransitionControllers(_currentPosition);

    // If we're inside a transition window, drive preview using clip2
    // to avoid running two decoders simultaneously (reduces lag).
    final activeTransition = _getActiveTransitionAt(_currentPosition);
    if (_renderedTransitionShownId != null &&
        _renderedTransitionShownId != activeTransition?.id) {
      _finishRenderedTransition();
    }
    if (activeTransition != null) {
      if (_isPlaying && _playRenderedTransition(activeTransition)) {
        // The pre-rendered clip (with its own audio) is on screen.
        unawaited(_syncAudioPlayback());
        return;
      }
      final clip2 = _clipById(activeTransition.clipId2);
      if (_isPlaying &&
          clip2 != null &&
          _activeTransitionId != activeTransition.id &&
          _handOverToPrewarmedController(clip2)) {
        // Seamless switch: the incoming clip's decoder was parked on its first
        // frame ahead of time, so just start it and keep the clock running.
        _activeTransitionId = activeTransition.id;
        unawaited(_applyPreviewVolumeForCurrentPosition());
        unawaited(_syncAudioPlayback());
        return;
      }
      if (_isPlaying &&
          clip2 != null &&
          clip2.mediaType == MediaType.video &&
          clip2.videoFile != null &&
          _controllerNeedsTimelineHoldForClip(clip2)) {
        _activeTransitionId = activeTransition.id;
        _holdTimelineForVideoSync(clip2, forceSeek: true);
        unawaited(_applyPreviewVolumeForCurrentPosition());
        unawaited(_syncAudioPlayback());
        return;
      }

      if (_transitionPreviewNeedsSync(activeTransition)) {
        unawaited(_enterTransitionWindow(activeTransition));
      }
      unawaited(_applyPreviewVolumeForCurrentPosition());
      unawaited(_syncAudioPlayback());
      return;
    } else {
      _activeTransitionId = null;
    }

    final currentClip = _clipAtTimeline(_currentPosition);

    if (currentClip != null && currentClip.id != _activePreviewClipId) {
      if (_isPlaying &&
          currentClip.mediaType == MediaType.video &&
          currentClip.videoFile != null &&
          _canContinueSeamlessly(currentClip)) {
        // Next clip continues the same file at the frame that is already
        // playing (e.g. the two halves of a cut): no pause/seek hitch.
        _activePreviewClipId = currentClip.id;
      } else if (_isPlaying &&
          currentClip.mediaType == MediaType.video &&
          currentClip.videoFile != null) {
        _holdTimelineForVideoSync(currentClip, forceSeek: true);
      } else {
        unawaited(_enterClip(currentClip));
      }
    } else if (currentClip == null && _activePreviewClipId != null) {
      _activePreviewClipId = null;
      unawaited(_leaveClip());
    } else if (_isPlaying &&
        currentClip != null &&
        currentClip.mediaType == MediaType.video) {
      _maybeHoldForStalledVideo(currentClip);
    }

    unawaited(_applyPreviewVolumeForCurrentPosition());
    unawaited(_syncAudioPlayback());
  }

  /// True when the active controller is already playing [clip]'s file at the
  /// right speed and within a few frames of where [clip] should be.
  bool _canContinueSeamlessly(VideoClip clip) {
    final videoPath = _resolvePlaybackPath(clip);
    final controller = _previewController;
    if (videoPath == null ||
        _activeFilePath != videoPath ||
        controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isPlaying ||
        controller.value.isBuffering) {
      return false;
    }
    if ((controller.value.playbackSpeed - clip.playbackSpeed).abs() > 0.001) {
      return false;
    }
    final expected = clampSourcePositionForVideo(
      calculateSourcePositionForTimeline(clip, _currentPosition),
      controller.value.duration,
    );
    return (controller.value.position - expected).abs() <=
        const Duration(milliseconds: 250);
  }

  bool _controllerNeedsTimelineHoldForClip(VideoClip clip) {
    final videoPath = _resolvePlaybackPath(clip);
    final controller = _previewController;
    if (videoPath == null ||
        _activeFilePath != videoPath ||
        controller == null ||
        !controller.value.isInitialized) {
      return true;
    }

    final expected = clampSourcePositionForVideo(
      calculateSourcePositionForTimeline(clip, _currentPosition),
      controller.value.duration,
    );
    return shouldHoldTimelineForVideoSync(
      isPlayingRequested: _isPlaying,
      controllerInitialized: controller.value.isInitialized,
      controllerPlaying: controller.value.isPlaying,
      controllerBuffering: controller.value.isBuffering,
      controllerPosition: controller.value.position,
      expectedPosition: expected,
    );
  }

  /// If the decoder stalls or drifts from the wall-clock timeline, stop the
  /// wall-clock until the active controller has actually resumed. This prevents
  /// the playhead from running ahead while Android is still recovering from a
  /// seek/flush.
  void _maybeHoldForStalledVideo(VideoClip clip) {
    if (!_controllerNeedsTimelineHoldForClip(clip)) return;
    _holdTimelineForVideoSync(clip, forceSeek: true);
  }

  void _holdTimelineForVideoSync(
    VideoClip clip, {
    required bool forceSeek,
  }) {
    if (!_isPlaying || _playbackRecoveryInFlight) return;

    _playbackRecoveryInFlight = true;
    final recoverySerial = ++_playbackRecoverySerial;
    final seekSerial = _seekSyncSerial;

    _stopTimelineClock();
    unawaited(_syncAudioPlayback());

    unawaited(_recoverVideoAndResumePlayback(
      clip,
      recoverySerial: recoverySerial,
      seekSerial: seekSerial,
      forceSeek: forceSeek,
    ));
  }

  Future<void> _recoverVideoAndResumePlayback(
    VideoClip clip, {
    required int recoverySerial,
    required int seekSerial,
    required bool forceSeek,
  }) async {
    var synced = false;

    bool isCurrent() {
      if (recoverySerial != _playbackRecoverySerial) return false;
      if (seekSerial != _seekSyncSerial) return false;
      if (!_isPlaying) return false;
      return _clipAtTimeline(_currentPosition)?.id == clip.id;
    }

    try {
      for (var attempt = 0; attempt < _maxPlaybackSyncAttempts; attempt++) {
        if (!isCurrent()) return;
        synced = await _forceSyncPreviewToTimeline(
          clip,
          play: true,
          forceSeek: forceSeek || attempt > 0,
          refreshController: Platform.isAndroid && attempt > 0,
          allowControllerRecovery: true,
          isCurrent: isCurrent,
        );
        if (synced) break;
        if (attempt < _maxPlaybackSyncAttempts - 1) {
          await Future<void>.delayed(_playbackSyncRetryDelay);
        }
      }

      if (!isCurrent()) return;
      if (synced) {
        _activePreviewClipId = clip.id;
        try {
          await _prepareAudioForPlayback();
        } catch (e) {
          debugPrint('Error preparing audio in recovery: $e');
        }
        if (isCurrent()) {
          _startTimelineClock();
        }
      } else {
        _isPlaying = false;
        _activePreviewClipId = null;
        await _pauseAllPreviewControllers();
        await _pauseAllAudioPlayers();
      }
    } catch (e) {
      debugPrint('Error in _recoverVideoAndResumePlayback: $e');
      if (isCurrent()) {
        _startTimelineClock();
      }
    } finally {
      if (recoverySerial == _playbackRecoverySerial) {
        _playbackRecoveryInFlight = false;
      }
      notifyListeners();
    }
  }

  Future<void> _syncVideoToTimeline(VideoClip clip) async {
    final synced = await _forceSyncPreviewToTimeline(
      clip,
      play: _isPlaying,
      forceSeek: false,
    );
    if (synced) _activePreviewClipId = clip.id;
  }

  void _prewarmUpcomingTransitionControllers(Duration now) {
    final project = _currentProject;
    if (project == null || project.transitions.isEmpty) return;

    for (final transition in project.transitions) {
      final clip1 = _clipById(transition.clipId1);
      final clip2 = _clipById(transition.clipId2);
      if (clip1 == null || clip2 == null) continue;
      if (!isTransitionPreviewPrewarmAt(
        now,
        transition,
        clip1,
        clip2,
        minimumLead: _transitionControllerPrewarmLead,
      )) {
        continue;
      }

      // With a rendered clip the incoming decoder is only needed once the
      // transition is over, so park it at the end of the window instead.
      final renderedFile = _renderedFileFor(transition);
      if (renderedFile != null &&
          _renderedTransitionShownId != transition.id) {
        unawaited(_prewarmRenderedTransitionClip(renderedFile));
      }

      if (clip2.mediaType != MediaType.video || clip2.videoFile == null) {
        continue;
      }

      final clip2Path = _resolvePlaybackPath(clip2);
      if (clip2Path == null) continue;

      final clip1Path = _resolvePlaybackPath(clip1);
      if (clip2Path == _activeFilePath || clip2Path == clip1Path) {
        continue;
      }

      final target = renderedFile != null
          ? _renderedHandoverSourcePosition(transition, clip2)
          : clip2.trimStart;
      final key = '${transition.id}|$clip2Path|${target.inMilliseconds}';
      if (_transitionPrewarmInFlight.contains(key) ||
          _isControllerParkedAt(clip2Path, target)) {
        continue;
      }

      _transitionPrewarmInFlight.add(key);
      unawaited(_prewarmTransitionController(clip2, clip2Path, key, target));
    }
  }

  /// Makes the prewarmed controller of [clip] the active one and starts it
  /// without pausing the timeline clock, the way NLEs cut into a clip whose
  /// decoder is already primed. Returns false (and changes nothing) when the
  /// controller is not parked on the clip's first frame; the caller then
  /// falls back to the regular hold-and-sync path.
  bool _handOverToPrewarmedController(VideoClip clip) {
    if (clip.mediaType != MediaType.video || clip.videoFile == null) {
      return false;
    }
    if (_previewSyncInFlight || _playbackRecoveryInFlight) return false;
    final videoPath = _resolvePlaybackPath(clip);
    if (videoPath == null || videoPath == _activeFilePath) return false;
    if (!_isControllerParkedAt(videoPath, clip.trimStart)) return false;

    final controller = _previewControllers[videoPath]!;
    final expected = calculateSourcePositionForTimeline(clip, _currentPosition);
    final lead = expected - controller.value.position;
    if (lead < -const Duration(milliseconds: 40) ||
        lead > const Duration(milliseconds: 250)) {
      return false;
    }

    final old = _previewController;
    old?.removeListener(_videoPositionListener);
    if (old != null && old.value.isInitialized) {
      unawaited(old.pause());
      unawaited(old.setVolume(0.0));
    }
    _previewController = controller;
    _activeFilePath = videoPath;
    _activePreviewClipId = clip.id;
    controller.addListener(_videoPositionListener);
    _lruAccessList
      ..remove(videoPath)
      ..add(videoPath);

    // The timer tick that crossed the cut is up to one tick past the clip
    // start; pull the playhead back onto the frame the decoder is showing so
    // video and timeline start in lock-step (a sub-frame, invisible rewind).
    if (lead > Duration.zero) {
      final aligned = clip.startTime +
          timelineLengthForSource(
            controller.value.position - clip.trimStart,
            clip.playbackSpeed,
          );
      if (aligned >= clip.startTime && aligned < _currentPosition) {
        _currentPosition = aligned;
        _updateTimelineClock();
      }
    }

    if ((controller.value.playbackSpeed - clip.playbackSpeed).abs() > 0.001) {
      unawaited(controller.setPlaybackSpeed(clip.playbackSpeed));
    }
    unawaited(controller.play());
    return true;
  }

  /// True when the controller for [videoPath] is initialized, paused and
  /// sitting on [sourceTarget], ready to be started.
  bool _isControllerParkedAt(String videoPath, Duration sourceTarget) {
    final controller = _previewControllers[videoPath];
    if (controller == null) return false;
    final value = controller.value;
    if (!value.isInitialized || value.hasError || value.isPlaying) {
      return false;
    }
    final target = clampSourcePositionForVideo(sourceTarget, value.duration);
    return (value.position - target).abs() <= const Duration(milliseconds: 40);
  }

  Future<void> _prewarmTransitionController(
    VideoClip clip,
    String videoPath,
    String key,
    Duration sourceTarget,
  ) async {
    try {
      final controller = await ensurePreviewController(videoPath);
      if (controller == null || !controller.value.isInitialized) return;
      // It may have become the active controller while initializing.
      if (identical(controller, _previewController)) return;

      await controller.setVolume(0.0);
      if (controller.value.isPlaying) await controller.pause();
      final target = clampSourcePositionForVideo(
        sourceTarget,
        controller.value.duration,
      );
      if ((controller.value.position - target).abs() >
          const Duration(milliseconds: 40)) {
        // A paused seek decodes and renders the frame into the texture, so
        // the hand-over shows it instantly.
        await controller.seekTo(target);
      }
      if ((controller.value.playbackSpeed - clip.playbackSpeed).abs() >
          0.001) {
        await controller.setPlaybackSpeed(clip.playbackSpeed);
      }
    } catch (_) {
      // Prewarming is best effort; active playback sync still handles misses.
    } finally {
      _transitionPrewarmInFlight.remove(key);
    }
  }

  // ── Pre-rendered transitions: rendering ─────────────────────────────────

  /// Everything that changes how a transition renders. A new signature means
  /// the rendered clip is stale and gets rendered again.
  String? _transitionRenderSignature(Transition t) {
    final project = _currentProject;
    if (project == null) return null;
    final clip1 = _clipById(t.clipId1);
    final clip2 = _clipById(t.clipId2);
    if (clip1 == null || clip2 == null) return null;

    String clipSignature(VideoClip c) {
      final own = _clipColorFilters[c.id];
      final filter =
          (own != null && own.hasFilters) ? own : project.colorFilter;
      return [
        c.mediaType.name,
        _resolvePlaybackPath(c) ?? c.imageFile?.path,
        c.trimStart.inMilliseconds,
        c.trimEnd.inMilliseconds,
        (c.endTime - c.startTime).inMilliseconds,
        c.playbackSpeed,
        c.rotation,
        c.isMirrored,
        c.cropRect,
        c.volume,
        c.isMuted,
        c.chromaKeySettings?.toJson(),
        filter.toJson(),
      ].join('|');
    }

    return [
      t.type.name,
      t.duration.inMilliseconds,
      project.outputFrameRate,
      project.outputResolution,
      clipSignature(clip1),
      clipSignature(clip2),
    ].join('#');
  }

  /// Rendered clip of [t], if it is ready and still matches the timeline.
  String? _renderedFileFor(Transition t) {
    final signature = _transitionRenderSignature(t);
    return signature == null ? null : _transitionRenderFiles[signature];
  }

  /// The active transition at [position] when its rendered clip is ready.
  Transition? _renderedTransitionAt(Duration position) {
    final t = _getActiveTransitionAt(position);
    if (t == null || _renderedFileFor(t) == null) return null;
    return t;
  }

  /// Source position of the incoming clip when the transition window ends,
  /// where its decoder is parked while the rendered clip plays.
  Duration _renderedHandoverSourcePosition(Transition t, VideoClip clip2) {
    final target =
        clip2.trimStart + sourceLengthForTimeline(t.duration, clip2.playbackSpeed);
    return target > clip2.trimEnd ? clip2.trimEnd : target;
  }

  void _scheduleTransitionRenders() {
    _transitionRenderDebounce?.cancel();
    _transitionRenderDebounce =
        Timer(const Duration(milliseconds: 300), _refreshTransitionRenderQueue);
  }

  void _refreshTransitionRenderQueue() {
    final project = _currentProject;
    if (project == null) return;

    final ordered = List<Transition>.from(project.transitions);
    ordered.sort((a, b) {
      final ca = _clipById(a.clipId2)?.startTime ?? Duration.zero;
      final cb = _clipById(b.clipId2)?.startTime ?? Duration.zero;
      return ca.compareTo(cb);
    });

    final live = <String>{};
    final wanted = <String>[];
    for (final t in ordered) {
      final signature = _transitionRenderSignature(t);
      if (signature == null) continue;
      live.add(signature);
      if (_transitionRenderFiles.containsKey(signature) ||
          _failedTransitionRenders.contains(signature) ||
          _transitionRenderingSignature == signature) {
        continue;
      }
      wanted.add(t.id);
    }

    // Forget renders of transitions that were removed or edited.
    final stale = _transitionRenderFiles.keys
        .where((signature) => !live.contains(signature))
        .toList();
    for (final signature in stale) {
      final file = _transitionRenderFiles.remove(signature)!;
      if (file != _transitionClipPath) _deleteQuietly(file);
    }

    _transitionRenderQueue
      ..clear()
      ..addAll(wanted);
    notifyListeners();
    unawaited(_runTransitionRenderWorker());
  }

  Future<void> _runTransitionRenderWorker() async {
    if (_transitionRenderingSignature != null) return;
    final generation = _transitionRenderGeneration;

    while (_transitionRenderQueue.isNotEmpty) {
      final transitionId = _transitionRenderQueue.removeAt(0);
      final project = _currentProject;
      if (project == null || generation != _transitionRenderGeneration) break;

      Transition? transition;
      for (final t in project.transitions) {
        if (t.id == transitionId) transition = t;
      }
      if (transition == null) continue;
      final clip1 = _clipById(transition.clipId1);
      final clip2 = _clipById(transition.clipId2);
      final signature = _transitionRenderSignature(transition);
      if (clip1 == null ||
          clip2 == null ||
          signature == null ||
          _transitionRenderFiles.containsKey(signature)) {
        continue;
      }

      _transitionRenderingSignature = signature;
      _transitionRenderProgress = 0.0;
      notifyListeners();

      String? result;
      try {
        final dir = Directory(p.join(
            (await getTemporaryDirectory()).path, 'transition_previews'));
        if (!await dir.exists()) await dir.create(recursive: true);
        final out = p.join(dir.path,
            'transition_${transition.id}_${DateTime.now().microsecondsSinceEpoch}.mp4');
        result = await ExportService.renderTransitionPreview(
          project: project,
          transition: transition,
          clip1: clip1,
          clip2: clip2,
          outputPath: out,
          clipColorFilters: Map.of(_clipColorFilters),
          onProgress: _onTransitionRenderProgress,
        );
        if (result != null && !File(result).existsSync()) result = null;
      } catch (e) {
        debugPrint('Transition preview render failed: $e');
        result = null;
      }

      _transitionRenderingSignature = null;
      if (generation != _transitionRenderGeneration) {
        if (result != null) _deleteQuietly(result);
        break;
      }

      // Keep it only if the timeline still matches what was rendered.
      String? currentSignature;
      for (final t in _currentProject?.transitions ?? const <Transition>[]) {
        if (t.id == transitionId) currentSignature = _transitionRenderSignature(t);
      }
      if (result == null) {
        _failedTransitionRenders.add(signature);
      } else if (currentSignature == signature) {
        _transitionRenderFiles[signature] = result;
      } else {
        _deleteQuietly(result);
      }
      notifyListeners();
    }

    if (_transitionRenderingSignature == null &&
        generation == _transitionRenderGeneration) {
      _transitionRenderProgress = 0.0;
      notifyListeners();
    }
  }

  void _onTransitionRenderProgress(double progress) {
    _transitionRenderProgress = progress.clamp(0.0, 1.0);
    final now = DateTime.now();
    if (now.difference(_lastRenderProgressNotify) >
        const Duration(milliseconds: 120)) {
      _lastRenderProgressNotify = now;
      notifyListeners();
    }
  }

  void _deleteQuietly(String file) {
    try {
      final f = File(file);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Drops every rendered transition and its player (project closed).
  void _clearTransitionRenders() {
    _transitionRenderGeneration++;
    _transitionRenderDebounce?.cancel();
    _transitionRenderQueue.clear();
    _transitionRenderingSignature = null;
    _transitionRenderProgress = 0.0;
    for (final file in _transitionRenderFiles.values) {
      _deleteQuietly(file);
    }
    _transitionRenderFiles.clear();
    _failedTransitionRenders.clear();
    _renderedTransitionShownId = null;
    _renderedTransitionEnterInFlight = false;
    final controller = _transitionClipController;
    _transitionClipController = null;
    _transitionClipPath = null;
    _transitionClipLoad = null;
    unawaited(controller?.dispose());
  }

  // ── Pre-rendered transitions: playback ──────────────────────────────────

  /// Loads the rendered clip [file] into the transition player.
  Future<VideoPlayerController?> _ensureTransitionClip(String file) async {
    if (_transitionClipPath == file && _transitionClipController != null) {
      final load = _transitionClipLoad;
      if (load != null) {
        try {
          await load;
        } catch (_) {}
      }
      final c = _transitionClipController;
      return (c != null && _transitionClipPath == file && c.value.isInitialized)
          ? c
          : null;
    }

    final old = _transitionClipController;
    if (old != null) {
      _renderedTransitionShownId = null;
      notifyListeners();
      // Let the preview drop its VideoPlayer before disposing.
      Future<void>.delayed(const Duration(milliseconds: 500), old.dispose);
    }

    final controller = VideoPlayerController.file(
      File(file),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _transitionClipController = controller;
    _transitionClipPath = file;
    final load = controller.initialize().then((_) => controller.setVolume(0.0));
    _transitionClipLoad = load;
    try {
      await load;
    } catch (e) {
      debugPrint('Could not load rendered transition: $e');
      if (identical(_transitionClipController, controller)) {
        _transitionClipController = null;
        _transitionClipPath = null;
      }
      unawaited(controller.dispose());
      return null;
    } finally {
      if (identical(_transitionClipLoad, load)) _transitionClipLoad = null;
    }
    return identical(_transitionClipController, controller) ? controller : null;
  }

  bool _renderedClipPrewarmInFlight = false;

  /// Loads the upcoming rendered clip and parks it on its first frame.
  Future<void> _prewarmRenderedTransitionClip(String file) async {
    final current = _transitionClipController;
    if (_transitionClipPath == file &&
        current != null &&
        current.value.isInitialized &&
        !current.value.isPlaying &&
        current.value.position <= const Duration(milliseconds: 40)) {
      return;
    }
    if (_renderedClipPrewarmInFlight || _renderedTransitionEnterInFlight) {
      return;
    }
    _renderedClipPrewarmInFlight = true;
    try {
      final controller = await _ensureTransitionClip(file);
      if (controller == null || _renderedTransitionShownId != null) return;
      if (controller.value.isPlaying) await controller.pause();
      if (controller.value.position > const Duration(milliseconds: 40)) {
        await controller.seekTo(Duration.zero);
      }
    } catch (_) {
      // Best effort; entering the transition loads it if needed.
    } finally {
      _renderedClipPrewarmInFlight = false;
    }
  }

  /// Plays the rendered clip of [t] while the playhead is in its window.
  /// Returns false to fall back to the live preview.
  bool _playRenderedTransition(Transition t) {
    final file = _renderedFileFor(t);
    final clip2 = _clipById(t.clipId2);
    if (file == null || clip2 == null) {
      if (_renderedTransitionShownId == t.id) _renderedTransitionShownId = null;
      return false;
    }

    final controller = _transitionClipController;
    final loaded = controller != null &&
        _transitionClipPath == file &&
        controller.value.isInitialized;

    if (_renderedTransitionEnterInFlight) return true;
    if (_renderedTransitionShownId == t.id &&
        loaded &&
        (controller.value.isPlaying ||
            // Finished a frame before the window closes: hold its last frame.
            controller.value.position >=
                controller.value.duration - const Duration(milliseconds: 60))) {
      return true;
    }
    // The live preview already took this pass of the transition.
    if (_activeTransitionId == t.id && _renderedTransitionShownId != t.id) {
      return false;
    }

    final offset = _currentPosition - clip2.startTime;
    if (loaded &&
        _renderedTransitionShownId != t.id &&
        !controller.value.isPlaying &&
        controller.value.position <= const Duration(milliseconds: 40) &&
        offset >= Duration.zero &&
        offset <= const Duration(milliseconds: 250)) {
      // Normal case: the playhead just crossed the cut and the clip is parked
      // on its first frame. Start it without stopping the clock and pull the
      // playhead back onto that frame (a sub-frame, invisible rewind).
      _activeTransitionId = t.id;
      _renderedTransitionShownId = t.id;
      if (offset > Duration.zero) {
        _currentPosition = clip2.startTime;
        _updateTimelineClock();
      }
      unawaited(controller.setVolume(_videoMasterVolume.clamp(0.0, 1.0)));
      unawaited(controller.play());
      unawaited(_parkIncomingClipBehindRenderedTransition(t, clip2));
      notifyListeners();
      return true;
    }

    // Entering mid-window (seek, resume, late load): hold the clock briefly.
    unawaited(_enterRenderedTransitionMidWindow(t, clip2, file));
    return true;
  }

  Future<void> _enterRenderedTransitionMidWindow(
    Transition t,
    VideoClip clip2,
    String file,
  ) async {
    _renderedTransitionEnterInFlight = true;
    final serial = _seekSyncSerial;
    _stopTimelineClock();
    _activeTransitionId = t.id;
    var started = false;
    try {
      final controller = await _ensureTransitionClip(file);
      if (controller == null) return;
      await _parkIncomingClipBehindRenderedTransition(t, clip2);
      if (serial != _seekSyncSerial || !_isPlaying) return;

      final offset = _currentPosition - clip2.startTime;
      final end = controller.value.duration;
      var target = offset < Duration.zero ? Duration.zero : offset;
      if (target > end) target = end;
      if ((controller.value.position - target).abs() >
          const Duration(milliseconds: 40)) {
        await controller.seekTo(target);
        await _waitForSeekToLand(controller,
            isCurrent: () => serial == _seekSyncSerial && _isPlaying);
      }
      if (serial != _seekSyncSerial || !_isPlaying) return;

      _renderedTransitionShownId = t.id;
      await controller.setVolume(_videoMasterVolume.clamp(0.0, 1.0));
      await controller.play();
      started = true;
    } catch (e) {
      debugPrint('Error entering rendered transition: $e');
    } finally {
      _renderedTransitionEnterInFlight = false;
      if (!started && _renderedTransitionShownId == t.id && _isPlaying) {
        _renderedTransitionShownId = null;
      }
      if (_isPlaying && serial == _seekSyncSerial && _timelineTimer == null) {
        _startTimelineClock();
      }
      notifyListeners();
    }
  }

  /// While the rendered clip plays, pause the outgoing decoder and park the
  /// incoming clip's decoder at the end of the window, so playback continues
  /// seamlessly when the transition is over (this also covers both halves of
  /// a split clip, which share one decoder).
  Future<void> _parkIncomingClipBehindRenderedTransition(
    Transition t,
    VideoClip clip2,
  ) async {
    final old = _previewController;
    if (old != null && old.value.isInitialized) {
      await old.pause();
      await old.setVolume(0.0);
    }
    if (clip2.mediaType != MediaType.video || clip2.videoFile == null) {
      _activePreviewClipId = clip2.id;
      return;
    }
    final videoPath = _resolvePlaybackPath(clip2);
    if (videoPath == null) return;

    final controller = await ensurePreviewController(videoPath);
    if (controller == null || !controller.value.isInitialized) return;
    if (_renderedTransitionShownId != t.id && _activeTransitionId != t.id) {
      return; // superseded (seek / pause)
    }
    if (controller.value.isPlaying) await controller.pause();
    await controller.setVolume(0.0);
    final target = clampSourcePositionForVideo(
      _renderedHandoverSourcePosition(t, clip2),
      controller.value.duration,
    );
    if ((controller.value.position - target).abs() >
        const Duration(milliseconds: 40)) {
      await controller.seekTo(target);
    }
    if ((controller.value.playbackSpeed - clip2.playbackSpeed).abs() > 0.001) {
      await controller.setPlaybackSpeed(clip2.playbackSpeed);
    }

    if (!identical(_previewController, controller)) {
      _previewController?.removeListener(_videoPositionListener);
      _previewController = controller;
      _activeFilePath = videoPath;
      controller.addListener(_videoPositionListener);
      _lruAccessList
        ..remove(videoPath)
        ..add(videoPath);
    }
    _activePreviewClipId = clip2.id;
  }

  /// The playhead left a rendered transition: stop the rendered clip and
  /// start the incoming clip's decoder, which is parked on this exact frame.
  void _finishRenderedTransition() {
    _renderedTransitionShownId = null;
    final rendered = _transitionClipController;
    if (rendered != null && rendered.value.isInitialized) {
      unawaited(rendered.pause());
      unawaited(rendered.setVolume(0.0));
    }
    if (!_isPlaying) return;

    final clip = _clipAtTimeline(_currentPosition);
    if (clip == null || clip.mediaType != MediaType.video) return;
    final videoPath = _resolvePlaybackPath(clip);
    final controller = _previewController;
    if (videoPath != null &&
        videoPath == _activeFilePath &&
        controller != null &&
        controller.value.isInitialized &&
        !controller.value.isPlaying &&
        !_previewSyncInFlight &&
        !_playbackRecoveryInFlight) {
      final expected = calculateSourcePositionForTimeline(clip, _currentPosition);
      final lead = expected - controller.value.position;
      if (lead >= -const Duration(milliseconds: 40) &&
          lead <= const Duration(milliseconds: 250)) {
        if (lead > Duration.zero) {
          final aligned = clip.startTime +
              timelineLengthForSource(
                controller.value.position - clip.trimStart,
                clip.playbackSpeed,
              );
          if (aligned >= clip.startTime && aligned < _currentPosition) {
            _currentPosition = aligned;
            _updateTimelineClock();
          }
        }
        if ((controller.value.playbackSpeed - clip.playbackSpeed).abs() >
            0.001) {
          unawaited(controller.setPlaybackSpeed(clip.playbackSpeed));
        }
        unawaited(controller.play());
        _activePreviewClipId = clip.id;
        return;
      }
    }
    // Not parked where expected: the regular sync path takes over.
    _activePreviewClipId = null;
  }

  /// Paused / scrubbing inside a rendered transition: show its frame.
  Future<bool> _showRenderedTransitionStill(Transition t, int serial) async {
    final file = _renderedFileFor(t);
    final clip2 = _clipById(t.clipId2);
    if (file == null || clip2 == null) return false;
    final controller = await _ensureTransitionClip(file);
    if (controller == null || serial != _seekSyncSerial) return false;
    if (controller.value.isPlaying) await controller.pause();
    await controller.setVolume(0.0);
    final offset = _currentPosition - clip2.startTime;
    final end = controller.value.duration;
    var target = offset < Duration.zero ? Duration.zero : offset;
    if (target > end) target = end;
    await controller.seekTo(target);
    if (serial != _seekSyncSerial) return false;
    _renderedTransitionShownId = t.id;
    return true;
  }

  Transition? _getActiveTransitionAt(Duration now) {
    final project = _currentProject;
    if (project == null || project.transitions.isEmpty) return null;
    for (final t in project.transitions) {
      final clip2 = _clipById(t.clipId2);
      if (clip2 != null && isTransitionPreviewActiveAt(now, t, clip2)) {
        return t;
      }
    }
    return null;
  }

  bool _transitionPreviewNeedsSync(Transition transition) {
    if (_activeTransitionId != transition.id) return true;

    final clip2 = _clipById(transition.clipId2);
    if (clip2 == null) return false;
    if (clip2.mediaType == MediaType.image) {
      return _activePreviewClipId != clip2.id;
    }
    if (clip2.mediaType != MediaType.video || clip2.videoFile == null) {
      return false;
    }

    final videoPath = _resolvePlaybackPath(clip2);
    final controller = _previewController;
    if (videoPath == null ||
        _activeFilePath != videoPath ||
        controller == null ||
        !controller.value.isInitialized ||
        _activePreviewClipId != clip2.id) {
      return true;
    }

    if (_isPlaying &&
        !controller.value.isPlaying &&
        !controller.value.isBuffering) {
      return true;
    }

    final expected = clampSourcePositionForVideo(
      calculateSourcePositionForTimeline(clip2, _currentPosition),
      controller.value.duration,
    );
    final driftMs = (controller.value.position - expected).inMilliseconds.abs();
    return driftMs > 350;
  }

  Future<void> _enterTransitionWindow(Transition t) async {
    if (_transitionOpInFlight) return;
    _transitionOpInFlight = true;
    try {
      final clip2 = _clipById(t.clipId2);
      if (clip2 == null) return;

      final isFirstEntry = _activeTransitionId != t.id;
      if (isFirstEntry) {
        _activeTransitionId = t.id;
      }

      if (clip2.mediaType == MediaType.video && clip2.videoFile != null) {
        final synced = await _forceSyncPreviewToTimeline(
          clip2,
          play: _isPlaying,
          forceSeek: isFirstEntry || _activePreviewClipId != clip2.id,
          allowControllerRecovery: true,
        );
        if (synced) {
          _activePreviewClipId = clip2.id;
        }
      } else if (clip2.mediaType == MediaType.image) {
        await _previewController?.pause();
        await _previewController?.setVolume(0.0);
        _activePreviewClipId = clip2.id;
      }
    } finally {
      _transitionOpInFlight = false;
    }
  }

  Future<void> _enterClip(VideoClip clip) async {
    if (clip.mediaType == MediaType.image) {
      await _previewController?.pause();
      await _previewController?.setVolume(0.0);
      _activePreviewClipId = clip.id;
      return;
    }
    await _syncVideoToTimeline(clip);
  }

  Future<void> _leaveClip() async {
    await _previewController?.pause();
    await _previewController?.setVolume(0.0);
  }

  /// Called when the app goes to background (e.g. file picker opens, home press).
  /// Pauses all media without changing the _isPlaying flag so resume can restart.
  Future<void> handleAppPause() async {
    await _pauseAllPreviewControllers();
    for (final p in _audioPlayers.values) {
      await p.pause();
    }
    if (_isPlaying && _timelineTimer != null) {
      _stopTimelineClock();
      _timelinePausedForBackground = true;
    }
  }

  /// Called when the app comes back to foreground.
  /// Resets the timeline clock reference point (prevents position drift) and
  /// restarts the video player if playback was active before going to background.
  void handleAppResume() {
    if (!_isPlaying) return;
    _updateTimelineClock();
    if (_timelinePausedForBackground) {
      _timelinePausedForBackground = false;
      _startTimelineClock();
    }
    unawaited(_restartCurrentClipPlayback());
  }

  /// Resumes video playback at the current timeline position if the player
  /// was paused (e.g. by the OS when the app went to background mid-clip).
  Future<void> _restartCurrentClipPlayback() async {
    final clip = _clipAtTimeline(_currentPosition);
    if (clip == null || clip.mediaType == MediaType.image) return;
    if (_isPlaying) {
      await _syncVideoToTimeline(clip);
      unawaited(_syncAudioPlayback(force: true));
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _seekPauseTimer?.cancel();
    _deferredSeekSyncTimer?.cancel();
    _disposeControllers();
    super.dispose();
  }

  void recordUndo() {
    if (_currentProject == null) return;
    if (_undoStack.length >= _maxHistory) {
      _undoStack.removeAt(0);
    }
    _undoStack.add(_currentProject!);
    _redoStack.clear();
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<void> undo() async {
    if (!canUndo) return;
    if (_currentProject != null) {
      _redoStack.add(_currentProject!);
    }
    _currentProject = _undoStack.removeLast();
    _audioSourceConfigCache.clear();
    if (_isPlaying) {
      unawaited(_syncAudioPlayback(force: true));
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> redo() async {
    if (!canRedo) return;
    if (_currentProject != null) {
      _undoStack.add(_currentProject!);
    }
    _currentProject = _redoStack.removeLast();
    _audioSourceConfigCache.clear();
    if (_isPlaying) {
      unawaited(_syncAudioPlayback(force: true));
    }
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> _autoSaveProject() async {
    if (_currentProject != null) {
      _isAutoSaving = true;
      notifyListeners();
      try {
        await HiveService.saveProject(_currentProject!);
        _lastAutoSaved = DateTime.now();
      } finally {
        _isAutoSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> forceAutoSave() async {
    _autoSaveTimer?.cancel();
    await _autoSaveProject();
  }

  /// Older builds stored some clips with `trimStart/trimEnd` that disagreed
  /// with the clip's timeline length (preview used `sourceStart`, export used
  /// `trimStart`), and ignored playback speed for the clip length. Bring such
  /// clips into the single consistent model used by both preview and export,
  /// keeping what the preview used to show.
  static VideoProject normalizeLegacyClipTiming(VideoProject project) {
    const tolerance = Duration(milliseconds: 40);
    bool close(Duration a, Duration b) => (a - b).abs() <= tolerance;

    final clips = List<VideoClip>.from(project.videoClips);
    var changed = false;
    for (int i = 0; i < clips.length; i++) {
      var c = clips[i];
      final timelineLen = c.endTime - c.startTime;
      if (timelineLen <= Duration.zero) continue;
      final speed = c.playbackSpeed;

      if (close(timelineLengthForSource(c.trimEnd - c.trimStart, speed),
          timelineLen)) {
        continue; // already consistent
      }

      final sourceWindow = c.sourceEnd - c.sourceStart;
      if (sourceWindow > Duration.zero &&
          (close(timelineLengthForSource(sourceWindow, speed), timelineLen) ||
              close(sourceWindow, timelineLen))) {
        // Preview used sourceStart..sourceEnd for this clip.
        c = c.copyWith(trimStart: c.sourceStart, trimEnd: c.sourceEnd);
        changed = true;
      }

      final window = c.trimEnd - c.trimStart;
      final expectedLen = timelineLengthForSource(window, speed);
      if (!close(expectedLen, timelineLen) &&
          window > Duration.zero &&
          close(window, timelineLen)) {
        // Speed was never applied to the clip length; the exporter always
        // rendered window/speed, so adopt that length and shift later clips.
        final diff = expectedLen - timelineLen;
        final oldEnd = c.endTime;
        c = c.copyWith(endTime: c.startTime + expectedLen);
        for (int j = 0; j < clips.length; j++) {
          if (j == i) continue;
          final o = clips[j];
          if (o.startTime >= oldEnd - tolerance) {
            clips[j] = o.copyWith(
                startTime: o.startTime + diff, endTime: o.endTime + diff);
          }
        }
        changed = true;
      }
      clips[i] = c;
    }
    if (!changed) return project;
    return project.copyWith(
      videoClips: clips,
      lastModified: project.lastModified,
    );
  }

  Future<void> loadProject(String projectId) async {
    final project = HiveService.getProject(projectId);
    if (project != null) {
      await _disposeControllers();
      // Use healer to fix paths before loading
      await _healProjectPaths(project);
      _currentProject = normalizeLegacyClipTiming(_currentProject!);

      _undoStack.clear();
      _redoStack.clear();
      _updateTrackCountsFromProject();

      if (_currentProject!.videoClips.isNotEmpty) {
        final firstClip = _currentProject!.videoClips.firstWhere(
            (c) => c.mediaType == MediaType.video && c.videoFile != null,
            orElse: () => _currentProject!.videoClips.first);
        if (firstClip.mediaType == MediaType.video &&
            firstClip.videoFile != null) {
          await _switchActivePreviewController(firstClip.videoFile!.path);
        }
      }

      // Pre-load all audio players for this project
      await _preloadAllAudioPlayers();
      _scheduleTransitionRenders();

      notifyListeners();
    }
  }

  /// Pre-loads all audio players and waveform data when project is loaded
  Future<void> _preloadAllAudioPlayers() async {
    if (_currentProject == null) return;

    for (final overlay in _currentProject!.audioOverlays) {
      if (_audioPlayers.containsKey(overlay.id)) continue;

      try {
        final player = AudioPlayer();
        _audioPlayers[overlay.id] = player;
        await _configureAudioPlayerSource(player, overlay);
        // Set initial volume
        final effectiveVolume =
            (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
        await player.setVolume(effectiveVolume);

        // Pre-cache waveform data
        final waveform = await WaveformService.generateWaveform(
          overlay.audioFile.path,
          samples: 100,
        );
        _waveformCache[overlay.id] = waveform;
      } catch (e) {
        // Skip if failed to load
      }
    }
  }

  /// Gets waveform data for an audio overlay
  Future<List<double>> getWaveformData(String overlayId) async {
    if (_waveformCache.containsKey(overlayId)) {
      return _waveformCache[overlayId]!;
    }

    if (_currentProject == null) {
      return List<double>.filled(80, 0.3);
    }

    try {
      final overlay = _currentProject!.audioOverlays.firstWhere(
        (o) => o.id == overlayId,
      );
      final waveform = await WaveformService.generateWaveform(
        overlay.audioFile.path,
      );
      _waveformCache[overlayId] = waveform;
      return waveform;
    } catch (e) {
      return List<double>.filled(80, 0.3);
    }
  }

  List<VideoProject> getSavedProjects() {
    return HiveService.getAllProjects();
  }

  Future<void> deleteProject(String projectId) async {
    await HiveService.deleteProject(projectId);
    notifyListeners();
  }

  Future<void> _pauseAllAudioPlayers() async {
    if (_audioPlayers.isEmpty) return;
    await Future.wait(_audioPlayers.values.map((player) async {
      try {
        if (player.playing) {
          await player.pause();
        }
      } catch (_) {}
    }));
  }

  Future<void> _syncAudioPlayback({bool force = false}) async {
    if (_currentProject == null) return;
    final nowTs = DateTime.now();
    if (_audioSyncInProgress) {
      if (force) _pendingForcedAudioSync = true;
      return;
    }
    if (!force &&
        nowTs.difference(_lastAudioSync) <
            const Duration(milliseconds: _audioSyncIntervalMs)) {
      return;
    }
    _audioSyncInProgress = true;
    try {
      final now = _currentPosition;
      final overlays = _currentProject!.audioOverlays;

      if (!_isPlaying) {
        // Guarantee all players are paused concurrently when playback is stopped
        await _pauseAllAudioPlayers();

        if (force) {
          await Future.wait(overlays.map((overlay) async {
            final active = now >= overlay.startTime && now < overlay.endTime;
            final player = _audioPlayers[overlay.id];
            if (player == null) return;
            if (!active) {
              if (player.playing) {
                try {
                  await player.pause();
                } catch (_) {}
              }
              return;
            }
            await _configureAudioPlayerSource(player, overlay);
            final elapsed = now - overlay.startTime;
            try {
              final playerDur = player.duration;
              final clampedPos = (playerDur != null && elapsed > playerDur)
                  ? playerDur
                  : (elapsed < Duration.zero ? Duration.zero : elapsed);
              await player.seek(clampedPos);
            } catch (_) {}
          }));
        }
        return;
      }

      // Process all audio overlays concurrently to prevent one player from blocking others
      await Future.wait(overlays.map((overlay) async {
        try {
          final active = now >= overlay.startTime && now < overlay.endTime;
          final id = overlay.id;
          var player = _audioPlayers[id];
          if (player == null) {
            try {
              player = AudioPlayer();
              _audioPlayers[id] = player;
            } catch (e) {
              return;
            }
          }
          await _configureAudioPlayerSource(player, overlay);

          final effectiveOverlayVolume =
              (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
          final lastVol = _lastSetOverlayVolume[id];
          if (lastVol == null ||
              (lastVol - effectiveOverlayVolume).abs() > 0.01) {
            await player.setVolume(effectiveOverlayVolume);
            _lastSetOverlayVolume[id] = effectiveOverlayVolume;
          }

          final elapsedInOverlay = now - overlay.startTime;

          if (active) {
            final playerDur = player.duration;
            if (playerDur != null && elapsedInOverlay >= playerDur) {
              if (player.playing) {
                await player.pause();
              }
              return;
            }

            final clampedPos =
                elapsedInOverlay < Duration.zero ? Duration.zero : elapsedInOverlay;

            const driftTolerance = Duration(milliseconds: 350);
            final pos = player.position;
            final isPlayingNow = player.playing;
            final drift = (pos - clampedPos).abs();

            if (!isPlayingNow || drift > driftTolerance) {
              await player.seek(clampedPos);
              if (_isPlaying) {
                await player.play();
              } else {
                await player.pause();
              }
            }
          } else {
            if (player.playing) {
              await player.pause();
            }
          }
        } catch (e) {
          debugPrint('Error syncing audio overlay ${overlay.id}: $e');
        }
      }));

      final validIds = overlays.map((o) => o.id).toSet();
      for (final entry in _audioPlayers.entries.toList()) {
        if (!validIds.contains(entry.key)) {
          try {
            await entry.value.stop();
            await entry.value.dispose();
          } catch (_) {}
          _audioPlayers.remove(entry.key);
          _lastSetOverlayVolume.remove(entry.key);
          _audioSourceConfigCache.remove(entry.key);
        }
      }
    } catch (e) {
      debugPrint('Error in _syncAudioPlayback: $e');
    } finally {
      _lastAudioSync = DateTime.now();
      _audioSyncInProgress = false;
      if (_pendingForcedAudioSync) {
        _pendingForcedAudioSync = false;
        scheduleMicrotask(() {
          _syncAudioPlayback(force: true);
        });
      }
    }
  }

  // --- CHROMA KEY METHODS ---

  /// Getter for backwards compatibility - shows if chroma key editor is open
  bool get showChromaKeyEditor => _editorPanelMode == EditorPanelMode.chromaKey;

  /// Get chroma key backgrounds available in the project (as file paths)
  List<String> get chromaKeyBackgrounds {
    return _currentProject?.chromaKeyBackgrounds ?? [];
  }

  /// Check if a background path is a video based on extension
  bool isChromaKeyBackgroundVideo(String path) {
    final ext = p.extension(path).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(ext);
  }

  /// Toggle the chroma key editor panel
  void toggleChromaKeyEditor() {
    print('DEBUG PROVIDER: toggleChromaKeyEditor called');
    print('DEBUG PROVIDER: Current _editorPanelMode = $_editorPanelMode');
    if (_editorPanelMode == EditorPanelMode.chromaKey) {
      _editorPanelMode = EditorPanelMode.none;
      print('DEBUG PROVIDER: Set mode to none');
    } else {
      _showStickerPanel = false;
      _editorPanelMode = EditorPanelMode.chromaKey;
      print('DEBUG PROVIDER: Set mode to chromaKey');
      // Initialize current chroma key settings from selected clip
      if (_selectedVideoClipId != null && _currentProject != null) {
        try {
          final clip = _currentProject!.videoClips.firstWhere(
            (c) => c.id == _selectedVideoClipId,
          );
          _currentChromaKeySettings =
              clip.chromaKeySettings ?? ChromaKeySettings.greenScreen();
          print(
              'DEBUG PROVIDER: Initialized settings from clip: $_currentChromaKeySettings');
        } catch (_) {
          _currentChromaKeySettings = ChromaKeySettings.greenScreen();
        }
      } else {
        _currentChromaKeySettings = ChromaKeySettings.greenScreen();
        print(
            'DEBUG PROVIDER: Using default green screen settings (no clip selected)');
      }
    }
    print('DEBUG PROVIDER: Calling notifyListeners');
    notifyListeners();
    print('DEBUG PROVIDER: toggleChromaKeyEditor complete');
  }

  /// Set chroma key background from file (picture or video)
  Future<void> setChromaKeyBackground(File backgroundFile) async {
    if (_currentProject == null) return;

    recordUndo();

    // Copy file to app documents
    final savedFile = await _importFileToAppDocs(backgroundFile);

    // Add to project's chroma key backgrounds (just the path)
    _currentProject = _currentProject!.addChromaKeyBackground(savedFile.path);

    // Update current clip's chroma key settings
    if (_selectedVideoClipId != null) {
      final isVideo = isChromaKeyBackgroundVideo(savedFile.path);
      _currentChromaKeySettings = (_currentChromaKeySettings ??
              ChromaKeySettings.greenScreen())
          .copyWith(backgroundPath: savedFile.path, isBackgroundVideo: isVideo);

      final clipIndex = _currentProject!.videoClips
          .indexWhere((c) => c.id == _selectedVideoClipId);
      if (clipIndex != -1) {
        final clip = _currentProject!.videoClips[clipIndex];
        final updatedClip =
            clip.copyWith(chromaKeySettings: _currentChromaKeySettings);
        _currentProject = _currentProject!
            .updateVideoClip(_selectedVideoClipId!, updatedClip);
      }
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Update chroma key settings (color, similarity, blend, position, scale, HSV range, spill reduction, feather, edge transition, shadow removal, skin protection)
  void updateChromaKeySettings({
    bool? enabled,
    String? backgroundPath,
    bool? isBackgroundVideo,
    Color? keyColor,
    double? similarity,
    double? blend,
    Offset? position,
    double? scale,
    double? hueMin,
    double? hueMax,
    double? saturationMin,
    double? saturationMax,
    double? valueMin,
    double? valueMax,
    double? spillReduction,
    double? edgeFeather,
    double? edgeTransition,
    double? shadowRemoval,
    double? skinProtection,
  }) {
    if (_currentProject == null || _selectedVideoClipId == null) return;

    recordUndo();

    _currentChromaKeySettings =
        (_currentChromaKeySettings ?? ChromaKeySettings.greenScreen()).copyWith(
      enabled: enabled,
      backgroundPath: backgroundPath,
      isBackgroundVideo: isBackgroundVideo,
      keyColor: keyColor,
      similarity: similarity,
      blend: blend,
      position: position,
      scale: scale,
      hueMin: hueMin,
      hueMax: hueMax,
      saturationMin: saturationMin,
      saturationMax: saturationMax,
      valueMin: valueMin,
      valueMax: valueMax,
      spillReduction: spillReduction,
      edgeFeather: edgeFeather,
      edgeTransition: edgeTransition,
      shadowRemoval: shadowRemoval,
      skinProtection: skinProtection,
    );

    // Update the clip's chroma key settings
    final clipIndex = _currentProject!.videoClips
        .indexWhere((c) => c.id == _selectedVideoClipId);
    if (clipIndex != -1) {
      final clip = _currentProject!.videoClips[clipIndex];
      final updatedClip =
          clip.copyWith(chromaKeySettings: _currentChromaKeySettings);
      _currentProject =
          _currentProject!.updateVideoClip(_selectedVideoClipId!, updatedClip);
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Enable or disable chroma key effect
  void toggleChromaKeyEnabled() {
    if (_currentChromaKeySettings == null) return;
    updateChromaKeySettings(enabled: !_currentChromaKeySettings!.enabled);
  }

  /// Reset chroma key to default green screen settings
  void resetChromaKey() {
    if (_currentProject == null || _selectedVideoClipId == null) return;

    recordUndo();

    _currentChromaKeySettings = ChromaKeySettings.greenScreen();

    // Update the clip's chroma key settings
    final clipIndex = _currentProject!.videoClips
        .indexWhere((c) => c.id == _selectedVideoClipId);
    if (clipIndex != -1) {
      final clip = _currentProject!.videoClips[clipIndex];
      final updatedClip =
          clip.copyWith(chromaKeySettings: _currentChromaKeySettings);
      _currentProject =
          _currentProject!.updateVideoClip(_selectedVideoClipId!, updatedClip);
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Remove chroma key background from project
  void removeChromaKeyBackground(String backgroundPath) {
    if (_currentProject == null) return;

    recordUndo();
    _currentProject =
        _currentProject!.removeChromaKeyBackground(backgroundPath);

    // If this was the active background, clear it from current settings
    if (_currentChromaKeySettings?.backgroundPath != null) {
      if (_currentChromaKeySettings!.backgroundPath == backgroundPath) {
        updateChromaKeySettings(backgroundPath: null, isBackgroundVideo: false);
      }
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Get current chroma key background path for preview
  String? get activeChromaKeyBackgroundPath {
    return _currentChromaKeySettings?.backgroundPath;
  }

  // Chroma key processing state
  bool _isChromaKeyProcessing = false;
  double _chromaKeyProcessingProgress = 0.0;
  String? _chromaKeyProcessingError;

  /// Check if chroma key is currently being processed
  bool get isChromaKeyProcessing => _isChromaKeyProcessing;

  /// Get chroma key processing progress (0.0 to 1.0)
  double get chromaKeyProcessingProgress => _chromaKeyProcessingProgress;

  /// Get chroma key processing error message
  String? get chromaKeyProcessingError => _chromaKeyProcessingError;

  /// Apply chroma key effect to the selected clip
  /// This processes the video and replaces the clip with the processed version
  Future<bool> applyChromaKey({Function(double)? onProgress}) async {
    if (_currentProject == null || _selectedVideoClipId == null) {
      _chromaKeyProcessingError = 'No project or clip selected';
      notifyListeners();
      return false;
    }

    final settings = _currentChromaKeySettings;
    if (settings == null ||
        !settings.enabled ||
        settings.backgroundPath == null) {
      _chromaKeyProcessingError = 'Chroma key not configured';
      notifyListeners();
      return false;
    }

    final clipIndex = _currentProject!.videoClips
        .indexWhere((c) => c.id == _selectedVideoClipId);
    if (clipIndex == -1) {
      _chromaKeyProcessingError = 'Clip not found';
      notifyListeners();
      return false;
    }

    final clip = _currentProject!.videoClips[clipIndex];
    if (clip.mediaType != MediaType.video || clip.videoFile == null) {
      _chromaKeyProcessingError = 'Selected clip is not a video';
      notifyListeners();
      return false;
    }

    // Start processing
    _isChromaKeyProcessing = true;
    _chromaKeyProcessingProgress = 0.0;
    _chromaKeyProcessingError = null;
    notifyListeners();

    try {
      final originalVideoPath = clip.videoFile?.path;
      final originalPlaybackPath = _resolvePlaybackPath(clip);
      await _pauseAllPreviewControllers();

      final result = await ChromaKeyService.processClip(
        clip: clip,
        settings: settings,
        onProgress: (progress) {
          _chromaKeyProcessingProgress = progress;
          onProgress?.call(progress);
          notifyListeners();
        },
      );

      if (result.success && result.outputPath != null) {
        // Create a new file in the app documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final newPath = p.join(
          appDir.path,
          'chroma_${_uuid.v4()}_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );

        // Copy the processed file to permanent storage
        await File(result.outputPath!).copy(newPath);

        // Delete the temp file
        try {
          await File(result.outputPath!).delete();
        } catch (_) {}

        // Update the clip with the processed video file
        final processedFile = File(newPath);
        // The processed file contains the clip's source window at 1x speed;
        // playback speed is still applied on top of it (preview and export).
        final processedDuration = clip.trimmedDuration > Duration.zero
            ? clip.trimmedDuration
            : clip.duration;
        final updatedClip = clip.copyWith(
          videoFile: processedFile,
          sourceStart: Duration.zero,
          sourceEnd: processedDuration,
          trimStart: Duration.zero,
          trimEnd: processedDuration,
          endTime: clip.startTime +
              timelineLengthForSource(processedDuration, clip.playbackSpeed),
          isReversed: false,
          clearReversedFilePath: true,
          clearChromaKeySettings: true,
        );

        recordUndo();
        _currentProject = _currentProject!
            .updateVideoClip(_selectedVideoClipId!, updatedClip);

        // Clear the cached preview controller for this path
        if (originalVideoPath != null) {
          await _discardPreviewController(originalVideoPath);
        }
        if (originalPlaybackPath != null &&
            originalPlaybackPath != originalVideoPath) {
          await _discardPreviewController(originalPlaybackPath);
        }
        await _discardPreviewController(newPath);
        _activePreviewClipId = null;

        _isChromaKeyProcessing = false;
        _chromaKeyProcessingProgress = 1.0;
        _scheduleAutoSave();
        notifyListeners();
        return true;
      } else {
        _chromaKeyProcessingError = result.errorMessage ?? 'Processing failed';
        _isChromaKeyProcessing = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _chromaKeyProcessingError = 'Error: $e';
      _isChromaKeyProcessing = false;
      notifyListeners();
      return false;
    }
  }

  /// Cancel chroma key processing
  Future<void> cancelChromaKeyProcessing() async {
    await ChromaKeyService.cancel();
    _isChromaKeyProcessing = false;
    _chromaKeyProcessingProgress = 0.0;
    notifyListeners();
  }

  /// Reorder video clips by moving a clip to a new position
  /// [sourceIndex] is the current index of the clip to move
  /// [targetIndex] is the desired index
  void reorderVideoClips(int sourceIndex, int targetIndex) {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) {
      return;
    }

    // Validate indices
    if (sourceIndex < 0 ||
        sourceIndex >= _currentProject!.videoClips.length ||
        targetIndex < 0 ||
        targetIndex >= _currentProject!.videoClips.length ||
        sourceIndex == targetIndex) {
      return;
    }

    recordUndo();

    // Create a new list and reorder
    final clips = List<VideoClip>.from(_currentProject!.videoClips);
    final movedClip = clips.removeAt(sourceIndex);
    clips.insert(targetIndex, movedClip);

    // Recalculate start and end times based on new order
    Duration currentStartTime = Duration.zero;
    final updatedClips = <VideoClip>[];

    for (final clip in clips) {
      // Preserve the clip's timeline length (what is previewed and exported)
      final clipLength = clip.endTime - clip.startTime;
      final updatedClip = clip.copyWith(
        startTime: currentStartTime,
        endTime: currentStartTime + clipLength,
      );
      updatedClips.add(updatedClip);
      currentStartTime += clipLength;
    }

    _currentProject = _currentProject!.copyWith(
      videoClips: updatedClips,
      lastModified: DateTime.now(),
    );

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Find the target index based on a drop position
  /// Returns the index where the clip should be inserted
  int? getTargetIndexForDropPosition(Duration dropTime) {
    if (_currentProject == null || _currentProject!.videoClips.isEmpty) {
      return null;
    }

    // Find which clip the drop time falls into
    for (int i = 0; i < _currentProject!.videoClips.length; i++) {
      final clip = _currentProject!.videoClips[i];
      if (dropTime >= clip.startTime && dropTime <= clip.endTime) {
        return i;
      }
    }

    // If drop is after all clips, return last index + 1
    if (dropTime > _currentProject!.videoClips.last.endTime) {
      return _currentProject!.videoClips.length;
    }

    return null;
  }

  /// Get the current index of a clip by ID
  int? getClipIndexById(String clipId) {
    if (_currentProject == null) return null;
    try {
      return _currentProject!.videoClips
          .indexWhere((clip) => clip.id == clipId);
    } catch (_) {
      return null;
    }
  }

  /// Overlay clip helpers (separate timeline layer)
  Future<void> addOverlayClip(File mediaFile, {int trackIndex = 0}) async {
    if (_currentProject == null) return;
    try {
      final savedFile = await _importFileToAppDocs(mediaFile);

      final ext = p.extension(savedFile.path).toLowerCase();
      final videoExts = ['.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm'];
      Duration duration = const Duration(seconds: 3);
      MediaType mediaType = MediaType.image;
      File? videoFile;
      File? imageFile;
      double mediaWidth = 1920;
      double mediaHeight = 1080;

      if (videoExts.contains(ext)) {
        mediaType = MediaType.video;
        // Initialize a temporary controller just to read metadata, then dispose
        // immediately. The DraggableMediaOverlay widget creates its own controller
        // for playback — keeping a second one here doubles memory and causes OOM.
        try {
          final controller = VideoPlayerController.file(savedFile);
          await controller.initialize();
          duration = controller.value.duration;
          final rot = controller.value.rotationCorrection;
          if ((rot % 180) != 0) {
            mediaWidth = controller.value.size.height;
            mediaHeight = controller.value.size.width;
          } else {
            mediaWidth = controller.value.size.width;
            mediaHeight = controller.value.size.height;
          }
          await controller.dispose(); // free memory immediately
          videoFile = savedFile;
        } catch (e) {
          videoFile = savedFile;
        }
      } else {
        imageFile = savedFile;
        // Get image dimensions (respecting EXIF orientation)
        try {
          final imgSize = await _readImageDisplaySize(savedFile);
          if (imgSize != null && imgSize.width > 0 && imgSize.height > 0) {
            mediaWidth = imgSize.width;
            mediaHeight = imgSize.height;
          }
        } catch (e) {
          // Fallback to default dimensions if we can't read the image
        }
      }

      Duration nextStart = Duration.zero;
      if (_currentProject != null && _currentProject!.overlayClips.isNotEmpty) {
        for (final c in _currentProject!.overlayClips) {
          if (c.trackIndex == trackIndex && c.endTime > nextStart) {
            nextStart = c.endTime;
          }
        }
      }

      // Calculate initial overlay size that maintains the overlay's true aspect ratio
      // in parent normalized coordinate space:
      // absoluteWidth / absoluteHeight == (overlayWidth * parentWidth) / (overlayHeight * parentHeight) == mediaWidth / mediaHeight.
      final parentWidth = _currentProject?.outputResolution.width ?? 1920.0;
      final parentHeight = _currentProject?.outputResolution.height ?? 1080.0;
      final parentAspectRatio = (parentWidth > 0 && parentHeight > 0)
          ? (parentWidth / parentHeight)
          : (16.0 / 9.0);
      final mediaAspectRatio = (mediaWidth > 0 && mediaHeight > 0)
          ? (mediaWidth / mediaHeight)
          : 1.0;

      // normalizedRatio is the ratio of overlayWidth / overlayHeight in normalized coords [0..1]
      final normalizedRatio = mediaAspectRatio / parentAspectRatio;

      const maxDimensionFraction = 0.45;
      double overlayWidth;
      double overlayHeight;

      if (normalizedRatio >= 1.0) {
        // Overlay is wider than tall relative to canvas
        overlayWidth = maxDimensionFraction;
        overlayHeight = overlayWidth / normalizedRatio;
        if (overlayHeight > maxDimensionFraction) {
          overlayHeight = maxDimensionFraction;
          overlayWidth = overlayHeight * normalizedRatio;
        }
      } else {
        // Overlay is taller than wide relative to canvas (e.g. portrait video/image)
        overlayHeight = maxDimensionFraction;
        overlayWidth = overlayHeight * normalizedRatio;
        if (overlayWidth > maxDimensionFraction) {
          overlayWidth = maxDimensionFraction;
          overlayHeight = overlayWidth / normalizedRatio;
        }
      }

      overlayWidth = overlayWidth.clamp(0.05, 1.0);
      overlayHeight = overlayHeight.clamp(0.05, 1.0);

      final overlayDx =
          ((1.0 - overlayWidth) / 2.0).clamp(0.0, 1.0 - overlayWidth);
      final overlayDy =
          ((1.0 - overlayHeight) / 2.0).clamp(0.0, 1.0 - overlayHeight);

      final clip = VideoClip(
        id: _uuid.v4(),
        mediaType: mediaType,
        videoFile: videoFile,
        imageFile: imageFile,
        startTime: nextStart,
        endTime: nextStart + duration,
        sourceStart: Duration.zero,
        sourceEnd: duration,
        trimStart: Duration.zero,
        trimEnd: duration,
        trackIndex: trackIndex,
        overlayPosition: Offset(overlayDx, overlayDy),
        overlaySize: Size(overlayWidth, overlayHeight),
      );

      if (videoFile != null) {
        try {
          await VideoThumbnailService().extractFirstFrame(videoFile.path);
        } catch (_) {}
      }

      recordUndo();
      _currentProject = _currentProject!.addOverlayClip(clip);
      _scheduleAutoSave();
      notifyListeners();
    } catch (e) {
      // ignore
    }
  }

  void moveOverlayClip(String clipId, Duration newStartTime,
      {int? trackIndex}) {
    if (_currentProject == null) return;
    final clipIndex =
        _currentProject!.overlayClips.indexWhere((clip) => clip.id == clipId);
    if (clipIndex == -1) return;
    final originalClip = _currentProject!.overlayClips[clipIndex];
    final clipDuration = originalClip.endTime - originalClip.startTime;
    Duration desiredStart = newStartTime;
    if (desiredStart < Duration.zero) desiredStart = Duration.zero;

    // Check if there's already a clip in the target track at the same time range
    int finalTrackIndex = trackIndex ?? originalClip.trackIndex;
    bool hasOverlap = _currentProject!.overlayClips
        .where(
            (clip) => clip.id != clipId && clip.trackIndex == finalTrackIndex)
        .any((clip) => _clipsOverlap(clip, desiredStart, clipDuration));

    // If there's an overlap, create a new track
    if (hasOverlap) {
      finalTrackIndex = _findAvailableTrackIndex();
    }

    final updatedClip = originalClip.copyWith(
      startTime: desiredStart,
      endTime: desiredStart + clipDuration,
      trackIndex: finalTrackIndex,
    );
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;
    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Check if two clips overlap in time
  bool _clipsOverlap(
      VideoClip existingClip, Duration newStart, Duration newDuration) {
    final newEnd = newStart + newDuration;
    return !(newEnd <= existingClip.startTime ||
        newStart >= existingClip.endTime);
  }

  /// Find the next available track index
  int _findAvailableTrackIndex() {
    if (_currentProject == null || _currentProject!.overlayClips.isEmpty) {
      return 0;
    }

    // Find the highest track index currently used
    int maxTrackIndex = _currentProject!.overlayClips
        .map((clip) => clip.trackIndex)
        .reduce((a, b) => a > b ? a : b);

    return maxTrackIndex + 1;
  }

  void reorderOverlayClips(int sourceIndex, int targetIndex) {
    if (_currentProject == null || _currentProject!.overlayClips.isEmpty) {
      return;
    }
    if (sourceIndex < 0 ||
        sourceIndex >= _currentProject!.overlayClips.length ||
        targetIndex < 0 ||
        targetIndex >= _currentProject!.overlayClips.length ||
        sourceIndex == targetIndex) {
      return;
    }

    recordUndo();
    final clips = List<VideoClip>.from(_currentProject!.overlayClips);
    final moved = clips.removeAt(sourceIndex);
    clips.insert(targetIndex, moved);

    // Recalculate start/end sequentially
    Duration currentStart = Duration.zero;
    final updated = <VideoClip>[];
    for (final c in clips) {
      final trimmed = c.trimmedDuration;
      final updatedClip =
          c.copyWith(startTime: currentStart, endTime: currentStart + trimmed);
      updated.add(updatedClip);
      currentStart += trimmed;
    }

    _currentProject = _currentProject!.copyWith(overlayClips: updated);
    _scheduleAutoSave();
    notifyListeners();
  }

  int? getOverlayClipIndexById(String clipId) {
    if (_currentProject == null) return null;
    try {
      return _currentProject!.overlayClips.indexWhere((c) => c.id == clipId);
    } catch (_) {
      return null;
    }
  }

  /// Update the overlay clip's position on the screen
  void updateOverlayClipPosition(String clipId, Offset newPosition) {
    if (_currentProject == null) return;
    final clipIndex = getOverlayClipIndexById(clipId);
    if (clipIndex == null || clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final updatedClip = originalClip.copyWith(overlayPosition: newPosition);
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Update the overlay clip's size on the screen
  void updateOverlayClipSize(String clipId, Size newSize) {
    if (_currentProject == null) return;
    final clipIndex = getOverlayClipIndexById(clipId);
    if (clipIndex == null || clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final updatedClip = originalClip.copyWith(overlaySize: newSize);
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Update the overlay clip's opacity
  void updateOverlayClipOpacity(String clipId, double opacity) {
    if (_currentProject == null) return;
    final clipIndex = getOverlayClipIndexById(clipId);
    if (clipIndex == null || clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final updatedClip = originalClip.copyWith(overlayOpacity: opacity);
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Remove an overlay clip from the project
  void removeOverlayClip(String clipId) {
    if (_currentProject == null) return;
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips.removeWhere((clip) => clip.id == clipId);

    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);

    // Deselect the overlay if it was selected
    if (_selectedOverlayClipId == clipId) {
      _selectedOverlayClipId = null;
    }

    _scheduleAutoSave();
    notifyListeners();
  }

  /// Update the overlay clip's volume
  void updateOverlayClipVolume(String clipId, double volume,
      {bool skipUndo = false}) {
    if (_currentProject == null) return;
    final clipIndex = getOverlayClipIndexById(clipId);
    if (clipIndex == null || clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final updatedClip = originalClip.copyWith(volume: volume.clamp(0.0, 2.0));
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    if (!skipUndo) {
      recordUndo();
    }
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Toggle mute for an overlay clip
  void toggleOverlayClipMute(String clipId) {
    if (_currentProject == null) return;
    final clipIndex = getOverlayClipIndexById(clipId);
    if (clipIndex == null || clipIndex == -1) return;

    final originalClip = _currentProject!.overlayClips[clipIndex];
    final updatedClip = originalClip.copyWith(isMuted: !originalClip.isMuted);
    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }
}
