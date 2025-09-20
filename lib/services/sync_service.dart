import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncService {
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;
  final ApiService _apiService;
  final SharedPreferences _prefs;

  static const _maxRetryAttempts = 3;
  static const _initialRetryDelay = Duration(seconds: 1);
  static const _syncTimeout = Duration(seconds: 15);

  SyncService({
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
    required ApiService apiService,
    required SharedPreferences prefs,
  })  : _dbHelper = dbHelper,
        _connectivity = connectivity,
        _apiService = apiService,
        _prefs = prefs;

  Future<void> syncPendingData() async {
    if (!await _hasNetworkConnection()) {
      throw Exception('No network connection');
    }

    final token = _prefs.getString('auth_token');
    if (token == null) {
      throw Exception('No auth token');
    }

    try {
      await _syncWorkflows(token);
      await _syncChecklists(token);
      await _syncScans(token);
      await _syncIncidents(token);
      await _syncSOS(token);
      await _syncMultimedia(token);
      await _syncSignatures(token);

      await _dbHelper.cleanupSyncedMultimedia();
      await _dbHelper.cleanupSyncedSignatures();
    } catch (e) {
      debugPrint('Sync failed: $e');
      rethrow;
    }
  }

  


Future<void> _syncWorkflows(String token) async {
  final pending = await _dbHelper.getPendingWorkflows();
  for (final item in pending) {
    try {
      await _processWithRetry('Workflow ${item['workflowId']}', () async {
        // Check if all checklists are synced (if required)
        final checklists = await _dbHelper.getChecklistsByWorkflow(item['workflowId']);
        final allSynced = checklists.every((c) => c['status'] != 'completed' || c['isSynced'] == 1);

        if (!allSynced && item['status'] == 'completed') {
          debugPrint('Not all checklists synced for workflow ${item['workflowId']}');
          return;
        }

        if (item['status'] == 'inprogress' && item['startDateTime'] != null) {
          final coordinates = item['startCoordinate']?.split(',');
          if (coordinates == null || coordinates.length != 2) {
            debugPrint('Invalid coordinates for workflow ${item['workflowId']}');
            return;
          }

          final startTime = DateTime.parse(item['startDateTime']);
          final latitude = double.tryParse(coordinates[0]);
          final longitude = double.tryParse(coordinates[1]);

          if (latitude == null || longitude == null) {
            debugPrint('Invalid coordinate values for workflow ${item['workflowId']}');
            return;
          }

          final response = await ApiService.startWorkflow(
            item['workflowId'],
            token,
            latitude: latitude,
            longitude: longitude,
            startTime: startTime, // Use the original offline start time
          ).timeout(_syncTimeout);

          if (response) {
            await _dbHelper.updateWorkflowSyncStatus(item['id']);
            await _dbHelper.update(
              table: 'workflows',
              values: {
                'isOffline': 0, // Mark as no longer offline-originated
                'isSynced': 1,
                'syncedAt': DateTime.now().toUtc().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [item['id']],
            );
            debugPrint('Successfully synced workflow ${item['workflowId']}');
          }
        } else if (item['status'] == 'completed' && item['endDateTime'] != null) {
          final coordinates = item['endCoordinate']?.split(',');
          if (coordinates == null || coordinates.length != 2) {
            debugPrint('Invalid end coordinates for workflow ${item['workflowId']}');
            return;
          }

          final response = await ApiService.completeWorkflow(
            item['workflowId'],
            token,
            latitude: double.parse(coordinates[0]),
            longitude: double.parse(coordinates[1]),
            endTime: DateTime.parse(item['endDateTime']),
          ).timeout(_syncTimeout);

          if (response) {
            await _dbHelper.updateWorkflowSyncStatus(item['id']);
            await _dbHelper.update(
              table: 'workflows',
              values: {
                'isOffline': 0,
                'isSynced': 1,
                'syncedAt': DateTime.now().toUtc().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [item['id']],
            );
          }
        }
      });
    } catch (e) {
      await _dbHelper.recordSyncAttempt('workflows', item['id']);
      debugPrint('Failed to sync workflow ${item['workflowId']}: $e');
    }
  }
}




Future<void> _syncChecklists(String token) async {
  final pending = await _dbHelper.getPendingChecklists();
  for (final item in pending) {
    try {
      await _processWithRetry('Checklist ${item['checklistId']}', () async {
        if (item['status'] == 'completed' && item['scanEndDate'] != null) {
          final completionTime = DateTime.parse(item['scanEndDate']);
          final scanStartDate = item['scanStartDate'] != null ? DateTime.parse(item['scanStartDate']).toIso8601String() : null;

          // Fetch scan details for coordinates
          final scans = await _dbHelper.getPendingScans();
          final scan = scans.firstWhere(
            (s) => s['checklistId'] == item['checklistId'],
            orElse: () => throw Exception('No scan found for checklist ${item['checklistId']}'),
          );
          final coordinates = scan['coordinates']?.split(',');
          if (coordinates == null || coordinates.length != 2) {
            throw Exception('Invalid coordinates for checklist ${item['checklistId']}');
          }

          // Submit scan if not already synced
          if (scan['isSynced'] == 0) {
            final response = await ApiService.submitScan(
              scanType: scan['scanType'],
              checklistId: item['checklistId'],
              token: token,
              latitude: double.parse(coordinates[0]),
              longitude: double.parse(coordinates[1]),
              scanStartDate: scanStartDate ?? DateTime.now().toUtc().toIso8601String(),
            ).timeout(_syncTimeout);

            if (response['message'] == "Scan recorded and checklist updated successfully") {
              await _dbHelper.updateScanSyncStatus(scan['id']);
              await _dbHelper.updateChecklistScanTime(item['checklistId'], scanTime: DateTime.parse(scanStartDate ?? DateTime.now().toUtc().toIso8601String()));
            }
          }

          // Complete the checklist
          final completeResponse = await ApiService.completeChecklists(
            [item['checklistId']],
            token,
            completionTime: completionTime.toIso8601String(),
            scanStartDate: scanStartDate,
          ).timeout(_syncTimeout);

          if (completeResponse != null) {
            await _dbHelper.updateChecklistSyncStatus(item['id']);
            await _dbHelper.updateChecklistCompletionTime(item['checklistId'], completionTime: completionTime);
          }
        }
      });
    } catch (e) {
      await _dbHelper.recordSyncAttempt('checklists', item['id']);
      debugPrint('Failed to sync checklist ${item['checklistId']}: $e');
    }
  }
}

Future<void> _syncScans(String token) async {
  final pending = await _dbHelper.getPendingScans();
  for (final item in pending) {
    try {
      await _processWithRetry('Scan for ${item['checklistId']}', () async {
        final coordinates = item['coordinates']?.split(',');
        if (coordinates == null || coordinates.length != 2) return;

        // Use the original scan time from offline storage
        final scanTime = item['createdAt'] != null
            ? DateTime.parse(item['createdAt'])
            : DateTime.now();

        final response = await ApiService.submitScan(
          scanType: item['scanType'],
          checklistId: item['checklistId'],
          token: token,
          latitude: double.parse(coordinates[0]),
          longitude: double.parse(coordinates[1]),
          scanStartDate: scanTime.toIso8601String(), // Pass original time
        ).timeout(_syncTimeout);

        if (response['message'] == "Scan recorded and checklist updated successfully") {
          await _dbHelper.updateScanSyncStatus(item['id']);
          
          // Also update the checklist's scanStartDate if needed
          await _dbHelper.updateChecklistScanTime(
            item['checklistId'],
            scanTime: scanTime,
          );
        }
      });
    } catch (e) {
      await _dbHelper.recordSyncAttempt('scans', item['id']);
      debugPrint('Failed to sync scan for checklist ${item['checklistId']}: $e');
    }
  }
}

  Future<void> _syncIncidents(String token) async {
    final pending = await _dbHelper.getPendingIncidents();
    for (final item in pending) {
      try {
        await _processWithRetry('Incident for ${item['patrolId']}', () async {
          final incidentCodes = (item['incidentCodes'] as String).split(',');
          final response = await ApiService.sendIncidents(
            token: token,
            patrolId: item['patrolId'],
            incidentCodes: incidentCodes,
          ).timeout(_syncTimeout);

          if (response['success'] == true) {
            await _dbHelper.updateIncidentSyncStatus(item['id']);
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('incidents', item['id']);
        debugPrint('Failed to sync incidents for patrol ${item['patrolId']}: $e');
      }
    }
  }

  Future<void> _syncSOS(String token) async {
    final pending = await _dbHelper.getPendingSOS();
    for (final item in pending) {
      try {
        await _processWithRetry('SOS for ${item['userId']}', () async {
          final coordinates = item['coordinates']?.split(',');
          if (coordinates == null || coordinates.length != 2) return;

          final response = await ApiService.sendSOSAlert(
            userid: item['userId'],
            remarks: item['remarks'] ?? '',
            token: token,
            latitude: double.parse(coordinates[0]),
            longitude: double.parse(coordinates[1]),
          ).timeout(_syncTimeout);

          if (response['message'] == 'SOS alert saved successfully.') {
            await _dbHelper.updateSOSSyncStatus(item['id']);
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('sos', item['id']);
        debugPrint('Failed to sync SOS alert for user ${item['userId']}: $e');
      }
    }
  }

  Future<void> _syncMultimedia(String token) async {
    final pending = await _dbHelper.getPendingMultimedia();
    for (final item in pending) {
      try {
        await _processWithRetry('Multimedia ${item['id']}', () async {
          final file = File(item['filePath'] as String);
          if (!await file.exists()) {
            await _dbHelper.deleteMultimedia(item['id']);
            return;
          }

          final response = await _apiService.uploadMultimedia(
            token: token,
            checklistId: item['checklistId'],
            mediaFile: file,
            mediaType: item['mediaType'],
            description: item['description'],
            patrolId: item['userId'],
            createdBy: item['createdBy'],
            latitude: item['latitude'],
            longitude: item['longitude'],
          ).timeout(_syncTimeout);

          if (response.statusCode == 200) {
            await _dbHelper.updateMultimediaSyncStatus(item['id'], isSuccess: true);
          } else {
            throw Exception('Upload failed with status ${response.statusCode}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('multimedia', item['id']);
        debugPrint('Failed to sync multimedia ${item['id']}: $e');
      }
    }
  }

  Future<void> _syncSignatures(String token) async {
    final pending = await _dbHelper.getPendingSignatures();
    for (final item in pending) {
      try {
        await _processWithRetry('Signature ${item['id']}', () async {
          final file = File(item['filePath'] as String);
          if (!await file.exists()) {
            await _dbHelper.deleteSignature(item['id']);
            return;
          }

          final response = await _apiService.uploadSignature(
            signatureFile: file,
            patrolId: item['userId'],
            checklistId: item['checklistId'],
            token: token,
          ).timeout(_syncTimeout);

          if (response.statusCode == 200) {
            await _dbHelper.updateSignatureSyncStatus(item['id'], isSuccess: true);
          } else {
            throw Exception('Upload failed with status ${response.statusCode}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('signatures', item['id']);
        debugPrint('Failed to sync signature ${item['id']}: $e');
      }
    }
  }

  Future<bool> hasPendingItems() async {
    final hasPending = await _dbHelper.hasPendingSyncs();
    if (hasPending) return true;

    final multimediaPending = await _dbHelper.getPendingMultimedia(limit: 1);
    final signaturesPending = await _dbHelper.getPendingSignatures(limit: 1);
    return multimediaPending.isNotEmpty || signaturesPending.isNotEmpty;
  }

  Future<void> _processWithRetry(String label, Future<void> Function() operation) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;
    
    while (attempt < _maxRetryAttempts) {
      attempt++;
      try {
        await operation().timeout(_syncTimeout);
        return;
      } catch (e) {
        debugPrint('$label sync attempt $attempt failed: $e');
        if (attempt >= _maxRetryAttempts) rethrow;
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  Future<bool> _hasNetworkConnection() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      return false;
    }
  }
  Future<void> refreshChecklistCacheFromServer({
  required String workflowId,
  required String patrolId,
  required String token,
}) async {
  try {
    final updatedChecklists = await ApiService.fetchWorkflowPatrolChecklists(
      workflowId: workflowId,
      patrolId: patrolId,
      token: token,
    );

    final db = await DatabaseHelper().database;

    await db.delete(
      'checklists',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );

    final batch = db.batch();
    for (final checklist in updatedChecklists) {
      batch.insert('checklists', {
        'checklistId': checklist['checklistId'],
        'workflowId': checklist['workflowId'],
        'title': checklist['title'],
        'status': checklist['status'],
        'locationCode': checklist['locationCode'],
        'scanStartDate': checklist['scanStartDate'] ?? '',
        'scanEndDate': checklist['scanEndDate'] ?? '',
        'isSynced': 1,
      });
    }

    await batch.commit(noResult: true);
  } catch (e) {
    debugPrint('Error refreshing checklist cache: $e');
  }
}

}