# Speech Emergency Classifier Model

This directory is the designated location for the TFLite speech emergency
classification model used by TriagePilot.

## Drop-in Instructions

1. Place your trained model file here:
   ```
   assets/models/speech_emergency_classifier.tflite
   ```

2. Open `lib/services/audio_preprocessing_service.dart` and set:
   ```dart
   const bool _useTflite = true;
   ```

3. Add `tflite_flutter: ^0.10.4` to `pubspec.yaml` (already commented in).

4. Run `flutter pub get` and rebuild.

## Expected Model Interface

- **Input**: Float32 tensor — log-mel spectrogram or MFCC features
  - Recommended shape: `[1, 98, 40]` (98 frames × 40 mel bins for 3-second audio at 16kHz)
- **Output**: Float32 tensor `[1, 2]`
  - Index 0: probability of `non-emergency`
  - Index 1: probability of `emergency`

## Threshold

The detection threshold is set in `lib/services/speech_detection_service.dart`:
```dart
static const double emergencyThreshold = 0.80;
```
Adjust as needed based on your model's precision/recall characteristics.

## Demo Mode

Without a model file present, the app runs a clearly-labeled demo fallback
in `AudioPreprocessingService._runDemoFallback()`. The fallback uses a
seeded RNG (seed = audio file size mod 1000) to simulate stable inference
results for demonstration purposes.
