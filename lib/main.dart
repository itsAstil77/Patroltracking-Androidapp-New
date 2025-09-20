import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:patroltracking/Login/login.dart';
import 'package:patroltracking/Login/onboarding.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/licence.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:patroltracking/services/background_sync.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:patroltracking/services/sync_service.dart';
import 'package:patroltracking/services/offline_service.dart';
import 'package:patroltracking/services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    final dbHelper = DatabaseHelper();
    final connectivity = Connectivity();
    final prefs = await SharedPreferences.getInstance();
    
    await dbHelper.database.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Database initialization timeout'),
    );

    final syncService = SyncService(
      dbHelper: dbHelper,
      connectivity: connectivity,
      apiService: ApiService(),
      prefs: prefs,
    );

    try {
      BackgroundSync.initialize();
      BackgroundSync.registerPeriodicSync();
    } catch (e) {
      debugPrint('Background sync initialization failed: $e');
    }

    runApp(MyApp(
      syncService: syncService,
      offlineService: OfflineService(dbHelper),
    ));
  } catch (e) {
    debugPrint('App initialization failed: $e');
    runApp(const ErrorApp());
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patrol Tracking - Error',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Please restart the application'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  SystemNavigator.pop(); // Close the app
                },
                child: const Text('Close App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final SyncService syncService;
  final OfflineService offlineService;

  const MyApp({
    Key? key,
    required this.syncService,
    required this.offlineService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Patrol Tracking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: AppConstants.fontFamily,
        primaryColor: AppConstants.primaryColor,
        textTheme: TextTheme(
          bodyLarge: AppConstants.normalFontStyle,
          titleLarge: AppConstants.headingStyle,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConstants.primaryColor,
        ),
        useMaterial3: true,
      ),
      home: SplashScreen(
        syncService: syncService,
        offlineService: offlineService,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final SyncService syncService;
  final OfflineService offlineService;

  const SplashScreen({
    Key? key,
    required this.syncService,
    required this.offlineService,
  }) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Position? _currentPosition;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;
  bool _isOnline = true;
  bool _isInitializing = true;
  String _initializationStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() => _initializationStatus = 'Setting up connectivity...');
      await _initConnectivity();
      
      setState(() => _initializationStatus = 'Checking permissions...');
      await _checkPermissionsAndNavigate();
    } catch (e) {
      debugPrint('App initialization error: $e');
      setState(() {
        _isInitializing = false;
        _initializationStatus = 'Initialization failed';
      });
      
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  Future<void> _initConnectivity() async {
    try {
      final initialResult = await Connectivity().checkConnectivity();
      setState(() => _isOnline = initialResult != ConnectivityResult.none);
      
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        (result) {
          if (mounted) {
            setState(() => _isOnline = result != ConnectivityResult.none);
          }
        },
        onError: (error) {
          debugPrint('Connectivity stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('Connectivity initialization error: $e');
      setState(() => _isOnline = false);
    }
  }

  Future<void> _checkPermissionsAndNavigate() async {
    try {
      setState(() => _initializationStatus = 'Getting location...');
      await _determinePosition();
      
      setState(() => _initializationStatus = 'Checking device authorization...');
      final deviceId = await _getDeviceId();
      final isAuthorized = await _checkLicenseFromLocal(deviceId);

      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 500));

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isAuthorized ? const LoginScreen() : const LicenseScreen(),
        ),
      );
    } catch (e) {
      debugPrint('Permission/Navigation error: $e');
      if (mounted) {
        _showErrorDialog(e.toString());
      }
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Initialization Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Failed to initialize the application:'),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isInitializing = true;
                _initializationStatus = 'Retrying...';
              });
              _initializeApp();
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<bool> _checkLicenseFromLocal(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedDeviceId = prefs.getString('device_id');
      final isValidated = prefs.getBool('license_validated') ?? false;
      return isValidated && storedDeviceId == deviceId;
    } catch (e) {
      debugPrint('License check error: $e');
      return false;
    }
  }

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'UnknownIOSId';
      }
      return 'UnsupportedPlatform';
    } catch (e) {
      debugPrint("Device ID Error: $e");
      return 'ErrorGettingDeviceId';
    }
  }

  Future<void> _determinePosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse && 
            permission != LocationPermission.always) {
          debugPrint('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      
      if (mounted) {
        setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.splashBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                height: MediaQuery.of(context).size.height * 0.08,
                width: MediaQuery.of(context).size.width * 0.6,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppConstants.logoImage),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              if (!_isOnline)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Offline Mode',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 20),
              
              if (_isInitializing)
                const CircularProgressIndicator(
                  color: AppConstants.primaryColor,
                ),
              
              const SizedBox(height: 16),
              
              Text(
                _initializationStatus,
                style: TextStyle(
                  color: AppConstants.primaryColor,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              
              if (_currentPosition != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Location ready',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}