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

  // Form Data
  String name = "";
  String phone = "";
  String selectedPlatform = "Swiggy";
  String workCity = "Chennai";

  bool isProcessing = false;
  String statusText = "Initializing secure wallet...";

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  // --- API CALL: REGISTER DRIVER ---
  Future<void> _completeRegistration() async {
    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please fill all fields")));
      return;
    }

    setState(() {
      isProcessing = true;
      statusText = "Creating Vritti Identity...";
    });

    try {
      final regResponse = await http.post(
        Uri.parse('https://vritti-ps1s.onrender.com/api/v1/auth/register'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": name,
          "phone": phone,
          "platform": selectedPlatform,
          "city": workCity,
        }),
      );

      if (regResponse.statusCode == 200 || regResponse.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', name);
        await prefs.setString('user_phone', phone);
        await prefs.setString('user_platform', selectedPlatform);
        await prefs.setString('user_city', workCity);

        if (mounted) Navigator.pushReplacementNamed(context, '/main');
      } else {
        setState(() {
          isProcessing = false;
          statusText = "Error: Phone already registered?";
        });
      }
    } catch (e) {
      setState(() {
        isProcessing = false;
        statusText = "Network Error. Try again.";
      });
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
                children: [_buildStep1(), _buildStep2(), _buildStep3()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: List.generate(3, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _currentStep >= index
                    ? const Color(0xFF006D32)
                    : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeInDown(
            child: Text(
              "Create your\nSafety Identity",
              style: GoogleFonts.outfit(
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 40),
          _buildTextField("Full Name", Iconsax.user, (val) => name = val),
          const SizedBox(height: 20),
          _buildTextField(
            "Mobile Number",
            Iconsax.mobile,
            (val) => phone = val,
          ),
          const Spacer(),
          _buildPrimaryButton("Continue", _nextPage),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Where do you work?",
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 40),
          _buildDropdown(
            "Platform",
            selectedPlatform,
            ["Swiggy", "Zomato", "Uber Eats"],
            (val) => setState(() => selectedPlatform = val!),
          ),
          const SizedBox(height: 20),
          _buildDropdown("Base City", workCity, [
            "Chennai",
            "Mumbai",
            "Delhi",
            "Bangalore",
          ], (val) => setState(() => workCity = val!)),
          const Spacer(),
          _buildPrimaryButton("Next: Finalize", _nextPage),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Iconsax.shield_tick, size: 80, color: Color(0xFF006D32)),
          const SizedBox(height: 24),
          Text(
            "Verified Onboarding",
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "Your initial wallet will be seeded with ₹12,450 to cover your first parametric policies.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                if (isProcessing)
                  const CircularProgressIndicator(color: Color(0xFF006D32))
                else
                  const Icon(
                    Iconsax.verify,
                    color: Color(0xFF006D32),
                    size: 40,
                  ),
                const SizedBox(height: 12),
                Text(
                  statusText,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          const Spacer(),
          _buildPrimaryButton(
            isProcessing ? "Connecting..." : "Finish & Enter Vritti",
            _completeRegistration,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String hint,
    IconData icon,
    Function(String) onChanged,
  ) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF006D32)),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildPrimaryButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF006D32),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
