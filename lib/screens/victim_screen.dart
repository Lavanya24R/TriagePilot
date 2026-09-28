import 'dart:async';

import 'package:flutter/material.dart';

import '../models/speech_detection_result.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/sensor_service.dart';
import '../services/speech_detection_service.dart';

// ── Voice recording state ─────────────────────────────────────────────────────
enum _VoiceState { idle, requestingPermission, listening, analyzing }

class VictimScreen extends StatefulWidget {
  const VictimScreen({super.key});

  @override
  State<VictimScreen> createState() => _VictimScreenState();
}

class _VictimScreenState extends State<VictimScreen>
    with TickerProviderStateMixin {
  // ── Existing services ───────────────────────────────────────────────────────
  late final SensorService _sensorService;
  late final ConnectivityService _connectivityService;

  // ── SOS state ───────────────────────────────────────────────────────────────
  String _alertType = 'manual_sos';
  String _alertMessage = 'Emergency SOS triggered';
  Timer? _countdownTimer;
  int _countdown = 10;
  bool _countdownActive = false;
  bool _alertSent = false;

  // ── Voice Emergency state ───────────────────────────────────────────────────
  final SpeechDetectionService _speechService = SpeechDetectionService();
  _VoiceState _voiceState = _VoiceState.idle;
  SpeechDetectionResult? _lastSpeechResult;
  Timer? _voiceAutoStopTimer;
  Timer? _voiceCountdownTimer;
  int _recordingSecondsLeft = 4;

  // ── Animations ──────────────────────────────────────────────────────────────
  // Pulse animation for the mic circle
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Waveform bar animations (5 bars)
  final List<AnimationController> _waveControllers = [];
  final List<Animation<double>> _waveAnimations = [];

  // ── Existing SOS pipeline (unchanged) ──────────────────────────────────────

  void _triggerSOS() {
    setState(() {
      _countdown = 10;
      _countdownActive = true;
      _alertSent = false;
    });

    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
        });
      } else {
        timer.cancel();

        setState(() {
          _countdown = 0;
          _countdownActive = false;
          _alertSent = true;
        });

        _sendEmergencyAlert();
      }
    });
  }

  void _cancelSOS() {
    _countdownTimer?.cancel();

    setState(() {
      _countdownActive = false;
      _countdown = 10;
    });
  }

  void _handleFallDetected() {
    debugPrint('VictimScreen received fall detection');

    if (_countdownActive || _alertSent) {
      debugPrint('Alert already active. Ignoring fall detection.');
      return;
    }
    _alertType = 'fall_detected';
    _alertMessage = 'Possible fall detected';

    _triggerSOS();
  }

  Future<void> _sendEmergencyAlert() async {
    debugPrint('Sending emergency alert...');

    final position = await LocationService.getCurrentLocation();

    double? latitude;
    double? longitude;

    if (position != null) {
      latitude = position.latitude;
      longitude = position.longitude;

      debugPrint('📍 Alert location: $latitude, $longitude');
    } else {
      debugPrint('⚠️ Could not get location');
    }

    final success = await ApiService.sendEmergencyAlert(
      type: _alertType,
      message: _alertMessage,
      latitude: latitude,
      longitude: longitude,
    );

    if (success) {
      debugPrint('Emergency alert sent successfully');

      if (mounted) {
        setState(() {
          _alertSent = true;
        });
      }
    } else {
      debugPrint('Alert stored for retry');
    }
  }

  void _resetAlert() {
    setState(() {
      _alertSent = false;
      _countdown = 10;
      _alertType = 'manual_sos';
      _alertMessage = 'Emergency SOS triggered';
    });
  }

  StateSetter? _sheetStateSetter;
  bool _isSheetOpen = false;

  void _updateVoiceUI() {
    if (mounted) {
      setState(() {});
      _sheetStateSetter?.call(() {});
    }
  }

  // ── Voice Emergency pipeline ────────────────────────────────────────────────

  Future<void> _handleVoiceEmergency() async {
    if (_countdownActive || _alertSent || _voiceState != _VoiceState.idle) {
      return;
    }

    // ── STEP 1: Show bottom sheet immediately (before any async work) ─────────
    _voiceState = _VoiceState.requestingPermission;
    _showVoiceBottomSheet();

    // ── STEP 2: Request permission (sheet is already visible) ─────────────────
    final granted = await _speechService.requestMicrophonePermission();

    if (!granted) {
      _dismissVoiceSheet();
      _voiceState = _VoiceState.idle;
      _updateVoiceUI();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🎤 Microphone permission denied. '
              'Please enable it to use Voice Emergency.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // ── STEP 3: Start recording ───────────────────────────────────────────────
    final started = await _speechService.startListening();

    if (!started) {
      _dismissVoiceSheet();
      _voiceState = _VoiceState.idle;
      _updateVoiceUI();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎤 Could not start microphone. Please try again.'),
          ),
        );
      }
      return;
    }

    _voiceState = _VoiceState.listening;
    _recordingSecondsLeft = 4;
    _lastSpeechResult = null;
    _updateVoiceUI();

    // Start waveform and pulse animations
    _pulseController.repeat(reverse: true);
    for (final c in _waveControllers) {
      c.repeat(reverse: true);
    }

    // Live recording countdown: 4 → 3 → 2 → 1
    _voiceCountdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_recordingSecondsLeft > 1) {
        _recordingSecondsLeft--;
        _updateVoiceUI();
      } else {
        timer.cancel();
        _analyzeVoice();
      }
    });
  }

  /// Cancels recording and closes the sheet.
  Future<void> _cancelVoiceRecording() async {
    _voiceAutoStopTimer?.cancel();
    _voiceCountdownTimer?.cancel();
    await _speechService.stopListening();
    _stopAllAnimations();

    _voiceState = _VoiceState.idle;
    _recordingSecondsLeft = 4;
    _updateVoiceUI();

    _dismissVoiceSheet();
  }

  /// Stops recording and runs inference.
  Future<void> _analyzeVoice() async {
    _voiceAutoStopTimer?.cancel();
    _voiceCountdownTimer?.cancel();
    _stopAllAnimations();

    _voiceState = _VoiceState.analyzing;
    _updateVoiceUI();

    // Run inference (demo fallback or real TFLite)
    final result = await _speechService.analyzeSpeech();

    if (!mounted) return;

    // Close the bottom sheet
    _dismissVoiceSheet();

    _lastSpeechResult = result;
    _voiceState = _VoiceState.idle;
    _recordingSecondsLeft = 4;
    _updateVoiceUI();

    debugPrint('🎤 Speech result: $result');

    // Trigger SOS if threshold met and no active alert
    if (_speechService.shouldTriggerSOS(result) &&
        !_countdownActive &&
        !_alertSent) {
      _speechService.recordTrigger();
      _alertType = 'speech_detected';
      _alertMessage = 'Possible emergency detected from speech';
      _triggerSOS();
    }
  }

  void _dismissVoiceSheet() {
    if (_isSheetOpen && mounted) {
      _isSheetOpen = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ── Bottom sheet (voice UI lives here — always visible above content) ───────

  void _showVoiceBottomSheet() {
    _isSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isDismissible: false, // user must use CANCEL button
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            _sheetStateSetter = setSheetState;
            return _buildVoiceSheet();
          },
        );
      },
    ).then((_) {
      _isSheetOpen = false;
      _sheetStateSetter = null;
      if (_voiceState != _VoiceState.idle) {
        _cancelVoiceRecording();
      }
    });
  }

  Widget _buildVoiceSheet() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1033),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.deepPurple.shade700, width: 1.5),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle look ─────────────────────────────────────────────
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // ── State-specific content ────────────────────────────────────────
              if (_voiceState == _VoiceState.requestingPermission)
                _sheetRequestingPermission()
              else if (_voiceState == _VoiceState.listening)
                _sheetListening()
              else if (_voiceState == _VoiceState.analyzing)
                _sheetAnalyzing()
              else
                _sheetRequestingPermission(), // fallback

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sheet: waiting for permission ─────────────────────────────────────────

  Widget _sheetRequestingPermission() {
    return Column(
      children: [
        const Icon(Icons.mic_none, size: 60, color: Colors.deepPurpleAccent),
        const SizedBox(height: 16),
        const Text(
          'Starting microphone...',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Please grant microphone permission if prompted.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
        const SizedBox(height: 24),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.deepPurpleAccent,
          ),
        ),
      ],
    );
  }

  // ── Sheet: actively recording ─────────────────────────────────────────────

  Widget _sheetListening() {
    return Column(
      children: [
        // Pulsing mic circle
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Colors.deepPurple,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, size: 40, color: Colors.white),
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Listening...',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Speak clearly near the microphone',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),

        const SizedBox(height: 20),

        // ── Animated waveform bars ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_waveAnimations.length, (i) {
            return AnimatedBuilder(
              animation: _waveAnimations[i],
              builder: (context2, child) {
                return Container(
                  width: 6,
                  height: _waveAnimations[i].value,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            );
          }),
        ),

        const SizedBox(height: 20),

        // ── Live countdown circle ───────────────────────────────────────────
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.deepPurple.shade400, width: 3),
          ),
          child: Center(
            child: Text(
              '$_recordingSecondsLeft',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'seconds remaining',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),

        const SizedBox(height: 20),

        OutlinedButton.icon(
          onPressed: _cancelVoiceRecording,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('CANCEL'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white38),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ── Sheet: analyzing ─────────────────────────────────────────────────────

  Widget _sheetAnalyzing() {
    return Column(
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            color: Colors.deepPurpleAccent,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '🎤 Analyzing voice...',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Checking for distress signals in your speech',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'On-device Acoustic Distress ML Model',
          style: TextStyle(color: Colors.deepPurple.shade200, fontSize: 11),
        ),
      ],
    );
  }

  // ── Animations setup ──────────────────────────────────────────────────────

  void _stopAllAnimations() {
    _pulseController.stop();
    _pulseController.reset();
    for (final c in _waveControllers) {
      c.stop();
      c.reset();
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _sensorService = SensorService(onFallDetected: _handleFallDetected);
    _connectivityService = ConnectivityService();

    _sensorService.startListening();
    _connectivityService.startListening();

    // Pulse animation for mic circle
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 5 waveform bar animations with staggered speeds/heights
    final barConfigs = [
      (400, 14.0, 36.0),
      (300, 20.0, 50.0),
      (250, 28.0, 62.0),
      (350, 18.0, 44.0),
      (450, 12.0, 30.0),
    ];

    for (final (ms, minH, maxH) in barConfigs) {
      final controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: ms),
      );
      final animation = Tween<double>(begin: minH, end: maxH).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
      _waveControllers.add(controller);
      _waveAnimations.add(animation);
    }
  }

  @override
  void dispose() {
    _sensorService.stopListening();
    _connectivityService.stopListening();
    _countdownTimer?.cancel();
    _voiceAutoStopTimer?.cancel();
    _voiceCountdownTimer?.cancel();
    _speechService.dispose();
    _pulseController.dispose();
    for (final c in _waveControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Victim Mode')),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_alertSent) {
      return _buildAlertSent();
    }

    if (_countdownActive) {
      return _buildCountdown();
    }

    return _buildSOSScreen();
  }

  // ── SOS screen ────────────────────────────────────────────────────────────

  Widget _buildSOSScreen() {
    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 20),

          const Icon(Icons.warning_rounded, size: 90, color: Colors.redAccent),

          const SizedBox(height: 24),

          const Text(
            'Emergency Assistance',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          Text(
            'Press the button only when you need emergency assistance.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),

          const SizedBox(height: 40),

          // ── Manual SOS ──────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 70,
            child: ElevatedButton.icon(
              onPressed: _triggerSOS,
              icon: const Icon(Icons.sos, size: 30),
              label: const Text(
                'EMERGENCY SOS',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          Text(
            'You will have 10 seconds to cancel.',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),

          const SizedBox(height: 24),

          // ── OR divider ──────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade700)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade700)),
            ],
          ),

          const SizedBox(height: 24),

          // ── Voice Emergency button ───────────────────────────────────────────
          _buildVoiceButton(),

          const SizedBox(height: 24),

          // ── Last result badge ────────────────────────────────────────────────
          if (_lastSpeechResult != null)
            _buildSpeechResultBadge(_lastSpeechResult!),

          const SizedBox(height: 24),

          // ── Test GPS ────────────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: () async {
              final position = await LocationService.getCurrentLocation();

              if (position != null) {
                debugPrint(
                  '📍 TEST LOCATION: '
                  '${position.latitude}, ${position.longitude}',
                );
              }
            },
            icon: const Icon(Icons.location_on),
            label: const Text('TEST GPS'),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildVoiceButton() {
    final bool busy = _voiceState != _VoiceState.idle;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 70,
          child: ElevatedButton.icon(
            // Disable while busy (sheet is already showing)
            onPressed: busy ? null : _handleVoiceEmergency,
            icon: Icon(busy ? Icons.mic : Icons.mic, size: 28),
            label: Text(
              busy ? 'RECORDING...' : 'VOICE EMERGENCY',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  busy ? Colors.deepPurple.shade800 : Colors.deepPurple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.deepPurple.shade800,
              disabledForegroundColor: Colors.white54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Speak a phrase to detect distress in your voice',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildSpeechResultBadge(SpeechDetectionResult result) {
    final isHighConfidenceEmergency = result.isEmergency &&
        result.confidence >= SpeechDetectionService.emergencyThreshold;
    final color =
        isHighConfidenceEmergency ? Colors.redAccent : Colors.green;
    final icon = isHighConfidenceEmergency
        ? Icons.warning_amber_rounded
        : Icons.check_circle;
    final label = isHighConfidenceEmergency
        ? '🚨 Emergency detected'
        : '✅ No emergency detected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Confidence: ${result.confidencePercent}%',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'On-device Acoustic Distress ML Model',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Countdown (unchanged) ─────────────────────────────────────────────────

  Widget _buildCountdown() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          size: 80,
          color: Colors.orangeAccent,
        ),

        const SizedBox(height: 24),

        const Text(
          'ALERT TRIGGERED',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.orangeAccent,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'Emergency alert will be sent in...',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
        ),

        const SizedBox(height: 30),

        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent, width: 6),
          ),
          child: Center(
            child: Text(
              '$_countdown',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ),
        ),

        const SizedBox(height: 40),

        SizedBox(
          width: double.infinity,
          height: 60,
          child: OutlinedButton.icon(
            onPressed: _cancelSOS,
            icon: const Icon(Icons.close),
            label: const Text(
              'CANCEL ALERT',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        Text(
          'Cancel if this was triggered accidentally.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      ],
    );
  }

  // ── Alert sent (unchanged) ────────────────────────────────────────────────

  Widget _buildAlertSent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 100,
          color: Colors.greenAccent,
        ),

        const SizedBox(height: 24),

        const Text(
          'ALERT SENT',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: Colors.greenAccent,
          ),
        ),

        const SizedBox(height: 12),

        Text(
          'Emergency responders have been notified.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
        ),

        const SizedBox(height: 40),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: _resetAlert,
            child: const Text(
              'DONE',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
