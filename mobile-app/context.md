# Context

This file is a short handoff for future agents working in this repo.

## Repo

- Path: `/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app`
- Flutter app for Android, with plugins including `geolocator`, `sensors_plus`, `flutter_secure_storage`, `shared_preferences`, and `another_telephony`.
- Main device used during setup/testing: Samsung `SM M346B`
- Last known device id: `RZCW7042PFM`

## Environment Notes

- OS: Arch Linux
- WM/compositor: `niri` on Wayland
- Android Studio now works under Wayland after adding a VM option override in:
  - `~/.config/Google/AndroidStudio2025.3.2/studio64.vmoptions`
- The key extra VM option used was:
  - `-Dawt.toolkit.name=WLToolkit`

## Important Build History

### 1. Kotlin/Gradle `.salive` failure from system Flutter

The app originally failed because the Arch-packaged Flutter SDK lives under `/usr/lib/flutter`, and Gradle/Kotlin tried to write session files inside Flutter's read-only bundled Gradle area:

- failure shape: `.../flutter_tools/gradle/.kotlin/sessions/...salive`

Fix applied:

- Project file updated:
  - [`android/gradle.properties`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/android/gradle.properties)
- Global file updated:
  - `~/.gradle/gradle.properties`

Relevant properties:

```properties
kotlin.project.persistent.dir=/tmp/kotlin-gradle-persistent
kotlin.project.persistent.dir.gradle.disableWrite=true
```

The repo also has a project-local Kotlin persistent dir override in `android/gradle.properties`.

### 2. Gradle network timeout

There was a later Maven Central timeout while downloading dependencies, including `fastutil-8.4.0.jar`.

Mitigation added in `~/.gradle/gradle.properties`:

```properties
systemProp.org.gradle.internal.http.connectionTimeout=120000
systemProp.org.gradle.internal.http.socketTimeout=120000
```

### 3. Missing Android SDK packages

The build was then blocked by missing SDK components required by Android/Flutter plugins:

- `build-tools;35.0.0`
- `platforms;android-34`

Those were later installed successfully during `flutter run`. The logs also show `platforms;android-36` and `cmake;3.22.1` getting installed.

## Current Status

`flutter run -d RZCW7042PFM` now builds, installs, and launches successfully.

Last successful path:

- APK built at `build/app/outputs/flutter-apk/app-debug.apk`
- App installed on device
- Dart VM service started successfully

## Current Product State

The app is intentionally still in prototype/demo mode, not cleaned up into a production-style rider app.

Important current product decisions:

- Prototype controls and raw observability were restored rather than removed
- Heartbeat was kept, but reduced from `1s` to `10s`
- Prototype-only tools are now hidden behind a password-gated `god mode`
- Dynamic pricing APIs are now integrated into the dashboard and god mode

## God Mode

Prototype/admin-only surfaces are hidden until god mode is unlocked.

Current implementation:

- Password is read from [`.env`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/.env)
- Current key:
  - `GODMODE_PASSWORD=123`
- `.env` is registered as an asset in [`pubspec.yaml`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/pubspec.yaml)

What god mode currently reveals in [`lib/main.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/main.dart):

- raw telemetry transparency div
- pricing diagnostics block
- ML payload block from demo pricing quote
- terminal log stream
- `Simulate Week` button
- `Disruption Trigger` button

Important bug/history:

- There was a framework assertion after opening god mode:
  - `'framework.dart': Failed assertion: '_dependents.isEmpty'`
- Most likely cause was the password dialog using a `TextEditingController` that was disposed immediately after `showDialog()`
- This was changed to use a local string via `onChanged` instead of a controller

## Dynamic Pricing Integration

Dynamic pricing is now wired into the app; it is no longer purely dependent on the older static-looking dashboard values.

Integrated endpoints:

- `GET /api/v1/pricing/health`
- `GET /api/v1/pricing/r-alert/:city`
- `GET /api/v1/pricing/quote/:userId`
- `POST /api/demo/pricing-quote`

Not directly wired yet:

- `POST /api/v1/pricing/predict`

Reason:

- `pricing/predict` requires the full manual 24-field ML payload
- the app does not currently construct that payload directly on the client
- for the prototype, `POST /api/demo/pricing-quote` is used instead because it safely returns both the pricing result and the generated ML payload

Current pricing behavior in [`lib/main.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/main.dart):

