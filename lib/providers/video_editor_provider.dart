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

  Timer? _timelineTimer;
  DateTime? _playbackStartTime;
  Duration? _playbackStartPosition;

  String? _activeTransitionId;
  DateTime _lastTransitionSeek = DateTime.fromMillisecondsSinceEpoch(0);
  bool _transitionOpInFlight = false;
  final Set<String> _transitionPrewarmInFlight = {};
  final Set<String> _transitionPrewarmedControllerKeys = {};

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

  // Per-clip color filters: key is clipId, value is the filter for that clip
  final Map<String, ColorFilter> _clipColorFilters = {};

  /// Get the per-clip color filter map (read-only access)
  Map<String, ColorFilter> get clipColorFilters =>
      Map.unmodifiable(_clipColorFilters);

  // Track management for multiple overlay and audio tracks
  int _overlayTrackCount = 2;
  int _audioTrackCount = 1;

  int get overlayTrackCount => _overlayTrackCount;
  int get audioTrackCount => _audioTrackCount;

  void _updateTrackCountsFromProject() {
    if (_currentProject == null) {
      _overlayTrackCount = 2;
      _audioTrackCount = 1;
      return;
    }
    
    // Find maximum track index used by existing overlay clips
    int maxOverlayIndex = 1; // Default to 2 tracks (index 0 and 1)
    for (final clip in _currentProject!.overlayClips) {
      if (clip.trackIndex > maxOverlayIndex) {
        maxOverlayIndex = clip.trackIndex;
      }
    }
    _overlayTrackCount = maxOverlayIndex + 1;

    // Find maximum track index used by existing audio overlays
    int maxAudioIndex = 0; // Default to 1 track (index 0)
    for (final audio in _currentProject!.audioOverlays) {
      if (audio.trackIndex > maxAudioIndex) {
        maxAudioIndex = audio.trackIndex;
      }
    }
    _audioTrackCount = maxAudioIndex + 1;
  }

  void addOverlayTrack() {
    _overlayTrackCount++;
    notifyListeners();
  }

  void addAudioTrack() {
    _audioTrackCount++;
    notifyListeners();
  }

  VideoProject? get currentProject => _currentProject;
  VideoEditorController? get videoController => _videoController;
  VideoPlayerController? get previewController => _previewController;
  String? get activeFilePath => _activeFilePath;

  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  bool get isLoading => _isLoading;

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
      final controller = VideoPlayerController.file(
        File(filePath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.setVolume(0.0);
      _previewControllers[filePath] = controller;
      unawaited(_manageControllerMemory(filePath));
    }
    return _previewControllers[filePath];
  }

  Future<void> _pauseAllPreviewControllers({bool mute = true}) async {
    final controllers = <VideoPlayerController>{
      if (_previewController != null) _previewController!,
      ..._previewControllers.values,
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
      // Increase track count if needed
      if (finalTrackIndex >= _audioTrackCount) {
        _audioTrackCount = finalTrackIndex + 1;
      }
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
    final firstSourceEnd = originalClip.sourceStart + firstDuration;
    final firstClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: originalClip.startTime,
      endTime: cutPosition,
      sourceStart: originalClip.sourceStart,
      sourceEnd: firstSourceEnd,
    );
    final secondClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: cutPosition,
      endTime: originalClip.endTime,
      sourceStart: firstSourceEnd,
      sourceEnd: originalClip.sourceEnd,
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

    final oldDuration = originalClip.trimEnd - originalClip.trimStart;
    final newDuration = newTrimEnd - originalClip.trimStart;
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

    final oldDuration = originalClip.trimEnd - originalClip.trimStart;
    final newDuration = endTrim - startTrim;

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
    _overlayTrackCount = 2;
    _audioTrackCount = 1;
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
    _overlayTrackCount = 2;
    _audioTrackCount = 1;
    notifyListeners();
  }

  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _autoSaveProject();
    });
  }

  Future<void> loadVideoFile(File videoFile) async {
    try {
      _isLoading = true;
      notifyListeners();

      var savedFile = await _importFileToAppDocs(videoFile);

      // Validate video codec and re-encode if necessary
      final isCompatible = await _validateVideoCodec(savedFile);
      if (!isCompatible) {
        _exportError =
            'Incompatible video codec. Re-encoding video for compatibility...';
        notifyListeners();

        final reencoded = await _reencodeVideoForCompatibility(savedFile);
        if (reencoded == null) {
          throw Exception(
              'Failed to re-encode video: Device hardware decoder cannot process this video format. Try using a different video file or convert it using H.264 codec.');
        }
        savedFile = reencoded;
      }

      _videoController ??= VideoEditorController.file(
        savedFile,
        minDuration: const Duration(seconds: 1),
        maxDuration: const Duration(minutes: 10),
      );
      if (!_videoController!.initialized) {
        await _videoController!.initialize();
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

      _isLoading = false;
      await _autoSaveProject();
      _scheduleAutoSave();
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      String errorMsg = _parseVideoError(e.toString());
      _exportError = errorMsg;
      notifyListeners();
      rethrow;
    }
  }

  /// Validate if the video codec is compatible with the device
  Future<bool> _validateVideoCodec(File videoFile) async {
    try {
      // Try to initialize the controller with a short timeout
      final testController = VideoPlayerController.file(videoFile);
      await testController.initialize().timeout(
        const Duration(seconds: 5),
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
    if (_isPlaying) {
      _seekSyncSerial++;
      _playbackRecoverySerial++;
      _playbackRecoveryInFlight = false;
      _seekPauseTimer?.cancel();
      _deferredSeekSyncTimer?.cancel();
      await _pauseAllPreviewControllers();
      _isPlaying = false;
      _stopTimelineClock();
      _activePreviewClipId = null;
      _activeTransitionId = null;
      await _pauseAllAudioPlayers();
    } else {
      final serial = ++_seekSyncSerial;
      _seekPauseTimer?.cancel();
      _deferredSeekSyncTimer?.cancel();
      _isPlaying = true;
      var canStartTimeline = true;

      final clip = _clipAtTimeline(_currentPosition);
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
        await _syncAudioPlayback(force: true);
        _startTimelineClock();
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
      final active = now >= overlay.startTime && now < overlay.endTime;
      if (!active) continue;

      var player = _audioPlayers[overlay.id];
      if (player == null) {
        try {
          player = AudioPlayer();
          _audioPlayers[overlay.id] = player;
          await player.setFilePath(overlay.audioFile.path);
        } catch (e) {
          // Skip if failed to load
          continue;
        }
      }

      // Set volume
      final effectiveVolume =
          (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
      await player.setVolume(effectiveVolume);

      // Calculate position and play
      final elapsedInOverlay = now - overlay.startTime;
      final audioPos = overlay.audioStartOffset + elapsedInOverlay;

      await player.seek(audioPos);
      if (!player.playing) {
        await player.play();
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

  @visibleForTesting
  static Duration calculateSourcePositionForTimeline(
    VideoClip clip,
    Duration timelinePosition,
  ) {
    final offsetWithinClip = timelinePosition - clip.startTime;
    if (offsetWithinClip <= Duration.zero) return clip.sourceStart;
    return clip.sourceStart + offsetWithinClip;
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
    VideoClip clip2,
  ) {
    final start = transitionPreviewPrewarmStart(transition, clip1, clip2);
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
    Duration driftTolerance = _videoDriftTolerance,
  }) {
    if (!isPlayingRequested) return false;
    if (!controllerInitialized) return true;

    final drift = (controllerPosition - expectedPosition).abs();
    if (!controllerPlaying && !controllerBuffering) return true;
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
      if (refreshController && Platform.isAndroid) {
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

    final nativePositionAhead = currentNativePosition - target;
    final nativeNearEnd = videoDuration > const Duration(milliseconds: 250) &&
        currentNativePosition >=
            videoDuration - const Duration(milliseconds: 120);
    final targetSafelyBeforeEnd =
        target < videoDuration - const Duration(milliseconds: 250);
    final replayingBackwardOnAndroid = Platform.isAndroid &&
        play &&
        forceSeek &&
        (nativePositionAhead > const Duration(milliseconds: 500) ||
            (nativeNearEnd && targetSafelyBeforeEnd));
    if (replayingBackwardOnAndroid) return false;

    if (forceSeek || driftMs > 120 || !controller.value.isPlaying) {
      await controller.seekTo(target);
    }
    if (isCurrent != null && !isCurrent()) return false;

    await _applyPreviewVolumeForCurrentPosition();
    if (clip.playbackSpeed != controller.value.playbackSpeed) {
      await controller.setPlaybackSpeed(clip.playbackSpeed);
    }
    if (isCurrent != null && !isCurrent()) return false;

    if (!play) return true;

    await controller.play();
    final started = await _waitForControllerPlaybackStart(
      controller,
      target,
      isCurrent: isCurrent,
    );
    if (isCurrent != null && !isCurrent()) return false;
    if (!started) return false;

    final value = controller.value;
    if (!value.isInitialized) return false;
    if (!value.isPlaying && !value.isBuffering) return false;

    final postPlayDrift = (value.position - target).inMilliseconds.abs();
    final nearVideoEnd = videoDuration > const Duration(milliseconds: 250) &&
        value.position >= videoDuration - const Duration(milliseconds: 80);
    final targetNearEnd = videoDuration > const Duration(milliseconds: 250) &&
        target >= videoDuration - const Duration(milliseconds: 250);

    if (!value.isBuffering && postPlayDrift > 500) return false;
    if (!value.isBuffering && nearVideoEnd && !targetNearEnd) return false;

    return true;
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
    final delay = resumeWhenSynced
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 16);
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
    final clip = _currentProject!.videoClips.firstWhere((c) => c.id == clipId);
    final updatedClip = clip.copyWith(playbackSpeed: speed);
    recordUndo();
    _currentProject = _currentProject!.updateVideoClip(clipId, updatedClip);

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
      // Increase track count if needed
      if (finalTrackIndex >= _audioTrackCount) {
        _audioTrackCount = finalTrackIndex + 1;
      }
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
          await oldPlayer.dispose();
        } catch (_) {}
      }
      _waveformCache.remove(overlayId);
      _lastSetOverlayVolume.remove(overlayId);
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
    await player?.dispose();
    _waveformCache.remove(overlayId);
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
    unawaited(oldPlayer?.dispose());
    if (_isPlaying) {
      unawaited(_syncAudioPlayback());
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
    final firstSourceEnd = originalClip.sourceStart + firstDuration;
    final firstClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: originalClip.startTime,
      endTime: cutPosition,
      sourceStart: originalClip.sourceStart,
      sourceEnd: firstSourceEnd,
      trimStart: originalClip.trimStart,
      trimEnd: originalClip.trimEnd,
      overlayPosition: originalClip.overlayPosition,
      overlaySize: originalClip.overlaySize,
      overlayOpacity: originalClip.overlayOpacity,
    );
    final secondClip = VideoClip(
      id: _uuid.v4(),
      mediaType: originalClip.mediaType,
      videoFile: originalClip.videoFile,
      imageFile: originalClip.imageFile,
      startTime: cutPosition,
      endTime: originalClip.endTime,
      sourceStart: firstSourceEnd,
      sourceEnd: originalClip.sourceEnd,
      trimStart: originalClip.trimStart,
      trimEnd: originalClip.trimEnd,
      overlayPosition: originalClip.overlayPosition,
      overlaySize: originalClip.overlaySize,
      overlayOpacity: originalClip.overlayOpacity,
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
    String preset = 'veryfast',
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
          notifyListeners();
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
      _exportError = 'Export failed: $e';
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

  /// Applies left trim - keeps only the right portion, deletes left portion
  Future<void> applyLeftTrim(String clipId, Duration trimPosition) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    // The trimPosition is where we want to cut
    // Keep everything from trimPosition to end
    final offsetWithinClip = trimPosition - originalClip.startTime;
    final newSourceStart = originalClip.sourceStart + offsetWithinClip;

    if (newSourceStart >= originalClip.sourceEnd) {
      return; // Can't trim everything
    }

    final updatedClip = originalClip.copyWith(
      startTime: Duration.zero,
      endTime: originalClip.endTime - trimPosition,
      sourceStart: newSourceStart,
      trimStart: Duration.zero,
      trimEnd: originalClip.sourceEnd,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
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

    // The trimPosition is where we want to cut
    // Keep everything from start to trimPosition
    final offsetWithinClip = trimPosition - originalClip.startTime;
    final newSourceEnd = originalClip.sourceStart + offsetWithinClip;

    if (newSourceEnd <= originalClip.sourceStart) {
      return; // Can't trim everything
    }

    final updatedClip = originalClip.copyWith(
      endTime: trimPosition,
      sourceEnd: newSourceEnd,
      trimStart: Duration.zero,
      trimEnd: newSourceEnd,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
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

    // Get the current cursor position
    final cursorPosition = _currentPosition;

    // Calculate the offset within the clip
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    // Calculate new source start (the position in the original video where we want to start)
    final newSourceStart = originalClip.sourceStart + offsetWithinClip;

    // The new timeline start should stay at the original clip's position
    // This keeps the trimmed right portion at the same position in the timeline
    final newTimelineStart = originalClip.startTime;
    final newEndTime =
        originalClip.startTime + (originalClip.endTime - cursorPosition);

    final updatedClip = originalClip.copyWith(
      startTime: newTimelineStart,
      endTime: newEndTime,
      sourceStart: newSourceStart,
      trimStart: Duration.zero,
      trimEnd: originalClip.sourceEnd,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    // Adjust position of subsequent clips if any
    final durationDiff = newEndTime - originalClip.endTime;
    for (int i = clipIndex + 1; i < updatedClips.length; i++) {
      final c = updatedClips[i];
      updatedClips[i] = c.copyWith(
        startTime: c.startTime + durationDiff,
        endTime: c.endTime + durationDiff,
      );
    }

    recordUndo();
    _currentProject = _currentProject!.copyWith(
      videoClips: updatedClips,
      totalDuration: _currentProject!.calculateTotalDuration(),
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

    // Get the current cursor position
    final cursorPosition = _currentPosition;

    // Calculate the offset within the clip
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    // Calculate new source end (the position in the original video where we want to end)
    final newSourceEnd = originalClip.sourceStart + offsetWithinClip;

    final updatedClip = originalClip.copyWith(
      endTime: cursorPosition,
      sourceEnd: newSourceEnd,
      trimStart: Duration.zero,
      trimEnd: newSourceEnd,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.videoClips);
    updatedClips[clipIndex] = updatedClip;

    // Adjust position of subsequent clips if any
    final durationDiff = cursorPosition - originalClip.endTime;
    for (int i = clipIndex + 1; i < updatedClips.length; i++) {
      final c = updatedClips[i];
      updatedClips[i] = c.copyWith(
        startTime: c.startTime + durationDiff,
        endTime: c.endTime + durationDiff,
      );
    }

    recordUndo();
    _currentProject = _currentProject!.copyWith(videoClips: updatedClips);
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

    // Get the current cursor position
    final cursorPosition = _currentPosition;

    // Calculate the offset within the clip
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    // Calculate new source start (the position in the original video where we want to start)
    final newSourceStart = originalClip.sourceStart + offsetWithinClip;

    final updatedClip = originalClip.copyWith(
      startTime: cursorPosition,
      endTime: originalClip.endTime,
      sourceStart: newSourceStart,
      trimStart: Duration.zero,
      trimEnd: originalClip.sourceEnd - newSourceStart,
    );

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

    // Get the current cursor position
    final cursorPosition = _currentPosition;

    // Calculate the offset within the clip
    final offsetWithinClip = cursorPosition - originalClip.startTime;

    // Only proceed if cursor is within this clip
    if (offsetWithinClip <= Duration.zero ||
        offsetWithinClip >= originalClip.duration) {
      return;
    }

    // Calculate new source end (the position in the original video where we want to end)
    final newSourceEnd = originalClip.sourceStart + offsetWithinClip;

    final updatedClip = originalClip.copyWith(
      endTime: cursorPosition,
      sourceEnd: newSourceEnd,
      trimStart: Duration.zero,
      trimEnd: newSourceEnd - originalClip.sourceStart,
    );

    final updatedClips = List<VideoClip>.from(_currentProject!.overlayClips);
    updatedClips[clipIndex] = updatedClip;

    recordUndo();
    _currentProject = _currentProject!.copyWith(overlayClips: updatedClips);
    _scheduleAutoSave();
    notifyListeners();
  }

  /// Applies trim (split) - splits video into two separate clips
  Future<void> applyTrimSplit(
      String clipId, Duration startTrim, Duration endTrim) async {
    if (_currentProject == null) return;

    final clipIndex =
        _currentProject!.videoClips.indexWhere((c) => c.id == clipId);
    if (clipIndex == -1) return;

    final originalClip = _currentProject!.videoClips[clipIndex];

    // Calculate durations
    final firstPartDuration = startTrim - originalClip.startTime;
    final secondPartDuration = originalClip.endTime - endTrim;

    if (firstPartDuration.inMilliseconds < 100 ||
        secondPartDuration.inMilliseconds < 100) {
      return; // Parts too short
    }

    // First clip: from start to startTrim
    final firstClipSourceEnd = originalClip.sourceStart + firstPartDuration;
    final firstClip = originalClip.copyWith(
      id: _uuid.v4(),
      endTime: startTrim,
      sourceEnd: firstClipSourceEnd,
      trimEnd: originalClip.duration! - firstPartDuration,
    );

    // Second clip: from endTrim to end
    final secondClipSourceStart =
        originalClip.sourceStart + (endTrim - originalClip.startTime);
    final secondClip = originalClip.copyWith(
      id: _uuid.v4(),
      startTime: endTrim,
      sourceStart: secondClipSourceStart,
      trimStart: secondClipSourceStart,
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
      toggleTextEditor();
    } else {
      notifyListeners();
    }
  }

  void selectAudioOverlay(String? overlayId) {
    _selectedAudioOverlayId = overlayId;
    if (overlayId != null) {
      toggleAudioEditor();
    } else {
      notifyListeners();
    }
  }

  void selectVideoClip(String? clipId) {
    _selectedVideoClipId = clipId;
    notifyListeners();
  }

  void selectOverlayClip(String? clipId) {
    _selectedOverlayClipId = clipId;
    notifyListeners();
  }

  void selectSticker(String? stickerId) {
    _selectedStickerId = stickerId;
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
    _transitionPrewarmedControllerKeys.clear();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> updateTransition(String transitionId, Transition updated) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.updateTransition(transitionId, updated);
    _transitionPrewarmedControllerKeys.clear();
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> removeTransition(String transitionId) async {
    if (_currentProject == null) return;
    recordUndo();
    _currentProject = _currentProject!.removeTransition(transitionId);
    _transitionPrewarmedControllerKeys.clear();
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
      final offsetWithinClip = _currentPosition - clip.startTime;
      final sourcePosition = clip.sourceStart + offsetWithinClip;
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
    _playbackRecoverySerial++;
    _playbackRecoveryInFlight = false;
    _transitionPrewarmInFlight.clear();
    _transitionPrewarmedControllerKeys.clear();
    _currentPosition = Duration.zero;
    _selectedTextOverlayId = null;
    _selectedAudioOverlayId = null;
    _selectedVideoClipId = null;
  }

  Future<void> _disposeControllers() async {
    _stopTimelineClock();
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
    if (activeTransition != null) {
      final clip2 = _clipById(activeTransition.clipId2);
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
    for (final p in _audioPlayers.values) {
      unawaited(p.pause());
    }

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
        await _prepareAudioForPlayback();
        if (isCurrent()) {
          _startTimelineClock();
        }
      } else {
        _isPlaying = false;
        _activePreviewClipId = null;
        await _pauseAllPreviewControllers();
        for (final p in _audioPlayers.values) {
          await p.pause();
        }
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
      if (!isTransitionPreviewPrewarmAt(now, transition, clip1, clip2)) {
        continue;
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

      final key =
          '${transition.id}|$clip2Path|${clip2.sourceStart.inMilliseconds}';
      if (_transitionPrewarmedControllerKeys.contains(key) ||
          _transitionPrewarmInFlight.contains(key)) {
        continue;
      }

      _transitionPrewarmInFlight.add(key);
      unawaited(_prewarmTransitionController(clip2, clip2Path, key));
    }
  }

  Future<void> _prewarmTransitionController(
    VideoClip clip,
    String videoPath,
    String key,
  ) async {
    try {
      final controller = await ensurePreviewController(videoPath);
      if (controller == null || !controller.value.isInitialized) return;

      await controller.setVolume(0.0);
      final target = clampSourcePositionForVideo(
        clip.sourceStart,
        controller.value.duration,
      );
      if ((controller.value.position - target).abs() >
          const Duration(milliseconds: 40)) {
        await controller.seekTo(target);
      }
      await controller.pause();
      _transitionPrewarmedControllerKeys.add(key);
    } catch (_) {
      // Prewarming is best effort; active playback sync still handles misses.
    } finally {
      _transitionPrewarmInFlight.remove(key);
    }
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
    _scheduleAutoSave();
    notifyListeners();
  }

  Future<void> redo() async {
    if (!canRedo) return;
    if (_currentProject != null) {
      _undoStack.add(_currentProject!);
    }
    _currentProject = _redoStack.removeLast();
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

  Future<void> loadProject(String projectId) async {
    final project = HiveService.getProject(projectId);
    if (project != null) {
      await _disposeControllers();
      // Use healer to fix paths before loading
      await _healProjectPaths(project);

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
        await player.setFilePath(overlay.audioFile.path);
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
            if (!active) return;
            final player = _audioPlayers[overlay.id];
            if (player != null) {
              final elapsed = now - overlay.startTime;
              final audioPos = overlay.audioStartOffset + elapsed;
              try {
                await player.seek(audioPos);
              } catch (_) {}
            }
          }));
        }
        return;
      }

      // Process all audio overlays concurrently to prevent one player from blocking others
      await Future.wait(overlays.map((overlay) async {
        final active = now >= overlay.startTime && now < overlay.endTime;
        final id = overlay.id;
        var player = _audioPlayers[id];
        if (player == null) {
          try {
            player = AudioPlayer();
            _audioPlayers[id] = player;
            await player.setFilePath(overlay.audioFile.path);
          } catch (e) {
            return;
          }
        }

        final effectiveOverlayVolume =
            (overlay.volume * _audioMasterVolume).clamp(0.0, 1.0);
        final lastVol = _lastSetOverlayVolume[id];
        if (lastVol == null ||
            (lastVol - effectiveOverlayVolume).abs() > 0.01) {
          await player.setVolume(effectiveOverlayVolume);
          _lastSetOverlayVolume[id] = effectiveOverlayVolume;
        }

        final elapsedInOverlay = now - overlay.startTime;
        final audioPos = overlay.audioStartOffset + elapsedInOverlay;

        if (active) {
          // Increase tolerance from 20ms to 250ms to prevent continuous re-seeking during normal playback
          const driftTolerance = Duration(milliseconds: 250);
          final pos = player.position;
          final isPlayingNow = player.playing;
          final drift = (pos - audioPos).abs();

          if (!isPlayingNow || drift > driftTolerance) {
            await player.seek(audioPos);
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
      }));

      final validIds = overlays.map((o) => o.id).toSet();
      for (final entry in _audioPlayers.entries.toList()) {
        if (!validIds.contains(entry.key)) {
          try {
            await entry.value.dispose();
          } catch (_) {}
          _audioPlayers.remove(entry.key);
          _lastSetOverlayVolume.remove(entry.key);
        }
      }
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
        final processedDuration = clip.duration > Duration.zero
            ? clip.duration
            : clip.trimmedDuration;
        final updatedClip = clip.copyWith(
          videoFile: processedFile,
          sourceStart: Duration.zero,
          sourceEnd: processedDuration,
          trimStart: Duration.zero,
          trimEnd: processedDuration,
          endTime: clip.startTime + processedDuration,
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
      // Preserve the trimmed duration of the clip
      final trimmedDuration = clip.trimmedDuration;
      final updatedClip = clip.copyWith(
        startTime: currentStartTime,
        endTime: currentStartTime + trimmedDuration,
      );
      updatedClips.add(updatedClip);
      currentStartTime += trimmedDuration;
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
          mediaWidth = controller.value.size.width;
          mediaHeight = controller.value.size.height;
          await controller.dispose(); // free memory immediately
          videoFile = savedFile;
        } catch (e) {
          videoFile = savedFile;
        }
      } else {
        imageFile = savedFile;
        // Get image dimensions
        try {
          final data = await savedFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(data);
          final frame = await codec.getNextFrame();
          mediaWidth = frame.image.width.toDouble();
          mediaHeight = frame.image.height.toDouble();
          frame.image.dispose();
          codec.dispose();
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

      // Calculate initial overlay size that maintains original aspect ratio.
      // Portrait media (tall) → height is primary dimension, width derived.
      // Landscape media (wide) → width is primary dimension, height derived.
      const maxDimensionFraction = 0.5;
      final mediaAspectRatio = mediaWidth / mediaHeight;

      double overlayWidth;
      double overlayHeight;

      if (mediaAspectRatio >= 1.0) {
        // Landscape or square: width is the primary dimension
        overlayWidth = maxDimensionFraction;
        overlayHeight = overlayWidth / mediaAspectRatio;
      } else {
        // Portrait: height is the primary dimension
        overlayHeight = maxDimensionFraction;
        overlayWidth = overlayHeight * mediaAspectRatio;
      }

      // Safety clamp so overlay never exceeds 50% in either dimension
      if (overlayWidth > maxDimensionFraction) {
        overlayWidth = maxDimensionFraction;
        overlayHeight = overlayWidth / mediaAspectRatio;
      }
      if (overlayHeight > maxDimensionFraction) {
        overlayHeight = maxDimensionFraction;
        overlayWidth = overlayHeight * mediaAspectRatio;
      }

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
        overlaySize: Size(overlayWidth, overlayHeight),
      );

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
      // Increase track count if needed
      if (finalTrackIndex >= _overlayTrackCount) {
        _overlayTrackCount = finalTrackIndex + 1;
      }
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
}
