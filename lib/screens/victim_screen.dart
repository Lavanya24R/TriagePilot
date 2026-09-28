import 'dart:async';

import '../services/api_service.dart';
import '../services/sensor_service.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';

import 'package:flutter/material.dart';

class VictimScreen extends StatefulWidget {
  const VictimScreen({super.key});

  @override
  State<VictimScreen> createState() => _VictimScreenState();
}

class _VictimScreenState extends State<VictimScreen> {
  late final SensorService _sensorService;
  late final ConnectivityService _connectivityService;
  String _alertType = 'manual_sos';
  String _alertMessage = 'Emergency SOS triggered';
  Timer? _countdownTimer;
  int _countdown = 10;
  bool _countdownActive = false;
  bool _alertSent = false;

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
    debugPrint('🚨 VictimScreen received fall detection');

    if (_countdownActive || _alertSent) {
      debugPrint('⚠️ Alert already active. Ignoring fall detection.');
      return;
    }
    _alertType = 'fall_detected';
    _alertMessage = 'Possible fall detected';

    _triggerSOS();
  }

  Future<void> _sendEmergencyAlert() async {
    debugPrint('🚨 Sending emergency alert...');

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
      debugPrint('✅ Emergency alert sent successfully');

      if (mounted) {
        setState(() {
          _alertSent = true;
        });
      }
    } else {
      debugPrint('📴 Alert stored for retry');
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

  @override
  void initState() {
    super.initState();

    _sensorService = SensorService(onFallDetected: _handleFallDetected);
    _connectivityService = ConnectivityService();

    _sensorService.startListening();
    _connectivityService.startListening();
  }

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

  @override
  void dispose() {
    _sensorService.stopListening();
    _connectivityService.stopListening();
    _countdownTimer?.cancel();
    super.dispose();
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

  Widget _buildSOSScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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

        const SizedBox(height: 50),

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

        const SizedBox(height: 20),

        Text(
          'You will have 10 seconds to cancel.',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
        const SizedBox(height: 30),

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
      ],
    );
  }

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
