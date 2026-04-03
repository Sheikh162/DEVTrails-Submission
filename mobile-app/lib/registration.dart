import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});
  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  String name = "";
  String phone = "";
  String otp = "";
  String selectedPlatform = "Swiggy";
  String workCity = "Chennai";

  bool isProcessing = false;
  String statusText = "Verifying...";

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  Future<void> _requestOTP() async {
    if (phone.length < 10) return;
    setState(() {
      isProcessing = true;
      statusText = "Requesting OTP...";
    });
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/request-otp'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      );
      if (res.statusCode == 200) {
        setState(() => isProcessing = false);
        _nextPage();
      }
    } catch (e) {
      setState(() => isProcessing = false);
    }
  }

  Future<void> _verifyAndRegister() async {
    setState(() {
      isProcessing = true;
      statusText = "Creating Global Wallet...";
    });
    try {
      final res = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/verify-otp'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phone,
          "otp": otp,
          "name": name,
          "platform": selectedPlatform,
          "city": workCity,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', data['user']['id']);
        await prefs.setString('user_name', data['user']['name']);
        await prefs.setString('user_phone', phone);
        await prefs.setString('user_city', workCity);
        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      }
    } catch (e) {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBF9),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildStepIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [_step1(), _step2(), _step3()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() => Row(
    children: List.generate(
      3,
      (i) => Expanded(
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _currentStep >= i
                ? const Color(0xFF006D32)
                : Colors.grey[300],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  );

  Widget _step1() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Safety SIP",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 40),
        _field("Full Name", Iconsax.user, (v) => name = v),
        const SizedBox(height: 20),
        _field("Phone Number", Iconsax.mobile, (v) => phone = v),
        const Spacer(),
        _btn(isProcessing ? "Processing..." : "Request OTP", _requestOTP),
      ],
    ),
  );

  Widget _step2() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Verify OTP",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          "Enter the code sent to $phone",
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 40),
        _field("6-digit Code", Iconsax.password_check, (v) => otp = v),
        const Spacer(),
        _btn("Verify Code", _nextPage),
      ],
    ),
  );

  Widget _step3() => Padding(
    padding: const EdgeInsets.all(32.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Work Zone",
          style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 40),
        _drop("Platform", selectedPlatform, [
          "Swiggy",
          "Zomato",
          "Uber Eats",
        ], (v) => setState(() => selectedPlatform = v!)),
        const SizedBox(height: 20),
        _drop("City", workCity, [
          "Chennai",
          "Mumbai",
          "Delhi",
          "Bangalore",
        ], (v) => setState(() => workCity = v!)),
        const Spacer(),
        _btn(
          isProcessing ? "Finalizing..." : "Finish Onboarding",
          _verifyAndRegister,
        ),
      ],
    ),
  );

  Widget _field(String h, IconData i, Function(String) o) => TextField(
    onChanged: o,
    decoration: InputDecoration(
      prefixIcon: Icon(i),
      hintText: h,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
  );
  Widget _drop(String l, String v, List<String> i, Function(String?) o) =>
      DropdownButtonFormField<String>(
        value: v,
        decoration: InputDecoration(
          labelText: l,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        items: i
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: o,
      );
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
