import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/models/checklist.dart';
import 'package:patroltracking/navigationbar.dart';
import 'package:patroltracking/patrol/patrolEvent.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/offline_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:patroltracking/services/background_sync.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:patroltracking/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PatrolDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> userdata;
  final String token;
  const PatrolDashboardScreen({
    super.key,
    required this.userdata,
    required this.token,
  });

  @override
  State<PatrolDashboardScreen> createState() => _PatrolDashboardScreenState();
}

class _PatrolDashboardScreenState extends State<PatrolDashboardScreen> {
  LatLng? _currentPosition;
  GoogleMapController? _mapController;
  final Location _location = Location();
  bool _isTracking = false;
  Timer? _locationTimer;
  bool _isOnline = true;
  List<EventChecklistGroup> _eventGroups = [];
  StreamSubscription? _connectivitySubscription;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeConnectivity();
    _initializeDashboard();
    BackgroundSync.initialize();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeConnectivity() async {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) async {
      final isOnline = result != ConnectivityResult.none;
      setState(() => _isOnline = isOnline);

      if (isOnline) {
        await SyncService(
          dbHelper: DatabaseHelper(),
          connectivity: Connectivity(),
          apiService: ApiService(),
          prefs: await SharedPreferences.getInstance(),
        ).syncPendingData();
        await _loadOnlineData();
      } else {
        await _loadOfflineData();
      }
    });

    _isOnline =
        await Connectivity().checkConnectivity() != ConnectivityResult.none;
  }

  Future<void> _initializeDashboard() async {
    if (_isOnline) {
      await _loadOnlineData();
    } else {
      await _loadOfflineData();
    }
    await _initLocation();
  }

  Future<void> _loadOnlineData() async {
    try {
      final formattedDate =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

      debugPrint('Loading data for date: $formattedDate');

      final events = await ApiService.fetchGroupedChecklists(
        widget.userdata['userId'],
        widget.token,
        scheduledDate: formattedDate,
      );

      debugPrint('Received ${events.length} workflows from API');
      for (var event in events) {
        debugPrint(
            '- ${event.workflowTitle} (${event.status}) - scheduledDate: ${event.scheduledDate} - checklists: ${event.checklists.length}');
      }

      // final offlineService = OfflineService(DatabaseHelper());
      // await offlineService.cacheWorkflows(events, widget.userdata['userId']);
      final offlineService = OfflineService(DatabaseHelper());
      final db = await DatabaseHelper().database;

// 🧠 Get current local workflow IDs
      final localWorkflows = await db.query('workflows');
      final localIds = localWorkflows.map((w) => w['workflowId']).toSet();

// 🌐 Get workflow IDs from MongoDB (server)
      final serverIds = events.map((e) => e.workflowId).toSet();

// 🧹 Delete local entries missing from server
      for (var localId in localIds) {
        if (!serverIds.contains(localId)) {
          await db.delete('workflows',
              where: 'workflowId = ?', whereArgs: [localId]);
          await db.delete('checklists',
              where: 'workflowId = ?', whereArgs: [localId]);
        }
      }

// 💾 Then cache/insert latest workflows
      await offlineService.cacheWorkflows(events, widget.userdata['userId']);
// till here

      _updateEventsList(events);
    } catch (e) {
      debugPrint('Error loading online data: $e');
      final offlineService = OfflineService(DatabaseHelper());
      final formattedDate =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final allOfflineEvents =
          await offlineService.getOfflineWorkflows(widget.userdata['userId']);

      final filteredEvents = allOfflineEvents.where((event) {
        if (event.scheduledDate != null) {
          return event.scheduledDate == formattedDate;
        }

        if (event.assignedStart != null && event.assignedEnd != null) {
          final selectedDate = DateTime.parse(formattedDate);
          final startDate = DateTime(event.assignedStart!.year,
              event.assignedStart!.month, event.assignedStart!.day);
          final endDate = DateTime(event.assignedEnd!.year,
              event.assignedEnd!.month, event.assignedEnd!.day);

          return (selectedDate.isAtSameMomentAs(startDate) ||
                  selectedDate.isAfter(startDate)) &&
              (selectedDate.isAtSameMomentAs(endDate) ||
                  selectedDate.isBefore(endDate));
        }

        return false;
      }).toList();

      if (filteredEvents.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("No data available for selected date: $e")),
          );
        }
      }

      _updateEventsList(filteredEvents);
    }
  }

  List<EventChecklistGroup> _filterWorkflowsByDate(
      List<EventChecklistGroup> workflows, DateTime selectedDate) {
    return workflows.where((workflow) {
      if (workflow.scheduledDate != null) {
        return true;
      }

      if (workflow.assignedStart != null && workflow.assignedEnd != null) {
        final selectedDateOnly =
            DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final startDateOnly = DateTime(workflow.assignedStart!.year,
            workflow.assignedStart!.month, workflow.assignedStart!.day);
        final endDateOnly = DateTime(workflow.assignedEnd!.year,
            workflow.assignedEnd!.month, workflow.assignedEnd!.day);

        final isInRange = (selectedDateOnly.isAtSameMomentAs(startDateOnly) ||
                selectedDateOnly.isAfter(startDateOnly)) &&
            (selectedDateOnly.isAtSameMomentAs(endDateOnly) ||
                selectedDateOnly.isBefore(endDateOnly));

        debugPrint('Ordinary workflow ${workflow.workflowTitle}:');
        debugPrint('  Selected: $selectedDateOnly');
        debugPrint('  Start: $startDateOnly');
        debugPrint('  End: $endDateOnly');
        debugPrint('  In range: $isInRange');

        return isInRange;
      }

      return true;
    }).toList();
  }

  Future<void> _loadOfflineData() async {
    try {
      final offlineService = OfflineService(DatabaseHelper());
      final formattedDate =
          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
      final events = await offlineService.getOfflineWorkflows(
          widget.userdata['userId'],
          scheduledDate: formattedDate);

      if (events.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("No offline data available for selected date")),
          );
        }
      }

      _updateEventsList(events);
    } catch (e) {
      if (mounted && _eventGroups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading offline data: $e")),
        );
      }
    }
  }

  void _updateEventsList(List<EventChecklistGroup> events) {
    events.sort((a, b) {
      const priority = {'inprogress': 0, 'pending': 1, 'completed': 2};
      final aPriority = priority[a.status.toLowerCase()] ?? 3;
      final bPriority = priority[b.status.toLowerCase()] ?? 3;
      return aPriority.compareTo(bPriority);
    });

    if (mounted) {
      setState(() => _eventGroups = events);
    }
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) return;
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }

      final locationData = await _location.getLocation();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(
            locationData.latitude ?? 0.0,
            locationData.longitude ?? 0.0,
          );
        });
      }
    } catch (e) {
      debugPrint("Location error: $e");
    }
  }

  void _startTracking() {
    setState(() => _isTracking = true);
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final locationData = await _location.getLocation();
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(
            locationData.latitude ?? 0.0,
            locationData.longitude ?? 0.0,
          );
        });
      }
      _mapController?.animateCamera(CameraUpdate.newLatLng(_currentPosition!));
    });
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied.');
    }

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high);
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppConstants.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });

      if (_isOnline) {
        await _loadOnlineData();
      } else {
        await _loadOfflineData();
      }
    }
  }

  void _showStartPatrolPopup({required EventChecklistGroup event}) async {
    final offlineService = OfflineService(DatabaseHelper());
    final workflows =
        await offlineService.getOfflineWorkflows(widget.userdata['userId']);
    final workflow = workflows.firstWhere(
      (w) => w.workflowId == event.workflowId,
      orElse: () => EventChecklistGroup(
        workflowId: event.workflowId,
        workflowTitle: event.workflowTitle,
        status: 'pending',
        checklists: [],
      ),
    );

    if (workflow.status.toLowerCase() == 'inprogress') {
      _navigateToPatrolEventCheckScreen(event);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Start Patrol"),
        content: Text(
            "Do you want to start the assignment: ${event.workflowTitle}?"),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final position = await _getCurrentLocation();
                final coords = '${position.latitude},${position.longitude}';
                final startTime = DateTime.now();

                if (_isOnline) {
                  final success = await ApiService.startWorkflow(
                    event.workflowId,
                    widget.token,
                    latitude: position.latitude,
                    longitude: position.longitude,
                    startTime: startTime,
                  );
                  if (success) {
                    _startTracking();
                    _navigateToPatrolEventCheckScreen(event);
                  }
                } else {
                  await OfflineService(DatabaseHelper()).startWorkflowOffline(
                    event.workflowId,
                    coords,
                    startTime: startTime,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Started offline - will sync when online')),
                    );
                  }
                  _startTracking();
                  _navigateToPatrolEventCheckScreen(event);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Location error: $e")),
                  );
                }
              }
            },
            child: const Text("Start"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  void _navigateToPatrolEventCheckScreen(EventChecklistGroup event) {
    Navigator.push(
      // Changed from pushReplacement
      context,
      MaterialPageRoute(
        builder: (context) => PatrolEventCheckScreen(
          token: widget.token,
          userdata: widget.userdata,
          eventId: event.workflowId,
          eventtitle: event.workflowTitle,
          scheduledDate: event.scheduledDate,
        ),
      ),
    );
  }

  void _showCompletedWorkflowAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Workflow Completed"),
        content: const Text("This assignment has already been completed."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showSOSPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Confirmation Box!"),
        content: const Text("Are you sure to submit SOS?"),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _sendSOSAlert();
            },
            child: const Text("Yes"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("No"),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSOSAlert() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      if (_isOnline) {
        final response = await ApiService.sendSOSAlert(
          userid: widget.userdata['userId'],
          remarks: "Emergency! Immediate help needed!",
          token: widget.token,
          latitude: position.latitude,
          longitude: position.longitude,
        );

        if (response['message'] == 'SOS alert saved successfully.') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("SOS Alert Sent")),
            );
          }
        }
      } else {
        await OfflineService(DatabaseHelper()).saveSOSOffline(
          userId: widget.userdata['userId'],
          remarks: "Emergency! Immediate help needed!",
          coordinates: '${position.latitude},${position.longitude}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("SOS saved offline - will send when online")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("SOS Error: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Show confirmation dialog when back button is pressed
        final shouldExit = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Exit'),
            content: const Text('Are you sure you want to exit the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        return shouldExit ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: Text('Patrol Dashboard', style: AppConstants.headingStyle),
          actions: [
            // Add debug button to app bar actions
            // IconButton(
            //   icon: const Icon(Icons.bug_report, color: AppConstants.primaryColor),
            //   onPressed: () {
            //     DatabaseHelper().printAllData();
            //     ScaffoldMessenger.of(context).showSnackBar(
            //       const SnackBar(content: Text('Database printed to console')),
            //     );
            //   },
            //   tooltip: 'Debug Database',
            // ),
            IconButton(
              icon: const Icon(Icons.calendar_today,
                  color: AppConstants.primaryColor),
              onPressed: _selectDate,
              tooltip: 'Select Date',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppConstants.primaryColor),
              tooltip: "Refresh Data",
              onPressed: () async {
                if (_isOnline) {
                  await _loadOnlineData();
                } else {
                  await _loadOfflineData();
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Data refreshed")),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.sos, color: Colors.white),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _showSOSPopup,
            ),
            if (!_isOnline)
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(Icons.wifi_off, color: Colors.orange),
              ),
          ],
        ),
        drawer: CustomDrawer(userdata: widget.userdata, token: widget.token),
        // floatingActionButton: FloatingActionButton(
        //   onPressed: () {
        //     DatabaseHelper().printAllData();
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(content: Text('Database printed to console')),
        //     );
        //   },
        //   backgroundColor: AppConstants.primaryColor,
        //   child: const Icon(Icons.bug_report, color: Colors.white),
        // ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppConstants.primaryColor.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 16, color: AppConstants.primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    'Selected Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    style: TextStyle(
                      color: AppConstants.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  // TextButton(
                  //   onPressed: _selectDate,
                  //   child: Text(
                  //     'Change Date',
                  //     style: TextStyle(color: AppConstants.primaryColor),
                  //   ),
                  // ),
                ],
              ),
            ),
            if (!_isOnline)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.orange,
                child: Row(
                  children: const [
                    Icon(Icons.wifi_off, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Offline Mode - Data will sync when online',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            Expanded(
              flex: 3,
              child: _currentPosition == null
                  ? const Center(child: CircularProgressIndicator())
                  : GoogleMap(
                      onMapCreated: (controller) => _mapController = controller,
                      initialCameraPosition: CameraPosition(
                        target: _currentPosition!,
                        zoom: 16.0,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId("currentLocation"),
                          position: _currentPosition!,
                          infoWindow: const InfoWindow(title: "Your Location"),
                        ),
                      },
                      myLocationButtonEnabled: true,
                      myLocationEnabled: true,
                      mapType: MapType.terrain,
                    ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assigned assignment',
                      style: AppConstants.headingStyle.copyWith(
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _eventGroups.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.assignment_outlined,
                                      size: 48, color: Colors.grey[400]),
                                  const SizedBox(height: 8),
                                  Text(
                                    "No assignment for selected date",
                                    style: TextStyle(
                                      color: AppConstants.primaryColor,
                                    ),
                                  ),
                                  // TextButton(
                                  //   onPressed: _selectDate,
                                  //   child: const Text('Try Different Date'),
                                  // ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _eventGroups.length,
                              itemBuilder: (context, index) {
                                final event = _eventGroups[index];
                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 8),
                                  child: ListTile(
                                    title: Text(
                                      event.workflowTitle,
                                      style: AppConstants.boldPurpleFontStyle,
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Status: ${event.status}",
                                          style: AppConstants
                                              .normalPurpleFontStyle,
                                        ),
                                        if (event.scheduledDate != null)
                                          Text(
                                            "Date: ${event.scheduledDate}",
                                            style: AppConstants
                                                .normalPurpleFontStyle
                                                .copyWith(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        if (event.assignedStart != null &&
                                            event.assignedEnd != null)
                                          Text(
                                            "Period: ${event.assignedStart!.day}/${event.assignedStart!.month}/${event.assignedStart!.year} - ${event.assignedEnd!.day}/${event.assignedEnd!.month}/${event.assignedEnd!.year}",
                                            style: AppConstants
                                                .normalPurpleFontStyle
                                                .copyWith(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                      ],
                                    ),
                                    onTap: () async {
                                      final db =
                                          await DatabaseHelper().database;
                                      final workflow = await db.query(
                                        'workflows',
                                        where: 'workflowId = ?',
                                        whereArgs: [event.workflowId],
                                        limit: 1,
                                      );

                                      final status = workflow.isNotEmpty
                                          ? (workflow.first['status']
                                                      as String?)
                                                  ?.toLowerCase() ??
                                              'unknown'
                                          : event.status?.toLowerCase() ??
                                              'unknown';

                                      if (status == "pending") {
                                        _showStartPatrolPopup(event: event);
                                      } else if (status == "inprogress") {
                                        _navigateToPatrolEventCheckScreen(
                                            event);
                                      } else if (status == "completed") {
                                        _showCompletedWorkflowAlert();
                                      } else {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                                    "Unknown assignment status")),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
