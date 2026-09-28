/// Result returned by the speech emergency detection pipeline.
class SpeechDetectionResult {
  /// Whether the audio was classified as an emergency/distress situation.
  final bool isEmergency;

  /// Confidence score in range [0.0, 1.0].
  /// e.g. 0.91 = 91% confidence
  final double confidence;

  /// Human-readable label for the predicted class.
  /// e.g. 'emergency' or 'non-emergency'
  final String label;

  const SpeechDetectionResult({
    required this.isEmergency,
    required this.confidence,
    required this.label,
  });

  /// Confidence as a 0–100 integer percentage, for display.
  int get confidencePercent => (confidence * 100).round();

  @override
  String toString() =>
      'SpeechDetectionResult(label: $label, confidence: $confidencePercent%, isEmergency: $isEmergency)';
}