- Reads `user_id` and `user_city` from local preferences
- Calls `pricing/quote` for the user-facing dynamic premium
- Calls `pricing/health` for engine readiness/model metadata
- Calls `pricing/r-alert/:city` for zone/weather multiplier information
- In god mode, also calls `demo/pricing-quote` for diagnostics and ML payload display

Pricing refresh triggers:

- app bootstrap
- successful heartbeat
- simulate week
- disruption trigger
- god mode unlock

User-facing pricing card currently shows:

- final premium
- base premium
- W-risk score
- R-alert multiplier
- discount percentage
- engine ready/pending state
- zone / alert source / confidence

God-mode pricing diagnostics currently show:

- engine status / readiness
- model trained timestamp
- training row count
- drift threshold
- baseline W-risk
- IMD level / max temp
- pricing quote timestamp
- top risk factors
- full ML payload returned by `POST /api/demo/pricing-quote`

## Prior Code Review Findings

These were identified earlier as high-value follow-ups. Some were intentionally not fully cleaned up because the app is still in MVP/prototype mode:

- heartbeat used to run around every second; it has now been changed to `10s`
- the app still does heartbeat POST plus heartbeat status GET
- log updates call `setState()` often and may trigger excessive full-widget rebuilds
- telemetry/sensor-driven UI may rebuild too often
- dashboard still includes debug/admin/demo controls, but now only inside god mode

## Current Technical Caveats

`flutter test test/widget_test.dart` passes.

`flutter analyze` still reports a set of pre-existing / prototype-level issues, mainly:

- deprecated `sensors_plus` stream APIs in [`lib/edge_engine.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/edge_engine.dart)
- deprecated `Geolocator.getCurrentPosition` parameters in [`lib/edge_engine.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/edge_engine.dart)
- deprecated `.withOpacity()` calls in [`lib/main.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/main.dart)
- async `BuildContext` warning on logout path in [`lib/main.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/main.dart)
- unused helper functions like `_tryDecodeJson` and `_regPrettyJson`
- deprecated `DropdownButtonFormField.value` usage in [`lib/registration.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/registration.dart)

These are not the main blocker for demo/testing, but they remain technical debt.

## Current File-Level Notes

[`lib/main.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/main.dart)

- main app shell
- login screen
- dashboard
- god mode
- heartbeat loop
- pricing integration

[`lib/registration.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/registration.dart)

- stores `user_city` in shared prefs during registration
- this city is now used by pricing calls

[`lib/edge_engine.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/lib/edge_engine.dart)

- still publishes live snapshot aggressively for prototype transparency
- still uses older sensor/geolocator APIs flagged by analyzer

[`test/widget_test.dart`](/home/sheikh/Documents/Projects/DEVTrails-Submission/mobile-app/test/widget_test.dart)

- current smoke test is just `app boots smoke test`

## Device / Tooling Notes

- Prefer SDK `adb` over system `adb` if debugging device detection:
  - `/home/sheikh/Android/Sdk/platform-tools/adb`
- A broken system `adb` was previously observed due to a protobuf shared-library mismatch.

## If Starting Fresh

Good first commands:

```bash
flutter devices
flutter run -d RZCW7042PFM
```

If the build regresses, check in this order:

1. device visibility via SDK `adb`
2. `~/.gradle/gradle.properties` still contains the Kotlin persistent-dir workaround
3. required Android SDK packages are installed
4. current error is app/runtime related rather than Gradle/bootstrap related

If pricing looks wrong, check in this order:

1. `user_id` and `user_city` exist in shared prefs
2. `GET /api/v1/pricing/quote/:userId` responds for that user
3. `GET /api/v1/pricing/r-alert/:city` resolves the expected city
4. `GET /api/v1/pricing/health` reports engine ready
5. unlock god mode and inspect the pricing diagnostics + ML payload
