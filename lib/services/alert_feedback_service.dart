import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../services/alert_feedback_service.dart';

class AlertFeedbackService {
  static final AudioPlayer _audioPlayer = AudioPlayer();

  static Future<void> startAlertFeedback() async {
    // Vibration
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(
        pattern: [
          0,
          500,
          300,
          500,
          300,
          500,
        ],
      );
    }

    // Sound
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);

    await _audioPlayer.play(
      AssetSource('sounds/emergency_alert.mp3'),
    );
  }

  static Future<void> stopAlertFeedback() async {
    await Vibration.cancel();
    await _audioPlayer.stop();
  }

  static Future<void> dispose() async {
    await stopAlertFeedback();
    await _audioPlayer.dispose();
  }
}