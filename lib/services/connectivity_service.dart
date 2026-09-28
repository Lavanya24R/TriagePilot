import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'offline_queue_service.dart';

class ConnectivityService {
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  void startListening() {
    _subscription = Connectivity()
        .onConnectivityChanged
        .listen((results) async {
      print('📶 Connectivity changed: $results');

      final hasConnection =
          results.any((result) => result != ConnectivityResult.none);

      if (hasConnection) {
        print('🌐 Network available — checking offline queue...');

        await OfflineQueueService.retryPendingAlerts();
      } else {
        print('📴 Device is offline');
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }
}