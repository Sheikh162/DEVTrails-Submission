# Flutter Source

Application source for the Vritti rider app.

## Files

- `main.dart` initializes notifications, loads app secrets, starts `EdgeEngine`, declares routes, and contains the login/dashboard experience.
- `registration.dart` handles rider signup, OTP verification, city/platform selection, consent capture, and local persistence of rider metadata.
- `edge_engine.dart` runs the on-device trust layer using accelerometer, gyroscope, GPS, carrier/SIM metadata, and battery temperature data exposed through a MethodChannel.
- `sms_engine.dart` is a currently disabled SMS proof-of-income prototype kept for future integration.

## Edge Trust Layer

`EdgeEngine` publishes live `EdgeSnapshot` values through a `ValueNotifier`. It keeps short rolling buffers of vibration and speed, checks mocked GPS status, and derives a fraud flag from physical movement consistency. Backend heartbeat sync uses this status to decide whether a rider is eligible for one-touch payout evaluation.

## Native Integration

The MethodChannel name is:

```text
vritti/device_info
```

Android native code should return carrier, MCC, MNC, and battery temperature values for richer telemetry. If the channel is unavailable, the app logs the failure and continues with degraded metadata.
