// import 'package:flutter/material.dart';
// import 'package:patroltracking/Login/otp.dart';
// import 'package:patroltracking/constants.dart';
// import 'package:patroltracking/services/api_service.dart';

// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});

//   @override
//   _LoginScreenState createState() => _LoginScreenState();
// }

// class _LoginScreenState extends State<LoginScreen> {
//   final _formKey = GlobalKey<FormState>();
//   final TextEditingController _usernameController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();

//   bool _isLoading = false;

//   Future<void> _loginUser() async {
//     setState(() {
//       _isLoading = true;
//     });

//     final result = await ApiService.login(
//       username: _usernameController.text,
//       password: _passwordController.text,
//     );

//     setState(() {
//       _isLoading = false;
//     });

//     final resBody = result['body'];

//     if (result['status'] == 200 && resBody['success'] == true) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(resBody['message'] ?? 'Login successful')),
//       );
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => OtpScreen(username: _usernameController.text),
//         ),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(resBody['message'] ?? 'Login failed')),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       resizeToAvoidBottomInset: false,
//       body: SingleChildScrollView(
//         child: Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Column(
//             children: [
//               const SizedBox(height: 80.0),
//               Text('PATROL TRACKING', style: AppConstants.headingStyle),
//               Text('LOGIN', style: AppConstants.headingStyle),
//               const SizedBox(height: 24.0),
//               Image.asset(AppConstants.loginScreenImage, height: 200.0),
//               const SizedBox(height: 24.0),
//               Form(
//                 key: _formKey,
//                 child: Column(
//                   children: [
//                     TextFormField(
//                       controller: _usernameController,
//                       decoration: InputDecoration(
//                         labelText: 'Username',
//                         border: const OutlineInputBorder(),
//                         labelStyle: AppConstants.normalFontStyle,
//                         hintStyle: AppConstants.normalFontStyle,
//                         errorStyle: AppConstants.errorFontStyle,
//                       ),
//                       validator: (value) => value == null || value.isEmpty
//                           ? 'Enter username'
//                           : null,
//                     ),
//                     const SizedBox(height: 16.0),
//                     TextFormField(
//                       controller: _passwordController,
//                       obscureText: true,
//                       decoration: InputDecoration(
//                         labelText: 'Password',
//                         border: const OutlineInputBorder(),
//                         labelStyle: AppConstants.normalFontStyle,
//                         hintStyle: AppConstants.normalFontStyle,
//                         errorStyle: AppConstants.errorFontStyle,
//                       ),
//                       validator: (value) => value == null || value.isEmpty
//                           ? 'Enter password'
//                           : null,
//                     ),
//                     const SizedBox(height: 8.0),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: TextButton(
//                         onPressed: () {},
//                         child: Text('Forgot Password?',
//                             style: AppConstants.selectedButtonFontStyle),
//                       ),
//                     ),
//                     const SizedBox(height: 16.0),
//                     SizedBox(
//                       width: double.infinity,
//                       child: ElevatedButton(
//                         onPressed: _isLoading
//                             ? null
//                             : () {
//                                 if (_formKey.currentState!.validate()) {
//                                   _loginUser();
//                                 }
//                               },
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: AppConstants.primaryColor,
//                           foregroundColor: AppConstants.fontColorWhite,
//                           padding: const EdgeInsets.symmetric(vertical: 16.0),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12.0),
//                           ),
//                         ),
//                         child: _isLoading
//                             ? const CircularProgressIndicator(
//                                 valueColor:
//                                     AlwaysStoppedAnimation<Color>(Colors.white),
//                               )
//                             : Text('Login',
//                                 style: AppConstants.notSelectedButtonFontStyle),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 40.0),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   @override
//   void dispose() {
//     _usernameController.dispose();
//     _passwordController.dispose();
//     super.dispose();
//   }
// }

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
        const SnackBar(content: Text("Offline login failed. Please try online login.")),
      );
    }
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
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
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