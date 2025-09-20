import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/patrol/patrolChecklistScan.dart';
import 'package:patroltracking/patrol/patrolMultimediaScreen.dart';
import 'package:patroltracking/patrol/patroldashboard.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/offline_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:patroltracking/models/checklist.dart';
import 'dart:convert';
import 'package:http/http.dart' as http; 

class PatrolEventCheckScreen extends StatefulWidget {
  final String eventId;
  final Map<String, dynamic> userdata;
  final String token;
  final String eventtitle;
  final String? scheduledDate; 

  const PatrolEventCheckScreen({
    super.key,
    required this.userdata,
    required this.token,
    required this.eventId,
    required this.eventtitle,
    this.scheduledDate, 
  });

  @override
  _PatrolEventCheckScreenState createState() => _PatrolEventCheckScreenState();
}

class _PatrolEventCheckScreenState extends State<PatrolEventCheckScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allChecklists = [];
  List<Map<String, dynamic>> _filteredChecklists = [];
  final Map<String, bool> _selectedChecklists = {};
  bool _isLoading = true;
  double? _latitude;
  double? _longitude;
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  final OfflineService _offlineService = OfflineService(DatabaseHelper());

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final db = await DatabaseHelper().database;
    final workflow = await db.query(
      'workflows',
      where: 'workflowId = ?',
      whereArgs: [widget.eventId],
      limit: 1,
    );

    if (workflow.isNotEmpty && workflow.first['status'] == 'completed') {
      if (mounted) {
        _showSnackbar("This workflow is already completed");
        _navigateBackToDashboard();
        return;
      }
    }

    await _initConnectivity();
    await _getCurrentLocation();
    await _loadChecklists();
  }


  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(() => _isOnline = result != ConnectivityResult.none);
      }
      _loadChecklists();
    });

    final connectivityResult = await Connectivity().checkConnectivity();
    if (mounted) {
      setState(() => _isOnline = connectivityResult != ConnectivityResult.none);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showSnackbar("Location services are disabled.");
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          if (mounted) {
            _showSnackbar("Location permissions denied");
          }
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnackbar("Failed to get location: ${e.toString()}");
      }
    }
  }

  

 Future<void> _loadChecklists() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      List<Map<String, dynamic>> checklists;
      debugPrint('Loading checklists for workflow ${widget.eventId}, scheduledDate: ${widget.scheduledDate}, online: $_isOnline');

      if (_isOnline) {
        checklists = await _fetchOnlineChecklists();
        debugPrint('Fetched ${checklists.length} checklists online');
        await _offlineService.syncOnlineCompletions(
            widget.eventId, widget.token, widget.userdata['userId']);
      } else {
        checklists = await _offlineService.getValidOfflineChecklists(
          widget.eventId, 
          scheduledDate: widget.scheduledDate 
        );
        debugPrint('Fetched ${checklists.length} checklists offline');
      }

      if (mounted) {
        setState(() {
          _allChecklists = checklists.map((checklist) {
            final locationCodeRaw = checklist['locationCode'];
            dynamic locationCode;
            if (locationCodeRaw is String) {
              try {
                locationCode = jsonDecode(locationCodeRaw);
              } catch (e) {
                locationCode = locationCodeRaw;
              }
            } else {
              locationCode = locationCodeRaw ?? '';
            }
            return {
              ...checklist,
              'locationCode': locationCode,
            };
          }).toList();
          _filteredChecklists = List.from(_allChecklists);
          _selectedChecklists.clear();
          for (var item in _allChecklists) {
            _selectedChecklists[item['checklistId']] = item['status'] == 'completed';
          }
          debugPrint('Updated UI with ${_filteredChecklists.length} checklists');
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading checklists: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar("Error loading checklists: ${e.toString()}");
        final offlineChecklists = await _offlineService.getValidOfflineChecklists(
          widget.eventId, 
          scheduledDate: widget.scheduledDate
        );
        if (offlineChecklists.isNotEmpty) {
          setState(() {
            _allChecklists = offlineChecklists.map((checklist) {
              final locationCodeRaw = checklist['locationCode'];
              dynamic locationCode;
              if (locationCodeRaw is String) {
                try {
                  locationCode = jsonDecode(locationCodeRaw);
                } catch (e) {
                  locationCode = locationCodeRaw;
                }
              } else {
                locationCode = locationCodeRaw ?? '';
              }
              return {
                ...checklist,
                'locationCode': locationCode,
              };
            }).toList();
            _filteredChecklists = List.from(_allChecklists);
            _selectedChecklists.clear();
            for (var item in _allChecklists) {
              _selectedChecklists[item['checklistId']] = item['status'] == 'completed';
            }
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOnlineChecklists() async {
    String url = '${AppConstants.baseUrl}/workflow/workflow-patrol?workflowId=${widget.eventId}&userId=${widget.userdata['userId']}';
    
    if (widget.scheduledDate != null) {
      url += '&scheduledDate=${widget.scheduledDate}';
    }

    debugPrint('Fetching checklists from: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      },
    );

    debugPrint('API Response Status: ${response.statusCode}');
    debugPrint('API Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['checklists'] != null && data['checklists'] is List) {
        final checklists = List<Map<String, dynamic>>.from(data['checklists']).map((checklist) {
          if (checklist['locationCode'] is String && 
              checklist['locationCode'].startsWith('[')) {
            try {
              checklist['locationCode'] = jsonDecode(checklist['locationCode']);
            } catch (e) {
              // Keep as string if parsing fails
            }
          }
          
          if (widget.scheduledDate != null) {
            checklist['scheduledDate'] = widget.scheduledDate;
          }
          
          return checklist;
        }).toList();

        await _offlineService.cacheWorkflows([
          EventChecklistGroup(
            workflowId: widget.eventId,
            workflowTitle: widget.eventtitle,
            status: 'pending',
            scheduledDate: widget.scheduledDate,
            checklists: checklists
                .map((c) => ChecklistItem(
                      checklistId: c['checklistId'],
                      title: c['title'],
                      status: c['status'],
                      locationCode: c['locationCode'],
                      isActive: true,
                      scheduledDate: widget.scheduledDate,
                    ))
                .toList(),
          )
        ], widget.userdata['userId']);

        return checklists;
      } else {
        debugPrint("No checklists found in response");
        return [];
      }
    } else {
      final data = jsonDecode(response.body);
      final errorMessage = data['message'] ?? "Failed to fetch patrol checklists.";
      debugPrint("API Error: $errorMessage");
      throw Exception(errorMessage);
    }
  }

  void _filterChecklists(String query) {
    setState(() {
      _filteredChecklists = _allChecklists.where((item) {
        final title = item['title']?.toString() ?? '';
        return title.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  Future<void> _sendChecklists() async {
    final selected = _selectedChecklists.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selected.isEmpty) {
      _showSnackbar("Please select at least one checklist");
      return;
    }

    try {
      for (var checklistId in selected) {
        final checklist =
            _allChecklists.firstWhere((c) => c['checklistId'] == checklistId);

        if (checklist['status'] != 'scanned' &&
            checklist['scanStartDate'] == null) {
          throw Exception(
              'Checklist ${checklist['title']} must be scanned first');
        }

        if (!_isOnline) {
          final hasMultimediaOffline =
              await _offlineService.hasMultimedia(checklistId);
          if (!hasMultimediaOffline) {
            throw Exception(
                'Checklist ${checklist['title']} requires multimedia when offline');
          }
        }
      }

      if (_isOnline) {
        await _sendChecklistsOnline(selected);
      } else {
        await _sendChecklistsOffline(selected);
      }
    } catch (e) {
      _showSnackbar("Error submitting checklists: ${e.toString()}");
    }
  }

  Future<void> _sendChecklistsOnline(List<String> selected) async {
    final message = await ApiService.completeChecklists(selected, widget.token);
    if (message != null) {
      await _offlineService.completeChecklistsOffline(selected);

      final db = await DatabaseHelper().database;
      await db.rawUpdate('''
        UPDATE checklists 
        SET isSynced = 1 
        WHERE checklistId IN (${selected.map((_) => '?').join(',')})
      ''', selected);

      await _completeWorkflow();
      _showSnackbar("Checklists submitted successfully");
      _navigateBackToDashboard();
    }
  }

  Future<void> _sendChecklistsOffline(List<String> selected) async {
    try {
      await _offlineService.completeChecklistsOffline(selected);

      final db = await DatabaseHelper().database;
      final remaining = await db.rawQuery('''
        SELECT COUNT(*) as count FROM checklists 
        WHERE workflowId = ? AND status != ?
      ''', [widget.eventId, 'completed']);

      final remainingCount = remaining.first['count'] as int;

      if (remainingCount == 0) {
        await _offlineService.completeWorkflowOffline(
            widget.eventId, '${_latitude ?? 0},${_longitude ?? 0}');
        _showSnackbar("All tasks completed - workflow saved offline");
      } else {
        _showSnackbar("Tasks partially completed ($remainingCount remaining)");
      }

      _navigateBackToDashboard();
    } catch (e) {
      _showSnackbar("Error saving offline: ${e.toString()}");
    }
  }

  Future<void> _completeWorkflow() async {
    try {
      if (_isOnline) {
        final completed = await ApiService.completeWorkflow(
          widget.eventId,
          widget.token,
          latitude: _latitude ?? 0,
          longitude: _longitude ?? 0,
        );
        if (completed) {
          await _offlineService.completeWorkflowOffline(
              widget.eventId, '${_latitude ?? 0},${_longitude ?? 0}');
          _showSnackbar("Workflow completed successfully");
        }
      } else {
        final pending =
            await _offlineService.getPendingChecklists(widget.eventId);
        if (pending.isEmpty) {
          await _offlineService.completeWorkflowOffline(
              widget.eventId, '${_latitude ?? 0},${_longitude ?? 0}');
          _showSnackbar("Workflow completed offline");
        } else {
          _showSnackbar("Complete all checklists first");
          return;
        }
      }
    } catch (e) {
      _showSnackbar("Error completing workflow: ${e.toString()}");
    }
  }

  

  Future<void> _updateChecklist(String checklistId) async {
  try {
    final checklist = _allChecklists.firstWhere(
      (c) => c['checklistId'] == checklistId,
      orElse: () => throw Exception('Checklist not found'),
    );

    if (checklist['status'] != 'scanned' && checklist['scanStartDate'] == null) {
      _showSnackbar("Checklist must be scanned first");
      return;
    }

    if (checklist['status'] == 'completed') {
      _showSnackbar("Checklist already completed");
      return;
    }

    final completionTime = DateTime.now().toUtc();

    final message = await ApiService.updateScanEndTime(
      checklistId,
      widget.token,
      endTime: completionTime.toIso8601String(),
    );

    if (mounted) {
      setState(() {
        final index = _filteredChecklists.indexWhere((c) => c['checklistId'] == checklistId);
        if (index != -1) {
          _filteredChecklists[index]['status'] = 'completed';
          _filteredChecklists[index]['scanEndDate'] = completionTime.toIso8601String();
          _selectedChecklists[checklistId] = true;
        }
        final allIndex = _allChecklists.indexWhere((c) => c['checklistId'] == checklistId);
        if (allIndex != -1) {
          _allChecklists[allIndex]['status'] = 'completed';
          _allChecklists[allIndex]['scanEndDate'] = completionTime.toIso8601String();
        }
      });
    }

    await _offlineService.updateChecklistOffline(
      checklistId,
      'completed',
      completionTime: completionTime,
    );

    _showSnackbar(message ?? "Checklist completed successfully");
  } catch (e) {
    debugPrint("Checklist update failed: $e");
    _showSnackbar("Checklist completed ");
  }
}
  void _navigateBackToDashboard() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolDashboardScreen(
          userdata: widget.userdata,
          token: widget.token,
        ),
      ),
    );
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Widget _buildChecklistItem(Map<String, dynamic> checklist) {
    final checklistId = checklist['checklistId'] ?? '';
    final title = checklist['title'] ?? '';
    final isScanned =
        checklist['status'] == 'scanned' || checklist['scanStartDate'] != null;
    final isCompleted = checklist['status'] == 'completed';
    final locationCode = checklist['locationCode'] ?? '';
    final scanStartDate = checklist['scanStartDate'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: _selectedChecklists[checklistId] ?? false,
              onChanged: null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppConstants.normalPurpleFontStyle,
                  ),
                  if (scanStartDate != null)
                    Text(
                      "Scanned at: ${DateTime.parse(scanStartDate).toLocal()}",
                      style: AppConstants.normalPurpleFontStyle
                          .copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.qr_code_scanner,
                color: !isScanned ? AppConstants.primaryColor : Colors.grey,
              ),
              onPressed: !isScanned ? () => _scanChecklist(checklist) : null,
            ),
            IconButton(
              icon: Icon(
                Icons.perm_media,
                color: !isCompleted ? AppConstants.primaryColor : Colors.grey,
              ),
              onPressed:
                  !isCompleted ? () => _addMultimedia(checklistId) : null,
            ),
            if (_isOnline) 
              IconButton(
                icon: Icon(
                  Icons.check,
                  color: isScanned && !isCompleted
                      ? AppConstants.primaryColor
                      : Colors.grey,
                ),
                onPressed: isScanned && !isCompleted
                    ? () => _updateChecklist(checklistId)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  void _scanChecklist(Map<String, dynamic> checklist) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolChecklistScanScreen(
          checklistId: checklist['checklistId'],
          scannerlocation: checklist['locationCode'],
          user: widget.userdata,
          token: widget.token,
        ),
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      final checklistId = checklist['checklistId'];
      final scanTime = result['scanStartDate'];

      setState(() {
        final filteredIndex = _filteredChecklists
            .indexWhere((c) => c['checklistId'] == checklistId);
        if (filteredIndex != -1) {
          _filteredChecklists[filteredIndex]['status'] = 'scanned';
          _filteredChecklists[filteredIndex]['scanStartDate'] = scanTime;
        }

        final allIndex =
            _allChecklists.indexWhere((c) => c['checklistId'] == checklistId);
        if (allIndex != -1) {
          _allChecklists[allIndex]['status'] = 'scanned';
          _allChecklists[allIndex]['scanStartDate'] = scanTime;
        }

        _selectedChecklists[checklistId] = false;
      });

      await _offlineService.updateChecklistScanStatus(checklistId);
    }
  }

  void _addMultimedia(String checklistId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PatrolMultimediaScreen(
          checklistId: checklistId,
          user: widget.userdata,
          token: widget.token,
          mode: 'notbymenu',
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isOnline
                ? "Multimedia uploaded"
                : "Multimedia saved offline")),
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.list_alt, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            "No checklists available",
            style: AppConstants.normalPurpleFontStyle.copyWith(fontSize: 18),
          ),
          if (!_isOnline) ...[
            const SizedBox(height: 8),
            Text(
              "Connect to the internet to load checklists",
              style: AppConstants.normalPurpleFontStyle
                  .copyWith(color: Colors.orange),
            ),
          ],
        ],
      ),
    );
  }


@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(
        widget.scheduledDate != null
            ? '${widget.eventtitle} (${widget.scheduledDate})'
            : widget.eventtitle,
        style: AppConstants.headingStyle,
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppConstants.primaryColor),
        onPressed: () => _navigateBackToDashboard(),
      ),
      actions: [
        if (!_isOnline)
          const Padding(
            padding: EdgeInsets.only(right: 8.0),
            child: Icon(Icons.wifi_off, color: Colors.orange),
          ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.green),
          tooltip: "Refresh Checklists",
          onPressed: () async {
            await _loadChecklists(); 
          },
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadChecklists,
            child: Column(
              children: [
                if (!_isOnline)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.withOpacity(0.2),
                    child: Row(
                      children: const [
                        Icon(Icons.info, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Working offline - changes will sync when online',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: "Search Checklist",
                      prefixIcon: Icon(Icons.search,
                          color: AppConstants.primaryColor),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _filterChecklists,
                  ),
                ),
                Expanded(
                  child: _allChecklists.isEmpty
                      ? _buildEmptyState()
                      : _filteredChecklists.isEmpty
                          ? Center(
                              child: Text(
                                "No matching checklists found",
                                style: AppConstants.normalPurpleFontStyle,
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredChecklists.length,
                              itemBuilder: (context, index) =>
                                  _buildChecklistItem(
                                      _filteredChecklists[index]),
                            ),
                ),
                if (_isOnline) 
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.send, color: AppConstants.primaryColor),
                      label: Text(
                        "Submit Checklists",
                        style: AppConstants.selectedButtonFontStyle,
                      ),
                      onPressed: _sendChecklists,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ),
              ],
            ),
          ),
  );
}
}
