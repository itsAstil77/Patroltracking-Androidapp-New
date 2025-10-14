import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/models/checklist.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:patroltracking/models/workflow.dart';
import 'package:flutter/foundation.dart';


class ApiService {
  static final String _baseUrl = AppConstants.baseUrl;


  static Future<bool> checkDeviceAuthorization(String deviceId) async {
    final url = Uri.parse('$_baseUrl/license/check-device');
    final body = {'deviceId': deviceId};

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authorized'] == true;
      } else {
        print('❌ Device check failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('🔥 Error during device check: $e');
      return false;
    }
  }

  static Future<String?> registerLicense({
    required String serialNumber,
    required String deviceId,
  }) async {
    final url = Uri.parse('$_baseUrl/license/register');
    final body = {
      'serialNumber': serialNumber,
      'deviceId': deviceId,
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      print('➡️ Requesting: $url');
      print('➡️ Body: $body');
      print('⬅️ Status: ${response.statusCode}');
      print('⬅️ Response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['uniqueKey']; 
      } else {
        print('License registration failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error during license registration: $e');
      return null;
    }
  }

  static Future<bool> validateLicense({
    required String serialNumber,
    required String deviceId,
    required String uniqueKey,
  }) async {
    final url = Uri.parse('$_baseUrl/license/validate');
    final body = {
      'serialNumber': serialNumber,
      'deviceId': deviceId,
      'uniqueKey': uniqueKey,
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authorized'] == true;
      }
    } catch (e) {
      print('Validation error: $e');
    }
    return false;
  }

  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final url = Uri.parse('$_baseUrl/login');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username.trim(),
          'password': password.trim(),
        }),
      );

      return {
        'status': response.statusCode,
        'body': jsonDecode(response.body),
      };
    } catch (e) {
      return {
        'status': 500,
        'body': {'success': false, 'message': 'Something went wrong!'},
      };
    }
  }

   static Future<Map<String, dynamic>> verifyOtp({
    required String username,
    required String otp,
  }) async {
    final url = Uri.parse('$_baseUrl/login/verify-otp');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'otp': otp,
        }),
      );

      return {
        'status': response.statusCode,
        'body': jsonDecode(response.body),
      };
    } catch (e) {
      return {
        'status': 500,
        'body': {'success': false, 'message': 'Something went wrong!'},
      };
    }
  }

   

