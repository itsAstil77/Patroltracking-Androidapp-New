// import 'package:flutter/material.dart';
// import 'package:patroltracking/constants.dart';
// import 'package:patroltracking/navigationbar.dart';
// import 'package:patroltracking/profile.dart';

// class SettingsScreen extends StatefulWidget {
//   final Map<String, dynamic> userdata;
//   final String token;

//   const SettingsScreen({
//     super.key,
//     required this.userdata,
//     required this.token,
//   });

//   @override
//   State<SettingsScreen> createState() => _SettingsScreenState();
// }

// class _SettingsScreenState extends State<SettingsScreen> {
//   final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
//   final bool _isDarkMode = false;
//   final bool _notificationsEnabled = true;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       key: _scaffoldKey,
//       appBar: AppBar(
//         leading: IconButton(
//           icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
//           onPressed: () {
//             _scaffoldKey.currentState?.openDrawer();
//           },
//         ),
//         title: Text('Settings', style: AppConstants.headingStyle),
//         backgroundColor: Colors.white,
//         iconTheme: const IconThemeData(color: AppConstants.primaryColor),
//         elevation: 1,
//       ),
//       drawer: CustomDrawer(
//         userdata: widget.userdata,
//         token: widget.token,
//       ),
//       body: ListView(
//         children: [
//           ListTile(
//             leading: const Icon(
//               Icons.person,
//               color: AppConstants.primaryColor,
//             ),
//             title: Text(
//               "Profile",
//               style: AppConstants.boldPurpleFontStyle,
//             ),
//             subtitle: Text(
//               widget.userdata['patrolGuardName'] ?? 'No Name',
//               style: AppConstants.normalPurpleFontStyle,
//             ),
//             trailing: const Icon(
//               Icons.arrow_forward_ios,
//               color: AppConstants.primaryColor,
//             ),
//             onTap: () {
//               Navigator.of(context).pushReplacement(
//                 MaterialPageRoute(
//                   builder: (_) => ProfileScreen(
//                     user: widget.userdata,
//                     mode: "settings",
//                     token: widget.token,
//                   ),
//                 ),
//               );
//             },
//           ),
//           Padding(
//             padding:
//                 const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//             child: Card(
//               elevation: 3,
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12)),
//               child: Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Row(
//                       children: const [
//                         Icon(Icons.lock, color: AppConstants.primaryColor),
//                         SizedBox(width: 8),
//                         Text(
//                           "License Info",
//                           style: TextStyle(
//                             color: AppConstants.primaryColor,
//                             fontSize: 16,
//                             fontWeight: FontWeight.bold,
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 12),
//                     const Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         Text("License Active:",
//                             style: TextStyle(fontWeight: FontWeight.w500)),
//                         Text("Yes", style: TextStyle(color: Colors.green)),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     const Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         Text("Expire Date:",
//                             style: TextStyle(fontWeight: FontWeight.w500)),
//                         Text("2026-12-31"),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     const Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                       children: [
//                         Text("Serial Number:",
//                             style: TextStyle(fontWeight: FontWeight.w500)),
//                         Text("PT-1234-5678-XYZ"),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),

//           ListTile(
//             leading: const Icon(
//               Icons.info,
//               color: AppConstants.primaryColor,
//             ),
//             title: Text("App Info", style: AppConstants.boldPurpleFontStyle),
//             subtitle: Text("Version 1.0.0",
//                 style: AppConstants.normalPurpleFontStyle),
//             onTap: () {
//               showAboutDialog(
//                 context: context,
//                 applicationName: "PatrolTracking",
//                 applicationVersion: "1.0.0",
//                 applicationLegalese: "© 2025 purpleiq",
//               );
//             },
//           ),
//         ],
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/navigationbar.dart';
import 'package:patroltracking/profile.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> userdata;
  final String token;

  const SettingsScreen({
    super.key,
    required this.userdata,
    required this.token,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final bool _isDarkMode = false;
  final bool _notificationsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Text('Settings', style: AppConstants.headingStyle),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppConstants.primaryColor),
        elevation: 1,
      ),
      drawer: CustomDrawer(
        userdata: widget.userdata,
        token: widget.token,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(
              Icons.person,
              color: AppConstants.primaryColor,
            ),
            title: Text(
              "Profile",
              style: AppConstants.boldPurpleFontStyle,
            ),
            subtitle: Text(
              widget.userdata['patrolGuardName'] ?? 'No Name',
              style: AppConstants.normalPurpleFontStyle,
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: AppConstants.primaryColor,
            ),
            onTap: () {
              Navigator.push( // Changed from pushReplacement
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    user: widget.userdata,
                    mode: "settings",
                    token: widget.token,
                  ),
                ),
              );
            },
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.lock, color: AppConstants.primaryColor),
                        SizedBox(width: 8),
                        Text(
                          "License Info",
                          style: TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("License Active:",
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text("Yes", style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Expire Date:",
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text("2026-12-31"),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Serial Number:",
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        Text("PT-1234-5678-XYZ"),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          ListTile(
            leading: const Icon(
              Icons.info,
              color: AppConstants.primaryColor,
            ),
            title: Text("App Info", style: AppConstants.boldPurpleFontStyle),
            subtitle: Text("Version 1.0.0",
                style: AppConstants.normalPurpleFontStyle),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: "PatrolTracking",
                applicationVersion: "1.0.0",
                applicationLegalese: "© 2025 purpleiq",
              );
            },
          ),
        ],
      ),
    );
  }
}