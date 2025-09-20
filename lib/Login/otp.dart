import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:patroltracking/patrol/patroldashboard.dart';
import 'package:patroltracking/services/api_service.dart';

class OtpScreen extends StatefulWidget {
  final String username;
  const OtpScreen({super.key, required this.username});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpControllers = List.generate(4, (index) => TextEditingController());
  final _focusNodes = List.generate(4, (index) => FocusNode());
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _verifyOtp() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      final otp = _otpControllers.map((e) => e.text).join();

      final result = await ApiService.verifyOtp(
        username: widget.username,
        otp: otp,
      );

      setState(() => _isLoading = false);
      final response = result['body'];

      if (result['status'] == 200 && response['success'] == true) {
        final token = response['token'];
        final user = response['user'];

        final prefs = await SharedPreferences.getInstance();
        final tempUsername = prefs.getString('temp_username');
        final tempPassword = prefs.getString('temp_password');

        await prefs.setString('auth_token', token);
        await prefs.setString(
            'saved_username', tempUsername ?? widget.username);
        await prefs.setString('saved_password', tempPassword ?? '');
        await prefs.setString('saved_user', jsonEncode(user));

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PatrolDashboardScreen(
              token: token,
              userdata: user,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'OTP Failed')),
        );
      }
    }
  }

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 65,
      height: 65,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              _otpControllers[index].text.isEmpty &&
              index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _otpControllers[index].text.isNotEmpty
                ? Theme.of(context).primaryColor.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              if (_focusNodes[index].hasFocus)
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.25),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
            ],
            border: Border.all(
              width: 2,
              color: _focusNodes[index].hasFocus
                  ? Theme.of(context).primaryColor
                  : Colors.grey.shade400,
            ),
          ),
          child: Center(
            child: TextFormField(
              controller: _otpControllers[index],
              focusNode: _focusNodes[index],
              textAlign: TextAlign.center,
              maxLength: 1,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? '!' : null,
              onChanged: (val) {
                if (val.isNotEmpty && index < 3) {
                  FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OTP Verification")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              "Enter the 4-digit OTP",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) => _buildOtpBox(index)),
              ),
            ),
            const SizedBox(height: 32),
            _isLoading
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Verify OTP",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}

