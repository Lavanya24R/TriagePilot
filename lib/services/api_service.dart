import 'dart:convert';

import 'package:http/http.dart' as http;

import 'database_service.dart';

class ApiService {
  static const String baseUrl = 'http://172.16.86.152:8000';

  static Future<void> _saveOfflineAlert({
    required String type,
    required String message,
  }) async {
    await DatabaseService.insertAlert(
      type: type,
      severity: 'high',
      message: message,
    );

    print('📴 Alert queued because network is unavailable');
  }

  static Future<bool> sendEmergencyAlert({
    required String type,
    required String message,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/alert'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': type,
              'severity': 'high',
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 5));

      print('Backend response: ${response.statusCode}');
      print(response.body);

      if (response.statusCode == 200) {
        return true;
      }

      await _saveOfflineAlert(type: type, message: message);

      return false;
    } catch (e) {
      print('⚠️ Network unavailable: $e');

      await _saveOfflineAlert(type: type, message: message);

      return false;
    }
  }
}