static Future<List<EventChecklistGroup>> fetchGroupedChecklists(
  String patrolId, 
  String token, 
  {String? scheduledDate}
) async {
  final url = Uri.parse('$_baseUrl/checklists/grouped/$patrolId');

  try {
    debugPrint('Fetching grouped checklists for patrolId: $patrolId, Date: $scheduledDate');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    debugPrint('Response Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      final List<dynamic> dataList = jsonBody['data'] ?? [];
      
      List<EventChecklistGroup> eventGroups = [];
      
      for (var workflowData in dataList) {
        final List<dynamic> scheduledGroups = workflowData['scheduledGroups'] ?? [];
        
        if (scheduledGroups.isNotEmpty) {
          for (var scheduledGroup in scheduledGroups) {
            final String groupScheduledDate = scheduledGroup['scheduledDate'];
            
            if (scheduledDate == null || groupScheduledDate == scheduledDate) {
              final List<dynamic> checklists = scheduledGroup['checklists'] ?? [];
              
              final filteredChecklists = _filterChecklistsByDate(checklists, scheduledDate);
              
              eventGroups.add(EventChecklistGroup(
                workflowId: workflowData['workflowId'],
                workflowTitle: '${workflowData['workflowTitle']} ($groupScheduledDate)',
                status: workflowData['status']?.toLowerCase() ?? 'pending',
                assignedStart: workflowData['AssignedStart'] != null 
                  ? DateTime.parse(workflowData['AssignedStart']) 
                  : null,
                assignedEnd: workflowData['AssignedEnd'] != null 
                  ? DateTime.parse(workflowData['AssignedEnd']) 
                  : null,
                scheduledDate: groupScheduledDate,
                checklists: filteredChecklists,
              ));
            }
          }
        } 
        else {
          bool shouldInclude = true;
          
          if (scheduledDate != null) {
            try {
              final selectedDate = DateTime.parse(scheduledDate);
              final assignedStart = workflowData['AssignedStart'] != null 
                ? DateTime.parse(workflowData['AssignedStart']) 
                : null;
              final assignedEnd = workflowData['AssignedEnd'] != null 
                ? DateTime.parse(workflowData['AssignedEnd']) 
                : null;
              
              if (assignedStart != null && assignedEnd != null) {
                final selectedDateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
                final startDateOnly = DateTime(assignedStart.year, assignedStart.month, assignedStart.day);
                final endDateOnly = DateTime(assignedEnd.year, assignedEnd.month, assignedEnd.day);
                
                shouldInclude = (selectedDateOnly.isAtSameMomentAs(startDateOnly) || 
                               selectedDateOnly.isAfter(startDateOnly)) && 
                               (selectedDateOnly.isAtSameMomentAs(endDateOnly) || 
                               selectedDateOnly.isBefore(endDateOnly));
              }
              else {
                shouldInclude = false;
              }
            } catch (e) {
              debugPrint('Date parsing error: $e');
              shouldInclude = false;
            }
          }
          
          if (scheduledDate == null || shouldInclude) {
            final List<dynamic> checklists = workflowData['checklists'] ?? [];
            
            final filteredChecklists = _filterChecklistsByDate(checklists, scheduledDate);
            
            eventGroups.add(EventChecklistGroup(
              workflowId: workflowData['workflowId'],
              workflowTitle: workflowData['workflowTitle'],
              status: workflowData['status']?.toLowerCase() ?? 'pending',
              assignedStart: workflowData['AssignedStart'] != null 
                ? DateTime.parse(workflowData['AssignedStart']) 
                : null,
              assignedEnd: workflowData['AssignedEnd'] != null 
                ? DateTime.parse(workflowData['AssignedEnd']) 
                : null,
              scheduledDate: null,
              checklists: filteredChecklists,
            ));
          }
        }
      }
      
      debugPrint('Total event groups created: ${eventGroups.length}');
      return eventGroups;
    } else if (response.statusCode == 404) {
      debugPrint('No checklists found for patrolId: $patrolId');
      return [];
    } else {
      throw Exception(
          'Failed to load grouped checklists: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    debugPrint('Error fetching grouped checklists: $e');
    throw Exception('Error fetching grouped checklists: $e');
  }
}

static List<ChecklistItem> _filterChecklistsByDate(
    List<dynamic> checklists, String? selectedDate) {

  if (selectedDate == null) {
    return checklists.map((c) => ChecklistItem.fromJson(c)).toList();
  }

  final selected = DateTime.parse(selectedDate);

  return checklists.map((c) => ChecklistItem.fromJson(c)).where((checklist) {
    if (checklist.scheduledDate != null) {
      final scheduled = DateTime.parse(checklist.scheduledDate!);
      return scheduled.year == selected.year &&
             scheduled.month == selected.month &&
             scheduled.day == selected.day;
    }

    if (checklist.assignedStart != null && checklist.assignedEnd != null) {
      final start = DateTime(checklist.assignedStart!.year, checklist.assignedStart!.month, checklist.assignedStart!.day);
      final end = DateTime(checklist.assignedEnd!.year, checklist.assignedEnd!.month, checklist.assignedEnd!.day);

      return (selected.isAtSameMomentAs(start) || selected.isAfter(start)) &&
             (selected.isAtSameMomentAs(end) || selected.isBefore(end));
    }

    return false; 
  }).toList();
}

static Future<List<EventChecklistGroup>> fetchGroupedChecklistsAlternative(
  String patrolId, 
  String token, 
  {String? scheduledDate}
) async {
  final url = Uri.parse('$_baseUrl/checklists/grouped/$patrolId');

  try {
    debugPrint('Fetching ALL grouped checklists for patrolId: $patrolId, URL: $url');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    debugPrint('Response Status: ${response.statusCode}');
    debugPrint('Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      final List<dynamic> dataList = jsonBody['data'] ?? [];
      
      List<EventChecklistGroup> eventGroups = [];
      
      for (var workflowData in dataList) {
        final List<dynamic> scheduledGroups = workflowData['scheduledGroups'] ?? [];
        
        if (scheduledGroups.isNotEmpty) {
          for (var scheduledGroup in scheduledGroups) {
            final String groupScheduledDate = scheduledGroup['scheduledDate'];
            
            if (scheduledDate == null || groupScheduledDate == scheduledDate) {
              final List<dynamic> checklists = scheduledGroup['checklists'] ?? [];
              
              eventGroups.add(EventChecklistGroup(
                workflowId: workflowData['workflowId'],
                workflowTitle: '${workflowData['workflowTitle']} ($groupScheduledDate)',
                status: workflowData['status']?.toLowerCase() ?? 'pending',
                assignedStart: workflowData['AssignedStart'] != null 
                  ? DateTime.parse(workflowData['AssignedStart']) 
                  : null,
                assignedEnd: workflowData['AssignedEnd'] != null 
                  ? DateTime.parse(workflowData['AssignedEnd']) 
                  : null,
                scheduledDate: groupScheduledDate,
                checklists: checklists.map((c) => ChecklistItem.fromJson(c)).toList(),
              ));
            }
          }
        } else {
          eventGroups.add(EventChecklistGroup(
            workflowId: workflowData['workflowId'],
            workflowTitle: workflowData['workflowTitle'],
            status: workflowData['status']?.toLowerCase() ?? 'pending',
            assignedStart: workflowData['AssignedStart'] != null 
              ? DateTime.parse(workflowData['AssignedStart']) 
              : null,
            assignedEnd: workflowData['AssignedEnd'] != null 
              ? DateTime.parse(workflowData['AssignedEnd']) 
              : null,
            scheduledDate: null,
            checklists: [],
          ));
        }
      }
      
      debugPrint('Total event groups created: ${eventGroups.length}');
      return eventGroups;
    } else if (response.statusCode == 404) {
      debugPrint('No checklists found for patrolId: $patrolId');
      return [];
    } else {
      throw Exception(
          'Failed to load grouped checklists: ${response.statusCode} - ${response.body}');
    }
  } catch (e) {
    debugPrint('Error fetching grouped checklists: $e');
    throw Exception('Error fetching grouped checklists: $e');
  }
}

static Future<bool> startWorkflow(
  String workflowId, 
  String token, {
  required double latitude,
  required double longitude,
  DateTime? startTime,
}) async {
  final url = Uri.parse('$_baseUrl/workflow/start/$workflowId');
  
  final startTimeToUse = (startTime ?? DateTime.now()).toUtc();

  final body = jsonEncode({
    'startDateTime': startTimeToUse.toIso8601String(),
    'startCoordinate': '$latitude,$longitude',
    'isOfflineSync': startTime != null, 
  });

  try {
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      debugPrint('Server error: ${response.statusCode} - ${response.body}');
      return false;
    }
  } catch (e) {
    debugPrint('Network error: $e');
    return false;
  }
}

  static Future<Map<String, dynamic>?> fetchLocationByCode(
      String locationCode) async {
    final url = Uri.parse('$_baseUrl/locationcode/$locationCode');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        print("Failed to fetch location. Status: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("API error: $e");
      return null;
    }
  }




static Future<Map<String, dynamic>> submitScan({
  required String scanType,
  required String checklistId,
  required String token,
  required double latitude,
  required double longitude,
  String? scanStartDate,
  String? scannedLocationCode, 
}) async {
  final url = Uri.parse("$_baseUrl/scanning");

  final requestBody = {
    "scanType": scanType,
    "checklistId": checklistId,
    "coordinates": '$latitude,$longitude',
    "scanStartDate": scanStartDate ?? DateTime.now().toUtc().toIso8601String(),
  };

  if (scannedLocationCode != null) {
    requestBody["scannedLocationCode"] = scannedLocationCode;
  }

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
    body: jsonEncode(requestBody),
  );

  if (response.statusCode == 200) {
    final responseData = jsonDecode(response.body);
    responseData['scanStartDate'] = scanStartDate ?? DateTime.now().toUtc().toIso8601String();
    return responseData;
  } else {
    throw Exception("Failed to submit scan. Status: ${response.statusCode}");
  }
}





