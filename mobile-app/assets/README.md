# Mobile Assets

Bundled assets declared in `pubspec.yaml`.

## Files

- `Vritti.jpeg` is the branded visual asset used by the app UI.
- `fraud_detector.tflite` is an edge fraud model artifact intended for on-device trust checks.

## Notes

`pubspec.yaml` currently declares `.env` and `assets/Vritti.jpeg`. If the TFLite model is used directly by Flutter code, add it under the `flutter.assets` section before loading it at runtime.
