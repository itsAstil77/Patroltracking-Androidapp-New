import 'package:flutter/material.dart';
import 'package:patroltracking/Login/login.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/patrol/PatrolIncident.dart';
import 'package:patroltracking/patrol/completedWorkflow.dart';
import 'package:patroltracking/patrol/patrolMultimediaScreen.dart';
import 'package:patroltracking/patrol/patroldashboard.dart';
import 'package:patroltracking/profile.dart';
import 'package:patroltracking/settings.dart';

class CustomDrawer extends StatelessWidget {
  final Map<String, dynamic> userdata;
  final String token;

  const CustomDrawer({super.key, required this.token, required this.userdata});

  @override
  Widget build(BuildContext context) {
    print("Token in CustomDrawer: $token");

    final imageUrl = userdata['imageUrl'] ?? '';
    final patrolName = userdata['patrolGuardName'] ?? 'User';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppConstants.primaryColor),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  backgroundImage: (imageUrl.isNotEmpty)
                      ? NetworkImage(imageUrl)
                      : null,
                  child: (imageUrl.isEmpty)
                      ? Icon(Icons.person,
                          size: 30, color: AppConstants.primaryColor)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  'Welcome, $patrolName',
                  style: AppConstants.drawerMiniHeaderStyle,
                ),
              ],
            ),
          ),
          _buildDrawerItem(context, Icons.dashboard, 'Dashboard', () {
            _safeNavigateToDashboard(context);
          }),
          _buildDrawerItem(context, Icons.perm_media, 'Multimedia', () {
            _safeNavigate(
              context,
              PatrolMultimediaScreen(
                checklistId: '',
                token: token,
                user: userdata,
                mode: 'bymenu',
              ),
            );
          }),
          _buildDrawerItem(context, Icons.person_2, 'Profile', () {
            _safeNavigate(
              context,
              ProfileScreen(user: userdata, mode: '', token: token),
            );
          }),
          _buildDrawerItem(context, Icons.event_available, 'Assignments', () {
            _safeNavigate(
              context,
              WorkflowScreen(userdata: userdata, token: token),
            );
          }),
          _buildDrawerItem(context, Icons.settings, 'Settings', () {
            _safeNavigate(
              context,
              SettingsScreen(userdata: userdata, token: token),
            );
          }),
          // Add Database Inspector to drawer
          // _buildDrawerItem(context, Icons.storage, 'Database Inspector', () {
          //   _safeNavigate(
          //     context,
          //     DatabaseInspectorScreen(
          //       token: token,
          //       userdata: userdata,
          //     ),
          //   );
          // }),
          _buildDrawerItem(context, Icons.power_settings_new_outlined, 'Logout',
              () {
            _showLogoutConfirmationDialog(context);
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
      BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppConstants.primaryColor),
      title: Text(title, style: AppConstants.normalFontStyle),
      onTap: onTap,
    );
  }

  void _safeNavigateToDashboard(BuildContext context) {
    try {
      Navigator.pop(context); 
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => PatrolDashboardScreen(userdata: userdata, token: token),
        ),
        (route) => route.isFirst, 
      );
    } catch (e) {
      print("Navigation error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open screen.')),
      );
    }
  }

  void _safeNavigate(BuildContext context, Widget screen) {
    try {
      Navigator.pop(context); 
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => screen),
      );
    } catch (e) {
      print("Navigation error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open screen.')),
      );
    }
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false, 
                );
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );
  }
}