static Future<List<Map<String, dynamic>>> fetchWorkflowPatrolChecklists({
  required String workflowId,
  required String patrolId,
  required String token,
}) async {
  final url = Uri.parse(
      "$_baseUrl/workflow/workflow-patrol?workflowId=$workflowId&userId=$patrolId");

  print("API Request: $url");

  final response = await http.get(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
  );

  print("API Response Status: ${response.statusCode}");
  print("API Response Body: ${response.body}");

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);

    if (data['checklists'] != null && data['checklists'] is List) {
      return List<Map<String, dynamic>>.from(data['checklists']).map((checklist) {
        if (checklist['locationCode'] is String && 
            checklist['locationCode'].startsWith('[')) {
          try {
            checklist['locationCode'] = jsonDecode(checklist['locationCode']);
          } catch (e) {
          }
        }
        return checklist;
      }).toList();
    } else {
      print("No checklists found in response");
      return [];
    }
  } else {
    final data = jsonDecode(response.body);
    final errorMessage =
        data['message'] ?? "Failed to fetch patrol checklists.";
    print("API Error: $errorMessage");
    throw Exception(errorMessage);
  }
}

Future<http.Response> uploadMultimedia({
  required String token,
  required String checklistId,
  required File mediaFile,
  required String mediaType,
  required String description,
  required String patrolId,
  required String createdBy,
  required double latitude,
  required double longitude,
  required
}) async {
  try {
    final uri = Uri.parse('$_baseUrl/media');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(mediaFile.path)?.split('/');
    if (mimeType == null) throw Exception("Unknown mime type");

    request.fields['checklistId'] = checklistId;
    request.fields['mediaType'] = mediaType;
    request.fields['description'] = description;
    request.fields['userId'] = patrolId;
    request.fields['createdBy'] = createdBy;
    request.fields['coordinates'] = '$latitude,$longitude';

    request.files.add(await http.MultipartFile.fromPath(
      'mediaFile',
      mediaFile.path,
      contentType: MediaType(mimeType[0], mimeType[1]),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    debugPrint('Upload response status: ${response.statusCode}');
    if (response.statusCode == 409) {
      debugPrint('Duplicate multimedia detected by server');
    }
    
    return response;
  } catch (e) {
    debugPrint('Error in uploadMultimedia: $e');
    rethrow;
  }
}

static Future<Map<String, dynamic>> checkMultimediaStatus({
  required String checklistId,
  required String token,
}) async {
  final url = Uri.parse('$_baseUrl/media/check-status/$checklistId');
  
  try {
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      debugPrint('Failed to check multimedia status: ${response.statusCode}');
      return {'hasMultimedia': false, 'count': 0, 'types': []};
    }
  } catch (e) {
    debugPrint('Error checking multimedia status: $e');
    return {'hasMultimedia': false, 'count': 0, 'types': []};
  }
}

static Future<Map<String, dynamic>> cleanupDuplicateMultimedia({
  required String token,
}) async {
  final url = Uri.parse('$_baseUrl/media/cleanup-duplicates');
  
  try {
    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      debugPrint('Failed to cleanup duplicates: ${response.statusCode}');
      throw Exception('Cleanup failed: ${response.body}');
    }
  } catch (e) {
    debugPrint('Error cleaning up duplicates: $e');
    rethrow;
  }
}



  Future<http.Response> uploadSignature({
    required File signatureFile,
    required String patrolId,
    required String checklistId,
    required String token,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/signature');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $token';

      request.fields['userId'] = patrolId;
      request.fields['checklistId'] = checklistId;

      request.files.add(await http.MultipartFile.fromPath(
        'signatureImage',
        signatureFile.path,
        contentType: MediaType('image', 'jpg'),
      ));

      final streamedResponse = await request.send();
      return await http.Response.fromStream(streamedResponse);
    } catch (e) {
      debugPrint('Error in uploadSignature: $e');
      rethrow;
    }
  }



  static Future<String> updateScanEndTime(
  String checklistId,
  String token, {
  String? endTime,
}) async {
  final url = Uri.parse('$_baseUrl/checklists/end/$checklistId');
  final body = jsonEncode({
    'endTime': endTime ?? DateTime.now().toUtc().toIso8601String(),
  });

  try {
    final response = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    final responseBody = json.decode(response.body);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return responseBody['message'] ?? 'Checklist updated successfully';
    } else {
      debugPrint("Update failed with status: ${response.statusCode}");
      debugPrint("Body: ${response.body}");
      return responseBody['message'] ?? 'Checklist update failed';
    }
  } catch (e) {
    return 'Network error: ${e.toString()}';
  }
}



