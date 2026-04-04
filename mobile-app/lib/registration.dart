import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _regTs() => DateTime.now().toIso8601String();
String _regTimestamp() => DateTime.now().toIso8601String();

dynamic _regTryDecodeJson(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _regPrettyJson(dynamic data) {
  if (data == null) return 'null';
  try {
    return const JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController(text: 'Chennai');
  String _platform = 'Swiggy';
  bool _consentGiven = false;

  bool _otpRequested = false;
  bool _isBusy = false;
  final _codeController = TextEditingController();

  static const _base = 'https://vritti-ps1s.onrender.com';

  void _log(String msg) => debugPrint('[${_regTs()}] [REGISTRATION] $msg');

  Future<void> _requestOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      _toast('Enter valid phone number');
      return;
    }

    setState(() => _isBusy = true);
    final payload = {'phone': phone};
    _log('REQUEST => POST /api/v1/auth/request-otp payload=$payload');

    try {
      final res = await http.post(
        Uri.parse('$_base/api/v1/auth/request-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
    setState(() => isProcessing = true);
    final url = 'https://vritti-ps1s.onrender.com/api/v1/auth/request-otp';
    final payload = {"phone": phone};
    debugPrint("[${_regTimestamp()}] [REG] Request => POST $url");
    debugPrint("[${_regTimestamp()}] [REG] Payload => ${_regPrettyJson(payload)}");

    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final decoded = _regTryDecodeJson(res.body);
      debugPrint(
        "[${_regTimestamp()}] [REG] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_regTimestamp()}] [REG] Response Body <= ${_regPrettyJson(decoded ?? res.body)}",
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');
      if (res.statusCode == 200) {
        setState(() => _otpRequested = true);
        _toast('OTP sent');
      } else {
        _toast('OTP request failed');
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error while requesting OTP');
      debugPrint("[${_regTimestamp()}] [REG] Exception during request OTP => $e");
      _showToast("Network Error", Colors.red);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyAndSignup() async {
    if (_nameController.text.trim().isEmpty) {
      _toast('Name required');
      return;
    }
    if (!_consentGiven) {
      _toast('Consent is mandatory');
      return;
    }

    final payload = {
      'phone': _phoneController.text.trim(),
      'code': _codeController.text.trim(),
      'name': _nameController.text.trim(),
      'city': _cityController.text.trim(),
      'platform': _platform,
      'consentGiven': true,
    };

    setState(() => _isBusy = true);
    _log('REQUEST => POST /api/v1/auth/verify-otp payload=$payload');
  // STEP 4: Final Verification & Consent
  Future<void> _completeRegistration() async {
    if (name.trim().isEmpty) {
      _showToast("Name is required for Sign Up", Colors.orange);
      return;
    }
    if (otp.trim().isEmpty) {
      _showToast("Please enter OTP", Colors.orange);
      return;
    }
    setState(() => isProcessing = true);
    final url = 'https://vritti-ps1s.onrender.com/api/v1/auth/verify-otp';
    final payload = {
      "phone": phone,
      "otp": otp,
      "name": name.trim(),
      "platform": selectedPlatform,
      "city": workCity,
      "consentGiven": true,
    };
    debugPrint("[${_regTimestamp()}] [REG] Request => POST $url");
    debugPrint("[${_regTimestamp()}] [REG] Payload => ${_regPrettyJson(payload)}");

    try {
      final res = await http.post(
        Uri.parse('$_base/api/v1/auth/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );
      final data = _regTryDecodeJson(res.body);
      debugPrint(
        "[${_regTimestamp()}] [REG] Response <= status=${res.statusCode}",
      );
      debugPrint(
        "[${_regTimestamp()}] [REG] Response Body <= ${_regPrettyJson(data ?? res.body)}",
      );
      _log('RESPONSE <= ${res.statusCode} body=${res.body}');

      if (res.statusCode == 200) {
        final map = jsonDecode(res.body);
        final userId = map['userId'] ?? map['user']?['id'] ?? '';
        final userName = map['name'] ?? map['user']?['name'] ?? 'Rider';

        if (userId.toString().isEmpty) {
          _toast('User ID missing in response');
          return;
        }
        final userData = data ?? jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('user_id', userData['user']['id']);
        await prefs.setString('user_name', userData['user']['name']);
        await prefs.setString('user_phone', phone);
        await prefs.setString('user_city', workCity);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', userId.toString());
        await prefs.setString('user_name', userName.toString());
        await prefs.setString('user_city', _cityController.text.trim());

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/main');
        }
      } else {
        _toast('OTP verification failed');
      }
    } catch (e) {
      _log('EXCEPTION => $e');
      _toast('Network error while verifying OTP');
        final err = (data is Map<String, dynamic>) ? data['error'] : null;
        _showToast(
          err?.toString() ?? "Invalid OTP or Registration Failed",
          Colors.red,
        );
      }
    } catch (e) {
      debugPrint(
        "[${_regTimestamp()}] [REG] Exception during complete registration => $e",
      );
      _showToast("Connection failed", Colors.red);
    } finally {
      setState(() => _isBusy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Sign Up for Vritti',
            style: GoogleFonts.outfit(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Iconsax.user)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Iconsax.mobile)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cityController,
            decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Iconsax.location)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _platform,
            items: const ['Swiggy', 'Zomato', 'Uber']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _platform = v ?? _platform),
            decoration: const InputDecoration(
              labelText: 'Platform',
              prefixIcon: Icon(Iconsax.briefcase),
            ),
          ),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _consentGiven,
            title: const Text('I consent to background telemetry for payout verification'),
            onChanged: (v) => setState(() => _consentGiven = v ?? false),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isBusy ? null : _requestOtp,
            child: Text(_otpRequested ? 'Resend OTP' : 'Request OTP'),
          ),
          if (_otpRequested) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP Code',
                prefixIcon: Icon(Iconsax.password_check),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _isBusy ? null : _verifyAndSignup,
              child: Text(_isBusy ? 'Please wait...' : 'Verify OTP & Continue'),
            ),
          ],
        ],
      ),
    );
  }
}
