import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://172.16.86.152:8000';

  static Future<bool> sendEmergencyAlert() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/alert'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'manual_sos',
          'severity': 'high',
          'message': 'Emergency SOS triggered',
        }),
      );

      print('Backend response: ${response.statusCode}');
      print(response.body);

      return response.statusCode == 200;
    } catch (e) {
      print('Failed to send emergency alert: $e');
      return false;
    }
  }
}