static Future<String?> completeChecklists(
  List<String> checklistIds,
  String token, {
  String? completionTime,
  String? scanStartDate,
}) async {
  final url = Uri.parse('$_baseUrl/checklists/complete');

  try {
    final response = await http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        "checklistIds": checklistIds,
        "completionTime": completionTime ?? DateTime.now().toUtc().toIso8601String(),
        "scanStartDate": scanStartDate, 
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['message'];
    }
    print('Failed to complete checklists: ${response.statusCode}');
    return null;
  } catch (e) {
    print('Error completing checklists: $e');
    return null;
  }
}

  static Future<bool> completeWorkflow(
  String workflowId, 
  String token, {
  required double latitude,
  required double longitude,
  DateTime? endTime,
}) async {
  final url = Uri.parse('$_baseUrl/workflow/done/$workflowId');
  
  final endTimeToUse = endTime ?? DateTime.now().toUtc();
  
  final body = jsonEncode({
    'endCoordinate': '$latitude,$longitude',
    'endDateTime': endTimeToUse.toIso8601String(),
  });
  
  try {
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return true;
    } else {
      print('❌ Server error: ${response.statusCode}');
      return false;
    }
  } catch (e) {
    print('❌ Exception during assignment completion: $e');
    return false;
  }
}

  static Future<List<Map<String, dynamic>>> fetchIncidents(String token) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/incidentmaster'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', 
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.cast<Map<String, dynamic>>();
    } else {
      throw Exception("Failed to load incidents");
    }
  }

  static Future<Map<String, dynamic>> sendIncidents({
    required String token,
    required String patrolId,
    required List<String> incidentCodes,
  }) async {
    final url = Uri.parse('$_baseUrl/incident');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final body = jsonEncode({
      "patrolId": patrolId,
      "incidentCodes": incidentCodes,
    });

    final response = await http.post(url, headers: headers, body: body);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to send incidents: ${response.body}");
    }
  }

  Future<List<WorkflowData>> getCompletedWorkflows(
      String patrolId, String token) async {
    final url = Uri.parse('$_baseUrl/workflow/completed/$patrolId');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List workflows =
            data['data']; 
        return workflows.map((e) => WorkflowData.fromJson(e)).toList();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to load workflows: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching completed workflows: $e');
    }
  }

  static Future<Map<String, dynamic>> sendSOSAlert({
    required String userid,
    required String remarks,
    required String token,
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse("$_baseUrl/sos");

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        "userId": userid,
        "remarks": remarks,
        "coordinates": '$latitude,$longitude',
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body); 
    } else {
      throw Exception("Failed to submit SOS. Status: ${response.statusCode}");
    }
  }
}