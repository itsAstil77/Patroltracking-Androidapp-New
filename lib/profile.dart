import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/navigationbar.dart';
import 'package:patroltracking/settings.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String mode;
  final String token;

  const ProfileScreen({
    super.key,
    required this.mode,
    required this.user,
    required this.token,
  });

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  late Map<String, dynamic> fullUserData;
  String profileImage = '';

  @override
  void initState() {
    super.initState();
    _fetchUserDetails(widget.user['userId']);
  }

  Future<void> _fetchUserDetails(String userId) async {
    final url = Uri.parse('http://172.19.9.152:5000/signup/$userId');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final data = jsonResponse['data'];

        setState(() {
          fullUserData = data;
          profileImage = data['imageUrl'] ?? '';
          _loading = false;
        });
      } else {
        _showError("Failed to load profile: ${response.statusCode}");
      }
    } catch (e) {
      _showError("Error fetching profile: $e");
    }
  }

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        profileImage = pickedFile.path;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _getDisplayValue(dynamic value) {
    if (value == null) return "N/A";
    if (value is List) {
      return value.join(", "); 
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) {
            if (widget.mode == "settings") {
              return IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: AppConstants.primaryColor),
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      userdata: widget.user,
                      token: widget.token,
                    ),
                  ),
                ),
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
                onPressed: () => Scaffold.of(context).openDrawer(),
              );
            }
          },
        ),
        title: Text("Profile", style: AppConstants.headingStyle),
      ),
      drawer: CustomDrawer(
        token: widget.token,
        userdata: widget.user,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor:
                          AppConstants.primaryColor.withOpacity(0.1),
                      backgroundImage: profileImage.isNotEmpty
                          ? (profileImage.startsWith('http')
                              ? NetworkImage(profileImage) as ImageProvider
                              : FileImage(File(profileImage)))
                          : null,
                      child: profileImage.isEmpty
                          ? Icon(Icons.person,
                              size: 50, color: AppConstants.primaryColor)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildDisplayField("Name", fullUserData['patrolGuardName']),
                  _buildDisplayField("Email", fullUserData['email']),
                  _buildDisplayField(
                      "Mobile Number", fullUserData['mobileNumber']),
                  _buildDisplayField("User ID", fullUserData['userId']),
                  _buildDisplayField("Department", fullUserData['department']),
                  _buildDisplayField(
                      "Designation", fullUserData['designation']),
                  _buildDisplayField("Location", fullUserData['locationName']),
                  _buildDisplayField("Role", fullUserData['role']),
                  _buildDisplayField(
                      "Active", fullUserData['isActive'] ? 'Yes' : 'No'),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildDisplayField(String label, dynamic value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppConstants.boldPurpleFontStyle),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _getDisplayValue(value),
            style: AppConstants.normalPurpleFontStyle,
          ),
        ),
      ],
    );
  }
}

