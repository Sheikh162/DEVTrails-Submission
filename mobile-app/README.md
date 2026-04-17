# Vritti Mobile App

Flutter client for riders using Vritti. The app handles OTP login/registration, dashboard and demo flows, local notifications, and the edge trust layer that correlates sensor movement with GPS state before sending fraud telemetry to the backend.

## What The App Does

- Signs riders in through the backend OTP endpoints.
- Captures profile details such as city, platform, consent, and name during registration.
- Stores rider identity and preferences with `shared_preferences`.
- Runs `EdgeEngine` on-device using accelerometer, gyroscope, GPS, SIM/carrier metadata, and battery temperature where available.
- Sends API requests to the Vritti backend for auth, dashboard, premium, claims, payouts, and heartbeat flows.
- Shows the hackathon/demo dashboard experience for income protection, risk status, and payout simulation.

## Tech Stack

- Flutter SDK with Dart `^3.11.3`
- Location and sensors: `geolocator`, `sensors_plus`
- Networking: `http`
- Local state: `shared_preferences`, `flutter_secure_storage`
- UI: Material 3, `google_fonts`, `animate_do`, `iconsax_flutter`, `percent_indicator`
- Notifications: `flutter_local_notifications`

## Setup

Install packages:

```bash
flutter pub get
```

The app includes `.env` as an asset. Add local-only values there when needed:

```env
GODMODE_PASSWORD=123
```

Run on a connected device or emulator:

```bash
flutter run
```

Run analysis and tests:

```bash
flutter analyze
flutter test
```

## Backend URL

The current source points to the deployed backend:

```text
https://vritti-ps1s.onrender.com
```

For local testing, update the `_baseUrl` in `lib/main.dart` and `_base` in `lib/registration.dart` to your machine's LAN URL, for example:

```text
http://192.168.x.x:3000
```

Android emulators usually need `http://10.0.2.2:3000` for a backend running on the host machine.

## Project Structure

```text
mobile-app/
|-- lib/
|   |-- main.dart
|   |-- registration.dart
|   |-- edge_engine.dart
|   `-- sms_engine.dart
|-- assets/
|   |-- Vritti.jpeg
|   `-- fraud_detector.tflite
|-- test/
|-- android/
|-- ios/
|-- linux/
|-- macos/
|-- web/
|-- windows/
`-- pubspec.yaml
```

See [lib/README.md](./lib/README.md) for app code responsibilities and [assets/README.md](./assets/README.md) for bundled assets. Platform folders are mostly generated Flutter host projects and should be edited only for native permissions, icons, build config, or MethodChannel integration.
