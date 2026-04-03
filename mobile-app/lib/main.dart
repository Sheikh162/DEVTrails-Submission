import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'registration.dart';
import 'edge_engine.dart';
import 'sms_engine.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await EdgeEngine.init();
  } catch (e) {}
  runApp(const VrittiApp());
}

class VrittiApp extends StatelessWidget {
  const VrittiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D32)),
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
        if (!otpSent)
          setState(() {
            otpSent = true;
            isProcessing = false;
          });
        else {
          final data = jsonDecode(res.body);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_id', data['user']['id']);
          await prefs.setString('user_name', data['user']['name'] ?? "Rider");
          if (mounted) Navigator.pushReplacementNamed(context, '/main');
        }
      }
    } catch (e) {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Iconsax.status_up, color: Color(0xFF006D32), size: 80),
            const SizedBox(height: 24),
            Text(
              "Vritti Login",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            TextField(
              onChanged: (v) => phone = v,
              decoration: const InputDecoration(
                hintText: "Phone Number",
                prefixIcon: Icon(Iconsax.mobile),
              ),
            ),
            if (otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => otp = v,
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
                onPressed: _handleAuth,
                child: Text(otpSent ? "Verify" : "Send OTP"),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/registration'),
              child: const Text("New Account"),
            ),
          ],
        ),
      ),
    );
  }
}

class MainNavigationController extends StatefulWidget {
  const MainNavigationController({super.key});
  @override
  State<MainNavigationController> createState() =>
      _MainNavigationControllerState();
}

class _MainNavigationControllerState extends State<MainNavigationController> {
  int _selectedIndex = 1;
  String userId = "",
      userName = "Rider",
      bracket = "Calculating...",
      gps = "Searching...",
      city = "Chennai";
  double balance = 0.0, invested = 0.0, credited = 0.0;
  bool isSecure = true;

  @override
  void initState() {
    super.initState();
    _load();
    _syncLocation();
    Timer.periodic(const Duration(minutes: 5), (t) => _heartbeat());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id') ?? "";
    userName = prefs.getString('user_name') ?? "Rider";
    _refresh();
  }

  Future<void> _refresh() async {
    if (userId.isEmpty) return;
    try {
      final res = await http.get(
        Uri.parse(
          'https://vritti-ps1s.onrender.com/api/v1/user/dashboard/$userId',
        ),
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        setState(() {
          invested = (d['moneyInvested'] ?? 0).toDouble();
          credited = (d['moneyCredited'] ?? 0).toDouble();
          balance = (d['currentBalance'] ?? 0).toDouble();
          bracket = d['incomeBracket'] ?? "Unverified";
        });
      }
    } catch (e) {}
  }

  void _syncLocation() {
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).listen((p) async {
      if (mounted)
        setState(
          () => gps =
              "${p.latitude.toStringAsFixed(2)}, ${p.longitude.toStringAsFixed(2)}",
        );
      try {
        await http.post(
          Uri.parse('https://vritti-ps1s.onrender.com/api/v1/user/location'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "userId": userId,
            "latitude": p.latitude,
            "longitude": p.longitude,
            "city": city,
          }),
        );
      } catch (e) {}
    });
  }

  Future<void> _heartbeat() async {
    bool valid = await EdgeEngine.runInference();
    setState(() => isSecure = valid);
    try {
      await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/heartbeat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "userId": userId,
          "status": valid ? 'VERIFIED' : 'FRAUD_FLAG',
        }),
      );
    } catch (e) {}
  }

  Future<void> invest() async {
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/premium/invest'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"userId": userId, "amount": 200}),
      );
      if (res.statusCode == 200) _refresh();
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      InfoScreen(
        gps: gps,
        city: city,
        isSecure: isSecure,
        onRefresh: _heartbeat,
      ),
      HomeScreen(name: userName, invested: invested, onInvest: invest),
      ProfileScreen(
        name: userName,
        balance: balance,
        payouts: credited,
        bracket: bracket,
      ),
    ];
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: screens[_selectedIndex],
      bottomNavigationBar: _buildNav(),
    );
  }

  Widget _buildNav() => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(40),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _nav(0, Iconsax.security_safe, "Security"),
        _nav(1, Iconsax.home, "Home"),
        _nav(2, Iconsax.user, "Profile"),
      ],
    ),
  );
  Widget _nav(int i, IconData ic, String l) => GestureDetector(
    onTap: () => setState(() => _selectedIndex = i),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _selectedIndex == i
            ? const Color(0xFF006D32)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, color: _selectedIndex == i ? Colors.white : Colors.grey),
          Text(
            l,
            style: TextStyle(
              fontSize: 10,
              color: _selectedIndex == i ? Colors.white : Colors.grey,
            ),
          ),
        ],
      ),
    ),
  );
}

class HomeScreen extends StatelessWidget {
  final String name;
  final double invested;
  final VoidCallback onInvest;
  const HomeScreen({
    super.key,
    required this.name,
    required this.invested,
    required this.onInvest,
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
            Container(
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
                    "TOTAL SAFETY INVESTMENTS",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
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
                    "Active Protection Active",
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: onInvest,
                child: const Text("Purchase Safety SIP (₹200)"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final String name, bracket;
  final double balance, payouts;
  const ProfileScreen({
    super.key,
    required this.name,
    required this.balance,
    required this.payouts,
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
            _box("Balance", "₹${balance.toStringAsFixed(2)}", Iconsax.wallet),
            const SizedBox(height: 12),
            _box(
              "Total Payouts",
              "₹${payouts.toStringAsFixed(2)}",
              Iconsax.receive_square,
            ),
            const SizedBox(height: 12),
            _box("Income Tier", bracket, Iconsax.status_up),
          ],
        ),
      ),
    );
  }

  Widget _box(String l, String v, IconData i) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Row(
      children: [
        Icon(i),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ],
    ),
  );
}

class InfoScreen extends StatelessWidget {
  final String gps, city;
  final bool isSecure;
  final VoidCallback onRefresh;
  const InfoScreen({
    super.key,
    required this.gps,
    required this.city,
    required this.isSecure,
    required this.onRefresh,
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
              "Security Hub",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF006D32),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  Text("GPS: $gps"),
                  const Divider(height: 40),
                  Text("INTEGRITY: ${isSecure ? 'SECURE' : 'FLAGGED'}"),
                ],
              ),
            ),
            const Spacer(),
            _btn("Refresh Integrity", onRefresh),
          ],
        ),
      ),
    );
  }

  Widget _btn(String t, VoidCallback p) => SizedBox(
    width: double.infinity,
    height: 60,
    child: ElevatedButton(
      onPressed: p,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF006D32),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(t),
    ),
  );
}
