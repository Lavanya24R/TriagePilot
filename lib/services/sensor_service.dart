import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SensorService {

  final VoidCallback onFallDetected;
  SensorService({
    required this.onFallDetected,
  });

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  bool _possibleFall = false;
  DateTime? _lowAccelerationTime;

  static const double freeFallThreshold = 3.0;
  static const double impactThreshold = 14.5;

  void startListening() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final x = event.x;
      final y = event.y;
      final z = event.z;

      final magnitude = sqrt(x * x + y * y + z * z);

      print(
        '📱 Acceleration magnitude: '
        '${magnitude.toStringAsFixed(2)} m/s²',
      );

      _detectFall(magnitude);
    });
  }

  void _detectFall(double magnitude) {
    final now = DateTime.now();

    if (magnitude < freeFallThreshold) {
      _possibleFall = true;
      _lowAccelerationTime = now;

      print('⚠️ Possible free-fall detected');

      return;
    }

    if (_possibleFall &&
        magnitude > impactThreshold &&
        _lowAccelerationTime != null) {
      final timeSinceLowAcceleration = now.difference(_lowAccelerationTime!);

      if (timeSinceLowAcceleration.inMilliseconds <= 1000) {
        print('🚨 POSSIBLE FALL DETECTED!');
        onFallDetected();
      }

      _possibleFall = false;
      _lowAccelerationTime = null;
    }
  }

  void stopListening() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }
}
