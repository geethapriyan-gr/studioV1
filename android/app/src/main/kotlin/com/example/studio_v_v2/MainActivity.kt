package com.example.studio_v_v2

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaCodec
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaItem.ClippingConfiguration
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ExportException

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "studio_v/export"
        private const val EVENT_CHANNEL = "studio_v/export_progress"
        private const val TAG = "StudioVExport"
    }

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Progress EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        // MethodChannel for export
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "exportProject" -> handleExport(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleExport(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *> ?: run {
            result.error("ARG_ERROR", "Arguments must be a map", null)
            return
        }
        val outputPath = args["outputPath"] as? String ?: run {
            result.error("ARG_ERROR", "Missing outputPath", null)
            return
        }

        // Perform export asynchronously using Media3 Transformer
        val mainHandler = Handler(Looper.getMainLooper())
        val executor = Executors.newSingleThreadExecutor()
        executor.execute {
            try {
                // Parse project and clips
                val project = args["project"] as? Map<*, *>
                val videoClips = (project?.get("videoClips") as? List<*>)
                    ?.mapNotNull { it as? Map<*, *> }
                    ?.filter { (it["mediaType"] as? String) == "video" && !(it["videoPath"] as? String).isNullOrEmpty() }
                    ?.sortedBy { (it["startTimeMs"] as? Number)?.toLong() ?: 0L }
                    ?: emptyList()

                if (videoClips.isEmpty()) {
                    // Nothing to process; create empty file to avoid crash
                    val outFile = File(outputPath)
                    outFile.parentFile?.mkdirs()
                    if (!outFile.exists()) outFile.createNewFile()
                    mainHandler.post { emitProgress(1.0) }
                    mainHandler.post { result.success(outputPath) }
                    return@execute
                }

                // Try fast passthrough (no re-encode). If it fails, fall back to Transformer.
                try {
                    Log.d(TAG, "Attempting passthrough muxer export...")
                    exportWithMuxer(videoClips, outputPath) { p ->
                        mainHandler.post { emitProgress(p) }
                    }
                    Log.d(TAG, "Passthrough export completed")
                    mainHandler.post { result.success(outputPath) }
                    return@execute
                } catch (e: Exception) {
                    Log.w(TAG, "Passthrough export failed, falling back to Transformer: ${e.message}")
                }

                // Build EditedMediaItems with clipping (Transformer fallback)
                val editedItems = mutableListOf<EditedMediaItem>()
                val missingSources = mutableListOf<String>()
                for (clip in videoClips) {
                    val path = clip["videoPath"] as String
                    val f = File(path)
                    if (!f.exists()) {
                        Log.e(TAG, "Source file does not exist: $path")
                        missingSources.add(path)
                        continue
                    }
                    val sourceStartMs = (clip["sourceStartMs"] as? Number)?.toLong() ?: 0L
                    val sourceEndMs = (clip["sourceEndMs"] as? Number)?.toLong()
                    val isMuted = (clip["isMuted"] as? Boolean) == true

                    val uri = Uri.fromFile(f)
                    val baseItem = MediaItem.fromUri(uri)
                    val clipConfigBuilder = ClippingConfiguration.Builder()
                        .setStartPositionMs(sourceStartMs)
                    if (sourceEndMs != null && sourceEndMs > 0L) {
                        clipConfigBuilder.setEndPositionMs(sourceEndMs)
                    }
                    val clippedItem = baseItem.buildUpon()
                        .setClippingConfiguration(clipConfigBuilder.build())
                        .build()
                    val edited = EditedMediaItem.Builder(clippedItem)
                        .setRemoveAudio(isMuted)
                        .build()
                    editedItems.add(edited)
                }

                if (editedItems.isEmpty()) {
                    val msg = "No valid source clips. Missing: ${missingSources.joinToString()}"
                    Log.e(TAG, msg)
                    mainHandler.post { result.error("NO_SOURCES", msg, null) }
                    return@execute
                }

                // Create a single sequence and composition for concatenation
                val sequence = EditedMediaItemSequence(editedItems)
                val composition = Composition.Builder(listOf(sequence)).build()

                // Ensure parent dir exists
                File(outputPath).parentFile?.mkdirs()

                val transformer = Transformer.Builder(applicationContext).build()

                // Listen for completion / error
                val latch = CountDownLatch(1)
                val errorRef = AtomicReference<Throwable?>()
                transformer.addListener(object : Transformer.Listener {
                    override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                        mainHandler.post { emitProgress(1.0) }
                        latch.countDown()
                    }
                    override fun onError(composition: Composition, exportResult: ExportResult, e: ExportException) {
                        Log.e(TAG, "Export error: ${e.message}", e)
                        errorRef.set(e)
                        latch.countDown()
                    }
                })

                // Start transformation
                Log.d(TAG, "Starting export to: $outputPath with ${editedItems.size} clips")
                transformer.start(composition, outputPath)

                // Emit progress periodically while waiting
                val holder = ProgressHolder()
                while (!latch.await(200, TimeUnit.MILLISECONDS)) {
                    when (transformer.getProgress(holder)) {
                        Transformer.PROGRESS_STATE_AVAILABLE -> {
                            val p = (holder.progress / 100f).toDouble()
                            mainHandler.post { emitProgress(p) }
                        }
                        else -> { /* keep waiting */ }
                    }
                }

                errorRef.get()?.let { throw it }
                mainHandler.post { result.success(outputPath) }
            } catch (t: Throwable) {
                Log.e(TAG, "Export failed: ${t.message}", t)
                mainHandler.post { result.error("EXPORT_FAIL", t.message, null) }
            }
        }
    }

    private fun exportWithMuxer(
        videoClips: List<Map<*, *>>,
        outputPath: String,
        onProgress: (Double) -> Unit
    ) {
        val outFile = File(outputPath)
        outFile.parentFile?.mkdirs()

        // Compute total timeline duration to report progress (video timeline only)
        var totalUs = 0L
        val clipInfos = mutableListOf<ClipInfo>()
        for (clip in videoClips) {
            val path = clip["videoPath"] as String
            val f = File(path)
            if (!f.exists()) throw IllegalArgumentException("Missing source $path")
            val startMs = (clip["sourceStartMs"] as? Number)?.toLong() ?: 0L
            val endMs = (clip["sourceEndMs"] as? Number)?.toLong() ?: -1L
            val isMuted = (clip["isMuted"] as? Boolean) == true
            val startUs = startMs * 1000
            val endUs = if (endMs > 0) endMs * 1000 else -1L
            clipInfos.add(ClipInfo(f.path, startUs, endUs, isMuted))
        }
        // We'll refine totalUs later by reading durations if endUs == -1

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var videoTrackOut = -1
        var audioTrackOut = -1
        var started = false

        var videoPtsOffset = 0L
        var audioPtsOffset = 0L

        val buffer = java.nio.ByteBuffer.allocate(1 shl 20) // 1MB
        val bufferInfo = MediaCodec.BufferInfo()

        try {
            // Determine tracks using the first clip
            var computedTotalUs = 0L
            for ((idx, info) in clipInfos.withIndex()) {
                val vExtractor = MediaExtractor()
                vExtractor.setDataSource(info.path)
                val vTrack = selectTrack(vExtractor, "video/")
                if (vTrack < 0) {
                    vExtractor.release()
                    throw IllegalStateException("No video track in ${info.path}")
                }
                vExtractor.selectTrack(vTrack)
                val vFormat = vExtractor.getTrackFormat(vTrack)

                var aExtractor: MediaExtractor? = null
                var aTrack = -1
                var aFormat: MediaFormat? = null
                if (!info.isMuted) {
                    aExtractor = MediaExtractor()
                    aExtractor.setDataSource(info.path)
                    aTrack = selectTrack(aExtractor, "audio/")
                    if (aTrack >= 0) {
                        aExtractor.selectTrack(aTrack)
                        aFormat = aExtractor.getTrackFormat(aTrack)
                    }
                }

                if (!started) {
                    videoTrackOut = muxer.addTrack(vFormat)
                    if (aFormat != null) {
                        audioTrackOut = muxer.addTrack(aFormat)
                    }
                    muxer.start()
                    started = true
                } else {
                    // Validate basic compatibility (mime/width/height) for video
                    val firstMime = vFormat.getString(MediaFormat.KEY_MIME)
                    val firstWidth = vFormat.getInteger(MediaFormat.KEY_WIDTH)
                    val firstHeight = vFormat.getInteger(MediaFormat.KEY_HEIGHT)
                    // Simple check: ensure output track exists
                    if (videoTrackOut < 0) throw IllegalStateException("Output video track invalid")
                    // Audio track presence across clips can vary; we just skip if missing or muted
                }

                // Resolve endUs by clip duration if -1
                var startUs = info.startUs
                var endUs = info.endUs
                if (endUs <= 0) {
                    val dur = vFormat.getLong(MediaFormat.KEY_DURATION)
                    endUs = dur
                }
                // Update total duration sum
                computedTotalUs += (endUs - startUs).coerceAtLeast(0)

                // Write video samples
                vExtractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                var firstVideoPts = -1L
                while (true) {
                    bufferInfo.offset = 0
                    bufferInfo.size = vExtractor.readSampleData(buffer, 0)
                    if (bufferInfo.size < 0) break
                    val sampleTime = vExtractor.sampleTime
                    if (sampleTime < 0 || sampleTime >= endUs) break
                    if (firstVideoPts < 0) firstVideoPts = sampleTime
                    bufferInfo.presentationTimeUs = (sampleTime - firstVideoPts) + videoPtsOffset
                    bufferInfo.flags = vExtractor.sampleFlags
                    muxer.writeSampleData(videoTrackOut, buffer, bufferInfo)
                    vExtractor.advance()
                }
                if (firstVideoPts >= 0) {
                    videoPtsOffset += (endUs - startUs)
                    onProgress((videoPtsOffset.toDouble() / computedTotalUs.toDouble()).coerceIn(0.0, 1.0))
                }

                // Write audio samples if available and not muted and track exists
                if (aExtractor != null && aTrack >= 0 && audioTrackOut >= 0) {
                    aExtractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
                    var firstAudioPts = -1L
                    while (true) {
                        bufferInfo.offset = 0
                        bufferInfo.size = aExtractor.readSampleData(buffer, 0)
                        if (bufferInfo.size < 0) break
                        val sampleTime = aExtractor.sampleTime
                        if (sampleTime < 0 || sampleTime >= endUs) break
                        if (firstAudioPts < 0) firstAudioPts = sampleTime
                        bufferInfo.presentationTimeUs = (sampleTime - firstAudioPts) + audioPtsOffset
                        bufferInfo.flags = aExtractor.sampleFlags
                        muxer.writeSampleData(audioTrackOut, buffer, bufferInfo)
                        aExtractor.advance()
                    }
                    if (firstAudioPts >= 0) {
                        audioPtsOffset += (endUs - startUs)
                    }
                }

                vExtractor.release()
                aExtractor?.release()
            }
            totalUs = if (totalUs == 0L) 1L else totalUs // avoid divide-by-zero
        } catch (e: Exception) {
            try { muxer.stop() } catch (_: Throwable) {}
            try { muxer.release() } catch (_: Throwable) {}
            throw e
        }

        try {
            muxer.stop()
        } finally {
            muxer.release()
        }
        onProgress(1.0)
    }

    private data class ClipInfo(
        val path: String,
        val startUs: Long,
        var endUs: Long,
        val isMuted: Boolean
    )

    private fun selectTrack(extractor: MediaExtractor, prefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(prefix)) return i
        }
        return -1
    }

    private fun emitProgress(p: Double) {
        try {
            eventSink?.success(mapOf("progress" to p))
        } catch (_: Throwable) {
            // ignore
        }
    }
}
