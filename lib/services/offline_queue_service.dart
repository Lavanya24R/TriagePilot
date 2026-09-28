import 'api_service.dart';
import 'database_service.dart';

class OfflineQueueService {
  static Future<void> retryPendingAlerts() async {
    final alerts = await DatabaseService.getPendingAlerts();

    if (alerts.isEmpty) {
      print('📭 No pending alerts');
      return;
    }

    print('🔄 Found ${alerts.length} pending alert(s)');

    for (final alert in alerts) {
      final id = alert['id'] as int;

      final success = await ApiService.sendEmergencyAlert(
        type: alert['type'] as String,
        message: alert['message'] as String,
      );

      if (success) {
        await DatabaseService.deleteAlert(id);

        print('✅ Pending alert $id sent successfully');
        print('🗑️ Removed alert $id from offline queue');
      } else {
        print('⏳ Alert $id still cannot be sent');
      }
    }
  }
}