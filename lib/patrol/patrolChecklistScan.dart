import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:patroltracking/constants.dart' as constants;
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/offline_service.dart';
import 'package:patroltracking/services/database_helper.dart';

enum ScanMode { qr, barcode, nfc }

class PatrolChecklistScanScreen extends StatefulWidget {
  final String checklistId;
  final dynamic scannerlocation; 
  final Map<String, dynamic> user;
  final String token;

  const PatrolChecklistScanScreen({
    super.key,
    required this.checklistId,
    required this.scannerlocation,
    required this.user,
    required this.token,
  });

  @override
  _PatrolChecklistScanScreenState createState() => _PatrolChecklistScanScreenState();
}

class _PatrolChecklistScanScreenState extends State<PatrolChecklistScanScreen> {
  String? scanResult;
  ScanMode selectedScanMode = ScanMode.nfc;
  final MobileScannerController scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _isOnline = true;
  bool _isCameraInitialized = false;
  String? _cameraError;
  bool _isPermissionRequestInProgress = false; 
  Future<void>? _scannerFuture; 
  final OfflineService _offlineService = OfflineService(DatabaseHelper());
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    _scannerFuture = _checkPermissionsAndStartScanner(); 
  }

  @override
  void dispose() {
    scannerController.stop();
    scannerController.dispose();
    NfcManager.instance.stopSession();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });

      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
        setState(() {
          _isOnline = result != ConnectivityResult.none;
        });
      });
    } catch (e) {
      debugPrint('Error initializing connectivity: $e');
      _showError('Failed to check connectivity: $e');
    }
  }

  Future<bool> _checkPermissions() async {
    if (_isPermissionRequestInProgress) {
      debugPrint('Permission request already in progress, skipping');
      return false;
    }

    if (selectedScanMode == ScanMode.qr || selectedScanMode == ScanMode.barcode) {
      try {
        setState(() => _isPermissionRequestInProgress = true);
        debugPrint('Requesting camera permission');
        final cameraPermission = await Permission.camera.request().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Camera permission request timed out');
          },
        );
        setState(() => _isPermissionRequestInProgress = false);

        if (cameraPermission.isDenied) {
          _showError('Camera permission is required to scan QR/barcode.');
          return false;
        } else if (cameraPermission.isPermanentlyDenied) {
          _showError('Camera permission is permanently denied. Please enable it in settings.');
          await openAppSettings();
          return false;
        }
        debugPrint('Camera permission granted');
        return true;
      } catch (e) {
        debugPrint('Error checking camera permission: $e');
        _showError('Failed to check camera permission: $e');
        setState(() => _isPermissionRequestInProgress = false);
        return false;
      }
    }
    return true; 
  }

  Future<void> _checkPermissionsAndStartScanner() async {
    setState(() {
      _cameraError = null;
      _isCameraInitialized = false;
    });

    if (selectedScanMode == ScanMode.qr || selectedScanMode == ScanMode.barcode) {
      final hasPermission = await _checkPermissions();
      if (hasPermission) {
        try {
          debugPrint('Starting camera for scan mode: $selectedScanMode');
          await scannerController.start().timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Camera initialization timed out');
            },
          );
          debugPrint('Camera started successfully');
          setState(() {
            _isCameraInitialized = true;
            _cameraError = null;
          });
        } catch (e) {
          debugPrint('Error starting scanner: $e');
          setState(() {
            _cameraError = 'Failed to start camera: $e';
            selectedScanMode = ScanMode.nfc; 
          });
        }
      } else {
        setState(() {
          _cameraError = 'Camera permission not granted';
          selectedScanMode = ScanMode.nfc; 
        });
      }
    } else {
      await scannerController.stop();
      setState(() {
        _isCameraInitialized = false;
        _cameraError = null;
      });
      if (selectedScanMode == ScanMode.nfc) {
        await _startNfcScan();
      }
    }
  }

  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showError('Location permissions are permanently denied.');
        return null;
      }

      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      _showError('Failed to get location: $e');
      return null;
    }
  }



