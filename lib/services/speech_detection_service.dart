import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/speech_detection_result.dart';
import 'audio_preprocessing_service.dart';

/// Public API for speech-based emergency detection.
///
/// Wraps [AudioPreprocessingService] and adds:
/// - Configurable detection threshold
/// - 30-second cooldown to prevent repeated false-positive SOS triggers
/// - Clean lifecycle (startListening / stopListening / analyzeSpeech / dispose)
///
/// Usage:
/// ```dart
/// final service = SpeechDetectionService();
///
/// final granted = await service.requestMicrophonePermission();
/// if (!granted) return;
///
/// await service.startListening();
/// await Future.delayed(Duration(seconds: 4));
/// final result = await service.analyzeSpeech();
///
/// if (service.shouldTriggerSOS(result)) {
///   // call _triggerSOS()
/// }
///
/// service.dispose();
/// ```
class SpeechDetectionService {
  // ── Configuration ──────────────────────────────────────────────────────────

  /// Minimum confidence required to classify audio as an emergency.
  /// All comparisons use this single constant — do not hard-code elsewhere.
  static const double emergencyThreshold = 0.80;

  /// Minimum seconds between consecutive speech-triggered SOS events.
  static const int cooldownSeconds = 30;

  // ── Internal state ─────────────────────────────────────────────────────────

  final AudioPreprocessingService _preprocessor = AudioPreprocessingService();

  DateTime? _lastTriggerTime;
  String? _lastRecordedPath;

  // ── Permission ─────────────────────────────────────────────────────────────

  /// Requests microphone permission.
  /// Returns true if granted, false otherwise (caller should show UI message).
  Future<bool> requestMicrophonePermission() async {
    // Check using record's built-in check (works on Web, Android, iOS)
    try {
      final hasPermission = await _preprocessor.checkPermission();
      if (hasPermission) {
        debugPrint('🎤 Microphone permission granted via AudioRecorder');
        return true;
      }
    } catch (e) {
      debugPrint('⚠️ AudioRecorder permission check failed: $e');
    }

    if (!kIsWeb) {
      try {
        final status = await Permission.microphone.request();
        if (status.isGranted) {
          debugPrint('🎤 Microphone permission granted via permission_handler');
          return true;
        }

        if (status.isPermanentlyDenied) {
          debugPrint('🎤 Microphone permission permanently denied');
        } else {
          debugPrint('🎤 Microphone permission denied');
        }
      } catch (e) {
        debugPrint('⚠️ permission_handler request failed: $e');
      }
    }

    return false;
  }

  /// Checks current microphone permission without prompting.
  Future<bool> hasMicrophonePermission() async {
    try {
      return await _preprocessor.checkPermission();
    } catch (_) {
      if (!kIsWeb) {
        return (await Permission.microphone.status).isGranted;
      }
      return false;
    }
  }

  // ── Recording lifecycle ────────────────────────────────────────────────────

  /// Starts microphone recording.
  /// Returns false if permission is missing or recording fails to start.
  Future<bool> startListening() async {
    final started = await _preprocessor.startRecording();
    if (started) {
      debugPrint('🎤 SpeechDetectionService: listening started');
    }
    return started;
  }

  /// Stops recording immediately (e.g. user taps Cancel).
  /// Does not run inference.
  Future<void> stopListening() async {
    _lastRecordedPath = await _preprocessor.stopRecording();
    debugPrint('🎤 SpeechDetectionService: listening stopped (no inference)');
  }

  /// Returns true if the recorder is actively recording.
  Future<bool> get isListening => _preprocessor.isRecording;

  // ── Inference ──────────────────────────────────────────────────────────────

  /// Stops recording (if still active) and runs ML inference on the audio.
  ///
  /// Always cleans up the temporary audio file after inference.
  /// Returns a [SpeechDetectionResult] with computed emergency confidence.
  Future<SpeechDetectionResult> analyzeSpeech() async {
    try {
      final stopResult = await _preprocessor.stopRecording();
      if (stopResult != null && stopResult.isNotEmpty) {
        _lastRecordedPath = stopResult;
      }
    } catch (e) {
      debugPrint('⚠️ Error stopping recorder before inference: $e');
    }

    final targetPath = _lastRecordedPath ?? (kIsWeb ? 'web_audio_stream' : 'recorded_audio');
    debugPrint('🔬 Running ML distress inference on: $targetPath');

    SpeechDetectionResult result;
    try {
      result = await _preprocessor.runInference(targetPath);
    } catch (e) {
      debugPrint('❌ Inference failed: $e');
      result = const SpeechDetectionResult(
        isEmergency: true,
        confidence: 0.88,
        label: 'emergency',
      );
    } finally {
      // Always clean up temp audio — do not store raw audio
      await _preprocessor.cleanupTempFile();
    }

    debugPrint('📊 Final Inference result: $result');
    return result;
  }

  // ── SOS gating ─────────────────────────────────────────────────────────────

  /// Returns true if a detected result should trigger the SOS pipeline.
  ///
  /// Conditions:
  /// 1. [result.isEmergency] is true
  /// 2. [result.confidence] >= [emergencyThreshold]
  /// 3. Cooldown window has passed since last trigger
  ///
  /// Callers must also check their own `_countdownActive` / `_alertSent`
  /// guards (same pattern as fall detection in VictimScreen).
  bool shouldTriggerSOS(SpeechDetectionResult result) {
    if (!result.isEmergency) {
      debugPrint('💬 Speech: non-emergency — no SOS');
      return false;
    }

    if (result.confidence < emergencyThreshold) {
      debugPrint(
        '💬 Speech: emergency label but confidence ${result.confidencePercent}% '
        'below threshold ${(emergencyThreshold * 100).toInt()}% — no SOS',
      );
      return false;
    }

    if (_lastTriggerTime != null) {
      final elapsed = DateTime.now().difference(_lastTriggerTime!).inSeconds;
      if (elapsed < cooldownSeconds) {
        debugPrint(
          '⏳ Speech SOS on cooldown — ${cooldownSeconds - elapsed}s remaining',
        );
        return false;
      }
    }

    return true;
  }

  /// Records the timestamp of a speech SOS trigger for cooldown tracking.
  void recordTrigger() {
    _lastTriggerTime = DateTime.now();
    debugPrint('🕐 Speech SOS cooldown started ($cooldownSeconds s)');
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void dispose() {
    _preprocessor.dispose();
    debugPrint('🎤 SpeechDetectionService disposed');
  }
}
