
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:patroltracking/Login/otp.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/patrol/patroldashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true; 

  Future<void> _loginUser() async {
    setState(() => _isLoading = true);

    final result = await ApiService.login(
      username: _usernameController.text,
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    final resBody = result['body'];

    if (result['status'] == 200 && resBody['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('temp_username', _usernameController.text);
      await prefs.setString('temp_password', _passwordController.text);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpScreen(username: _usernameController.text),
        ),
      );
    } else {
      _tryOfflineLogin();
    }
  }

  Future<void> _tryOfflineLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString('saved_username');
    final savedPassword = prefs.getString('saved_password');
    final savedUserData = prefs.getString('saved_user');
    final savedToken = prefs.getString('auth_token');

    if (_usernameController.text == savedUsername &&
        _passwordController.text == savedPassword &&
        savedUserData != null &&
        savedToken != null) {
      final user = jsonDecode(savedUserData);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PatrolDashboardScreen(
            token: savedToken,
            userdata: user,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Invalid Credentials")),
      );
    }
  }

  // Toggle password visibility
  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const SizedBox(height: 100),
            Text('LOGIN', style: AppConstants.headingStyle),
            const SizedBox(height: 20),
            Image.asset(AppConstants.loginScreenImage, height: 200),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword, // Use the variable here
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: _togglePasswordVisibility,
                      ),
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                _loginUser();
                              }
                            },
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : const Text("Login"),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}