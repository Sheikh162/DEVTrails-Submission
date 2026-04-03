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
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/$endpoint'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(
          otpSent ? {"phone": phone, "otp": otp} : {"phone": phone},
        ),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!otpSent) {
          setState(() {
            otpSent = true;
            isProcessing = false;
          });
        } else {
          final data = jsonDecode(res.body);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', data['user']['id']);
          await prefs.setString('user_name', data['user']['name'] ?? "Rider");
          if (mounted) Navigator.pushReplacementNamed(context, '/main');
        }
      } else {
        setState(() => isProcessing = false);
        _showToast("Auth failed: ${jsonDecode(res.body)['error']}", Colors.red);
      }
    } catch (e) {
      setState(() => isProcessing = false);
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
    _initUserSession();
    _startSensorStreams();
    _startLocationSync();
    Timer.periodic(const Duration(seconds: 30), (t) => _syncHeartbeat());
  }

  Future<void> _initUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id') ?? "";
    userName = prefs.getString('user_name') ?? "Rider";
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse(
          'https://vritti-ps1s.onrender.com/api/v1/user/dashboard/$userId',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          invested = (data['moneyInvested'] ?? 0).toDouble();
          credited = (data['moneyCredited'] ?? 0).toDouble();
          balance = (data['currentBalance'] ?? 0).toDouble();
          incomeBracket = data['incomeBracket'] ?? "Unverified";
          isActivelyFlagged = data['edgeEngine']?['isActivelyFlagged'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Sync Error: $e");
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
    try {
      await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/user/location'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "latitude": pos.latitude,
          "longitude": pos.longitude,
        }),
      );
    } catch (e) {}
  }

  Future<void> _syncHeartbeat() async {
    final result = await EdgeEngine.runInference();
    currentMae = result['maeScore'] ?? 0.0;
    try {
      await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/heartbeat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "accel": {"x": ax, "y": ay, "z": az},
          "gyro": {"x": gx, "y": gy, "z": gz},
          "speed": currentSpeed,
          "maeScore": currentMae,
          "status": result['isSecure'] ? 'VERIFIED' : 'FRAUD_FLAG',
        }),
      );
      _fetchDashboardData(); // Refresh flagging status
    } catch (e) {}
  }

  Future<void> _processOneTouchClaim() async {
    setState(() {
      isClaiming = true;
      claimSteps = [];
    });

    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/claims/one-touch'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId}),
      );
      final data = jsonDecode(res.body);

      setState(() => claimSteps = data['steps'] ?? []);

      if (data['success'] == true) {
        _fetchDashboardData(); // Instantly update balance
        _showToast("₹500 Payout Credited to Gullak!", Colors.green);
      } else {
        _showToast(data['message'] ?? "Claim Rejected", Colors.orange);
      }
    } catch (e) {
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
                  "> ${s['label']}: ${s['status'] == 'pass' ? '✓' : '✗'}\n  ${s['detail']}",
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