void _processScanResult(String result) async {
  if (scanResult != null) return;

  setState(() => scanResult = result);
  await scannerController.stop();

  debugPrint('Scanned result: $result');
  debugPrint('Expected scannerlocation: ${widget.scannerlocation}, type: ${widget.scannerlocation.runtimeType}');

  bool isValidScan = false;
  dynamic scannerLocation = widget.scannerlocation;
  String? scannedLocationCode;

  if (scannerLocation is String) {
    try {
      scannerLocation = jsonDecode(scannerLocation);
    } catch (e) {
      // Not a JSON string, keep as String
    }
  }

  if (scannerLocation is String) {
    isValidScan = result.trim() == scannerLocation.trim();
    if (isValidScan) {
      scannedLocationCode = result.trim();
    }
  } else if (scannerLocation is List) {
    isValidScan = scannerLocation.contains(result.trim());
    if (isValidScan) {
      scannedLocationCode = result.trim();
    }
  }

  debugPrint('Is valid scan: $isValidScan');
  debugPrint('Scanned location code: $scannedLocationCode');

  if (isValidScan && scannedLocationCode != null) {
    try {
      final position = await _getCurrentLocation();
      if (position == null) {
        throw Exception('Failed to get location');
      }
      final coordinates = '${position.latitude},${position.longitude}';
      final scanTime = DateTime.now().toUtc().toIso8601String();

      // Save scan offline with location information
      await _offlineService.saveScanOffline(
        checklistId: widget.checklistId,
        scanType: selectedScanMode.name.toUpperCase(),
        coordinates: coordinates,
        scannedLocationCode: scannedLocationCode, // Add this parameter
      );

      await _offlineService.updateChecklistScanStatus(widget.checklistId);

      if (_isOnline) {
        final response = await ApiService.submitScan(
          scanType: selectedScanMode.name.toUpperCase(),
          checklistId: widget.checklistId,
          token: widget.token,
          latitude: position.latitude,
          longitude: position.longitude,
          scanStartDate: scanTime,
          scannedLocationCode: scannedLocationCode, // Add this parameter
        );

        if (response['message'] != 'Scan recorded and checklist updated successfully') {
          throw Exception('Scan failed: ${response['message']}');
        }

        // Show which location was scanned
        final scannedLocation = response['data']?['scannedLocation'];
        String successMessage = 'Scan recorded successfully';
        if (scannedLocation != null) {
          successMessage = 'Scanned location: ${scannedLocation['locationName']} (${scannedLocation['locationCode']})';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage)),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Scan saved offline (Location: $scannedLocationCode) - will sync when online'),
            ),
          );
        }
      }

      if (mounted) {
        Navigator.pop(context, {
          'success': true, 
          'scanStartDate': scanTime,
          'scannedLocationCode': scannedLocationCode,
        });
      }
    } catch (e) {
      debugPrint('Error processing scan: $e');
      _showError('Error: $e');
      if (selectedScanMode != ScanMode.nfc) {
        _scannerFuture = _checkPermissionsAndStartScanner();
        setState(() {}); 
      }
      setState(() => scanResult = null);
    }
  } else {
    _showError('Invalid scan: Location mismatch.');
    debugPrint('Location mismatch - scanned: $result, expected: $scannerLocation');
    if (selectedScanMode != ScanMode.nfc) {
      _scannerFuture = _checkPermissionsAndStartScanner();
      setState(() {}); 
    }
    setState(() => scanResult = null);
  }
}


  Future<void> _startNfcScan() async {
  if (scanResult != null) return;

  final isAvailable = await NfcManager.instance.isAvailable();
  if (!isAvailable) {
    _showError('NFC not available on this device.');
    return;
  }

  try {
    await NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null || ndef.cachedMessage == null) {
            throw Exception('Invalid or empty NFC tag.');
          }

          final record = ndef.cachedMessage!.records.first;
          final payload = record.payload;
          final languageCodeLength = payload[0] & 0x3F;
          final tagValue = utf8.decode(payload.sublist(1 + languageCodeLength)).trim();

          bool isValidScan = false;
          String? scannedLocationCode;
          
          if (widget.scannerlocation is String) {
            isValidScan = tagValue == widget.scannerlocation.trim();
            if (isValidScan) {
              scannedLocationCode = tagValue;
            }
          } else if (widget.scannerlocation is List) {
            isValidScan = (widget.scannerlocation as List).contains(tagValue);
            if (isValidScan) {
              scannedLocationCode = tagValue;
            }
          }

          if (isValidScan && scannedLocationCode != null) {
            setState(() => scanResult = tagValue);
            await NfcManager.instance.stopSession();

            final position = await _getCurrentLocation();
            if (position == null) {
              throw Exception('Failed to get location');
            }
            final scanTime = DateTime.now().toUtc().toIso8601String();

            await _offlineService.saveScanOffline(
              checklistId: widget.checklistId,
              scanType: 'NFC',
              coordinates: '${position.latitude},${position.longitude}',
              scannedLocationCode: scannedLocationCode, // Add this parameter
            );

            await _offlineService.updateChecklistScanStatus(widget.checklistId);

            if (_isOnline) {
              final response = await ApiService.submitScan(
                scanType: 'NFC',
                checklistId: widget.checklistId,
                token: widget.token,
                latitude: position.latitude,
                longitude: position.longitude,
                scanStartDate: scanTime,
                scannedLocationCode: scannedLocationCode, // Add this parameter
              );

              if (response['message'] != 'Scan recorded and checklist updated successfully') {
                throw Exception('Scan failed: ${response['message']}');
              }

              final scannedLocation = response['data']?['scannedLocation'];
              String successMessage = 'NFC scan recorded successfully';
              if (scannedLocation != null) {
                successMessage = 'NFC scanned location: ${scannedLocation['locationName']} (${scannedLocation['locationCode']})';
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(successMessage)),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('NFC scan saved offline (Location: $scannedLocationCode) - will sync when online'),
                  ),
                );
              }
            }

            if (mounted) {
              Navigator.pop(context, {
                'success': true, 
                'scanStartDate': scanTime,
                'scannedLocationCode': scannedLocationCode,
              });
            }
          } else {
            _showError('Invalid scan: Location mismatch.');
            await Future.delayed(const Duration(seconds: 2));
            setState(() => scanResult = null);
          }
        } catch (e) {
          await NfcManager.instance.stopSession(errorMessage: e.toString());
          _showError('Error: $e');
          setState(() => scanResult = null);
        }
      },
    );
  } catch (e) {
    _showError('Failed to start NFC session: $e');
  }
}

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _buildScanner() {
    if (selectedScanMode == ScanMode.qr || selectedScanMode == ScanMode.barcode) {
      if (_cameraError != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _cameraError!,
                style: constants.AppConstants.normalWhiteFontStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _scannerFuture = _checkPermissionsAndStartScanner();
                  setState(() {}); 
                },
                child: const Text('Retry Camera'),
              ),
              ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('Open Settings'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    selectedScanMode = ScanMode.nfc;
                    _cameraError = null;
                    _scannerFuture = _checkPermissionsAndStartScanner();
                  });
                },
                child: const Text('Switch to NFC'),
              ),
            ],
          ),
        );
      }
      return FutureBuilder(
        future: _scannerFuture, 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!_isCameraInitialized) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Camera not initialized. Please grant camera permission or try again.',
                    style: constants.AppConstants.normalWhiteFontStyle,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      _scannerFuture = _checkPermissionsAndStartScanner();
                      setState(() {}); 
                    },
                    child: const Text('Retry Camera'),
                  ),
                  ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text('Open Settings'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedScanMode = ScanMode.nfc;
                        _cameraError = null;
                        _scannerFuture = _checkPermissionsAndStartScanner();
                      });
                    },
                    child: const Text('Switch to NFC'),
                  ),
                ],
              ),
            );
          }
          return MobileScanner(
            controller: scannerController,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  _processScanResult(barcode.rawValue!);
                  break;
                }
              }
            },
          );
        },
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.nfc, size: 100, color: constants.AppConstants.primaryColor),
            Text(
              'Bring device near an NFC tag',
              style: constants.AppConstants.headingStyle,
            ),
            if (!_isOnline)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Offline Mode',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildScanOptions() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 10,
        children: [
          ChoiceChip(
            label: Text('Scanner', style: constants.AppConstants.boldPurpleFontStyle),
            selected: selectedScanMode == ScanMode.qr,
            onSelected: (val) {
              setState(() {
                selectedScanMode = ScanMode.qr;
                scanResult = null;
                _scannerFuture = _checkPermissionsAndStartScanner();
              });
            },
          ),
          ChoiceChip(
            label: Text('NFC', style: constants.AppConstants.boldPurpleFontStyle),
            selected: selectedScanMode == ScanMode.nfc,
            onSelected: (val) {
              setState(() {
                selectedScanMode = ScanMode.nfc;
                scanResult = null;
                _scannerFuture = _checkPermissionsAndStartScanner();
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Scan Task', style: constants.AppConstants.headingStyle),
        actions: [
          if (!_isOnline)
            const Icon(Icons.wifi_off, color: Colors.orange),
        ],
      ),
      body: Column(
        children: [
          _buildScanOptions(),
          Expanded(
            child: Stack(
              children: [
                _buildScanner(),
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Scan / Tag against the task: ${widget.checklistId}',
                      style: constants.AppConstants.normalWhiteFontStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (scanResult != null)
                  Positioned(
                    bottom: 50,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Scanned: $scanResult',
                        style: constants.AppConstants.normalWhiteBoldFontStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}