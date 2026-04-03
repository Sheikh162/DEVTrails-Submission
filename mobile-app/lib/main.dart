import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'registration.dart';
import 'edge_engine.dart';
import 'sms_engine.dart';

String _timestampNow() => DateTime.now().toIso8601String();

dynamic _tryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _prettyJson(dynamic data) {
  if (data == null) return 'null';
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await EdgeEngine.init();
  } catch (e) {
    debugPrint("Edge Engine Initialization failed: $e");
  }
  runApp(const VrittiApp());
}

class VrittiApp extends StatelessWidget {
  const VrittiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vritti',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D32)),
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/main': (context) => const MainNavigationController(),
      },
    );
  }
}

// --- PRODUCTION LOGIN SCREEN ---

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String phone = "";
  String otp = "";
  bool otpSent = false;
  bool isProcessing = false;

  Future<void> _handleAuth() async {
    setState(() => isProcessing = true);
    final endpoint = otpSent ? 'verify-otp' : 'request-otp';
    final payload = otpSent ? {"phone": phone, "otp": otp} : {"phone": phone};
    debugPrint(
      "[${_timestampNow()}] [AUTH] Request => POST /api/v1/auth/$endpoint",
    );
    debugPrint("[${_timestampNow()}] [AUTH] Payload => ${_prettyJson(payload)}");
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/$endpoint'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final decodedBody = _tryDecodeJson(res.body);
      debugPrint(
        "[${_timestampNow()}] [AUTH] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_timestampNow()}] [AUTH] Response Body <= ${_prettyJson(decodedBody ?? res.body)}",
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!otpSent) {
          setState(() {
            otpSent = true;
            isProcessing = false;
          });
        } else {
          final data = decodedBody ?? jsonDecode(res.body);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', data['user']['id']);
          await prefs.setString('user_name', data['user']['name'] ?? "Rider");
          if (mounted) Navigator.pushReplacementNamed(context, '/main');
        }
      } else {
        setState(() => isProcessing = false);
        _showToast(
          "Auth failed: ${(decodedBody is Map ? decodedBody['error'] : null) ?? 'Unknown error'}",
          Colors.red,
        );
      }
    } catch (e) {
      setState(() => isProcessing = false);
      debugPrint("[${_timestampNow()}] [AUTH] Exception => $e");
      _showToast("Network Error", Colors.orange);
    }
  }

  void _showToast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInDown(
              child: const Icon(
                Iconsax.status_up,
                color: Color(0xFF006D32),
                size: 80,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Vritti Sign In",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            TextField(
              onChanged: (v) => phone = v,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: "Phone Number",
                prefixIcon: Icon(Iconsax.mobile),
              ),
            ),
            if (otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => otp = v,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: "Enter OTP",
                  prefixIcon: Icon(Iconsax.password_check),
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: isProcessing ? null : _handleAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF006D32),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  isProcessing
                      ? "Processing..."
                      : (otpSent ? "Enter Dashboard" : "Send OTP"),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/registration'),
              child: const Text(
                "New to Vritti? Create Account",
                style: TextStyle(color: Color(0xFF006D32)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- MAIN NAVIGATION CONTROLLER ---

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});
  @override
  State<MainNavigationController> createState() =>
      _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  int _selectedIndex = 1;
  Timer? _heartbeatTimer;

  // Persistent State
  String userId = "";
  String userName = "Rider";
  double balance = 0.0;
  double invested = 0.0;
  double credited = 0.0;
  String incomeBracket = "Calculating...";

  // Real-time Sensor State
  double ax = 0, ay = 0, az = 0;
  double gx = 0, gy = 0, gz = 0;
  double currentSpeed = 0;
  double currentMae = 0;
  bool isActivelyFlagged = false;
  String gpsData = "Scanning...";

  // Disruption Terminal State
  List<dynamic> claimSteps = [];
  bool isClaiming = false;

  @override
  void initState() {
    super.initState();
    debugPrint("[${_timestampNow()}] [APP] MainNavigationController initialized.");
    _initUserSession();
    _startSensorStreams();
    _startLocationSync();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (t) => _syncHeartbeat(),
    );
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _initUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id') ?? "";
    userName = prefs.getString('user_name') ?? "Rider";
    debugPrint(
      "[${_timestampNow()}] [SESSION] Loaded userId=$userId, userName=$userName",
    );
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    if (userId.isEmpty) return;
    final url = 'https://vritti-ps1s.onrender.com/api/v1/user/dashboard/$userId';
    try {
      debugPrint("[${_timestampNow()}] [DASHBOARD] Request => GET $url");
      final res = await http.get(
        Uri.parse(url),
      );
      final decoded = _tryDecodeJson(res.body);
      debugPrint(
        "[${_timestampNow()}] [DASHBOARD] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_timestampNow()}] [DASHBOARD] Response Body <= ${_prettyJson(decoded ?? res.body)}",
      );
      if (res.statusCode == 200) {
        final data = decoded ?? jsonDecode(res.body);
        setState(() {
          invested = (data['moneyInvested'] ?? 0).toDouble();
          credited = (data['moneyCredited'] ?? 0).toDouble();
          balance = (data['currentBalance'] ?? 0).toDouble();
          incomeBracket = data['incomeBracket'] ?? "Unverified";
          isActivelyFlagged = data['edgeEngine']?['isActivelyFlagged'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("[${_timestampNow()}] [DASHBOARD] Exception => $e");
    }
  }

  Future<void> _refreshUserProfile() async {
    if (userId.isEmpty) return;
    final profileEndpoints = [
      'https://vritti-ps1s.onrender.com/api/v1/user/profile/$userId',
      'https://vritti-ps1s.onrender.com/api/v1/auth/profile/$userId',
    ];
    for (final url in profileEndpoints) {
      try {
        debugPrint("[${_timestampNow()}] [PROFILE] Request => GET $url");
        final res = await http.get(Uri.parse(url));
        final decoded = _tryDecodeJson(res.body);
        debugPrint(
          "[${_timestampNow()}] [PROFILE] Response <= status=${res.statusCode}",
        );
        debugPrint(
          "[${_timestampNow()}] [PROFILE] Response Body <= ${_prettyJson(decoded ?? res.body)}",
        );
        if (res.statusCode == 200 && decoded is Map<String, dynamic>) {
          setState(() {
            userName = decoded['name'] ?? userName;
            balance = (decoded['currentBalance'] ?? balance).toDouble();
          });
          return;
        }
      } catch (e) {
        debugPrint("[${_timestampNow()}] [PROFILE] Exception ($url) => $e");
      }
    }
  }

  void _startSensorStreams() {
    userAccelerometerEvents.listen(
      (event) => setState(() {
        ax = event.x;
        ay = event.y;
        az = event.z;
      }),
    );
    gyroscopeEvents.listen(
      (event) => setState(() {
        gx = event.x;
        gy = event.y;
        gz = event.z;
      }),
    );
  }

  void _startLocationSync() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((pos) {
      if (mounted) {
        setState(() {
          gpsData =
              "${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}";
          currentSpeed = pos.speed * 3.6; // km/h
        });
        _syncLocationToBackend(pos);
      }
    });
  }

  Future<void> _syncLocationToBackend(Position pos) async {
    if (userId.isEmpty) return;
    final url = 'https://vritti-ps1s.onrender.com/api/v1/user/location';
    final payload = {
      "userId": userId,
      "latitude": pos.latitude,
      "longitude": pos.longitude,
    };
    try {
      debugPrint("[${_timestampNow()}] [LOCATION] Request => POST $url");
      debugPrint(
        "[${_timestampNow()}] [LOCATION] Payload => ${_prettyJson(payload)}",
      );
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      debugPrint(
        "[${_timestampNow()}] [LOCATION] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_timestampNow()}] [LOCATION] Response Body <= ${_prettyJson(_tryDecodeJson(res.body) ?? res.body)}",
      );
    } catch (e) {}
  }

  Future<void> _syncHeartbeat() async {
    if (userId.isEmpty) return;
    final result = await EdgeEngine.runInference();
    setState(() => currentMae = (result['maeScore'] ?? 0.0).toDouble());
    final heartbeatPayload = {
      "userId": userId,
      "accelX": ax,
      "accelY": ay,
      "accelZ": az,
      "gyroX": gx,
      "gyroY": gy,
      "gyroZ": gz,
      "speed": currentSpeed,
      "maeScore": currentMae,
      "status": result['isSecure'] ? 'NORMAL' : 'FLAGGED',
    };
    final heartbeatEndpoints = [
      'https://vritti-ps1s.onrender.com/api/v1/user/heartbeat',
      'https://vritti-ps1s.onrender.com/api/heartbeat',
    ];

    for (final endpoint in heartbeatEndpoints) {
      try {
        debugPrint("[${_timestampNow()}] [HEARTBEAT] Request => POST $endpoint");
        debugPrint(
          "[${_timestampNow()}] [HEARTBEAT] Payload => ${_prettyJson(heartbeatPayload)}",
        );
        final res = await http.post(
          Uri.parse(endpoint),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(heartbeatPayload),
        );
        debugPrint(
          "[${_timestampNow()}] [HEARTBEAT] Response <= status=${res.statusCode}",
        );
        debugPrint(
          "[${_timestampNow()}] [HEARTBEAT] Response Body <= ${_prettyJson(_tryDecodeJson(res.body) ?? res.body)}",
        );
        if (res.statusCode == 200 || res.statusCode == 201) {
          _fetchDashboardData();
          break;
        }
      } catch (e) {
        debugPrint(
          "[${_timestampNow()}] [HEARTBEAT] Exception ($endpoint) => $e",
        );
      }
    }
  }

  Future<void> _processOneTouchClaim() async {
    if (userId.isEmpty) {
      _showToast("Please login again.", Colors.orange);
      return;
    }

    setState(() {
      isClaiming = true;
      claimSteps = [];
    });

    final url = 'https://vritti-ps1s.onrender.com/api/v1/claims/one-touch';
    final payload = {"userId": userId};

    try {
      debugPrint("[${_timestampNow()}] [CLAIM] Request => POST $url");
      debugPrint("[${_timestampNow()}] [CLAIM] Payload => ${_prettyJson(payload)}");
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final data = _tryDecodeJson(res.body);
      debugPrint(
        "[${_timestampNow()}] [CLAIM] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_timestampNow()}] [CLAIM] Response Body <= ${_prettyJson(data ?? res.body)}",
      );

      if (data is! Map<String, dynamic>) {
        _showToast("Invalid claim response from server", Colors.red);
        return;
      }

      setState(() => claimSteps = data['steps'] ?? []);

      if (data['success'] == true) {
        if (data['newBalance'] != null) {
          setState(() => balance = (data['newBalance']).toDouble());
        } else {
          await _refreshUserProfile();
          _fetchDashboardData();
        }
        _showToast("₹500 Payout Credited to Gullak!", Colors.green);
      } else {
        _showToast(data['message'] ?? "Claim Rejected", Colors.orange);
      }
    } catch (e) {
      debugPrint("[${_timestampNow()}] [CLAIM] Exception => $e");
      _showToast("Claim process failed", Colors.red);
    } finally {
      setState(() => isClaiming = false);
    }
  }

  void _showToast(String m, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: c,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SecurityPanel(
        ax: ax,
        ay: ay,
        az: az,
        gx: gx,
        gy: gy,
        gz: gz,
        speed: currentSpeed,
        mae: currentMae,
        isFlagged: isActivelyFlagged,
        gps: gpsData,
      ),
      HomeScreen(
        name: userName,
        invested: invested,
        isClaiming: isClaiming,
        steps: claimSteps,
        onClaim: _processOneTouchClaim,
      ),
      ProfileScreen(
        name: userName,
        balance: balance,
        credited: credited,
        bracket: incomeBracket,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: screens[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 30),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, Iconsax.security_safe, "Edge AI"),
          _navItem(1, Iconsax.home, "Home"),
          _navItem(2, Iconsax.user, "Gullak"),
        ],
      ),
    );
  }

  Widget _navItem(int i, IconData icon, String label) {
    bool active = _selectedIndex == i;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF006D32) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? Colors.white : Colors.grey, size: 20),
            if (active)
              Text(
                " $label",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET: HOME SCREEN (SOS & TERMINAL) ---

class HomeScreen extends StatelessWidget {
  final String name;
  final double invested;
  final bool isClaiming;
  final List<dynamic> steps;
  final VoidCallback onClaim;

  const HomeScreen({
    super.key,
    required this.name,
    required this.invested,
    required this.isClaiming,
    required this.steps,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Namaste, $name",
              style: GoogleFonts.outfit(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _investedCard(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 80,
              child: ElevatedButton(
                onPressed: isClaiming ? null : onClaim,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5252),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: isClaiming
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "SOS: CLAIM PAYOUT",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            if (steps.isNotEmpty || isClaiming) _TerminalView(steps: steps),
          ],
        ),
      ),
    );
  }

  Widget _investedCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF006D32),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "SAFETY SIP INVESTED",
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          "₹${invested.toStringAsFixed(2)}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Divider(color: Colors.white24, height: 32),
        const Text(
          "Active Zonal Protection Enabled",
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}

// --- WIDGET: TERMINAL LOG VIEW ---

class _TerminalView extends StatelessWidget {
  final List<dynamic> steps;
  const _TerminalView({required this.steps});

  @override
  Widget build(BuildContext context) {
    return FadeInUp(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "VERIFICATION TERMINAL",
              style: TextStyle(
                color: Colors.green,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            if (steps.isEmpty)
              const Text(
                "> Handshaking with Vritti-Core...",
                style: TextStyle(
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ...steps.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  "> [${s['timestamp'] ?? 'NO_TS'}] ${s['label']}: ${s['status'] == 'pass' ? '✓' : '✗'}\n  ${s['detail']}",
                  style: TextStyle(
                    color: s['status'] == 'pass'
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGET: EDGE AI PANEL ---

class SecurityPanel extends StatelessWidget {
  final double ax, ay, az, gx, gy, gz, speed, mae;
  final bool isFlagged;
  final String gps;

  const SecurityPanel({
    super.key,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.speed,
    required this.mae,
    required this.isFlagged,
    required this.gps,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Edge AI Intelligence",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF006D32),
              ),
            ),
            const SizedBox(height: 24),
            _integrityCard(),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "LIVE SENSOR TELEMETRY",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const Divider(),
                      _sensorRow("GPS COORDINATES", gps),
                      _sensorRow(
                        "HARDWARE SPEED",
                        "${speed.toStringAsFixed(1)} KM/H",
                      ),
                      _sensorRow(
                        "ACCEL (X, Y, Z)",
                        "${ax.toStringAsFixed(2)}, ${ay.toStringAsFixed(2)}, ${az.toStringAsFixed(2)}",
                      ),
                      _sensorRow(
                        "GYRO (X, Y, Z)",
                        "${gx.toStringAsFixed(2)}, ${gy.toStringAsFixed(2)}, ${gz.toStringAsFixed(2)}",
                      ),
                      _sensorRow("MAE INERTIAL ERROR", mae.toStringAsFixed(4)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _integrityCard() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: isFlagged ? Colors.red.shade50 : Colors.green.shade50,
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: isFlagged ? Colors.red.shade200 : Colors.green.shade200,
      ),
    ),
    child: Row(
      children: [
        Icon(
          isFlagged ? Iconsax.warning_2 : Iconsax.shield_tick,
          color: isFlagged ? Colors.red : Colors.green,
          size: 40,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFlagged ? "STATUS: FLAGGED" : "STATUS: SECURE",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isFlagged ? Colors.red : Colors.green,
              ),
            ),
            const Text(
              "Hardware Integrity Verified by Edge",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _sensorRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    ),
  );
}

// --- WIDGET: PROFILE (GULLAK) ---

class ProfileScreen extends StatelessWidget {
  final String name, bracket;
  final double balance, credited;

  const ProfileScreen({
    super.key,
    required this.name,
    required this.balance,
    required this.credited,
    required this.bracket,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 50,
              backgroundColor: Color(0xFF006D32),
              child: Icon(Iconsax.user, color: Colors.white, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            _box(
              "GULLAK BALANCE",
              "₹${balance.toStringAsFixed(2)}",
              Iconsax.wallet_1,
            ),
            const SizedBox(height: 12),
            _box(
              "LIFETIME PAYOUTS",
              "₹${credited.toStringAsFixed(2)}",
              Iconsax.receive_square,
            ),
            const SizedBox(height: 12),
            _box("VERIFIED INCOME TIER", bracket, Iconsax.status_up),
            const Spacer(),
            TextButton(
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text(
                "Log Out Account",
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(String l, String v, IconData i) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Row(
      children: [
        Icon(i, color: const Color(0xFF006D32)),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
      ],
    ),
  );
}
