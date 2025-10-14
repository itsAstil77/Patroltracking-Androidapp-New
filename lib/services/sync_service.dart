import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:collection'; 
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart'; 





class SyncService {
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;
  final ApiService _apiService;
  final SharedPreferences _prefs;

  static const _maxRetryAttempts = 3;
  static const _initialRetryDelay = Duration(seconds: 2);
  static const _syncTimeout = Duration(seconds: 30);
  static const _maxConcurrentUploads = 2;

  static SyncService? _instance;
  
  factory SyncService({
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
    required ApiService apiService,
    required SharedPreferences prefs,
  }) {
    _instance ??= SyncService._internal(
      dbHelper: dbHelper,
      connectivity: connectivity,
      apiService: apiService,
      prefs: prefs,
    );
    return _instance!;
  }
  
  SyncService._internal({
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
      debugPrint('🔄 Starting sync process...');
      
      await _syncWorkflows(token);
      await _syncScans(token);
      await _syncChecklists(token);
      await _syncIncidents(token);
      await _syncSOS(token);
      await _syncMultimedia(token);  // FIXED: Now with deduplication
      await _syncSignatures(token);

      await _dbHelper.cleanupSyncedMultimedia();
      await _dbHelper.cleanupSyncedSignatures();
      
      debugPrint('✅ Sync completed successfully');
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
      rethrow;
    }
  }

  Future<void> _syncMultimedia(String token) async {
  final pending = await _dbHelper.getPendingMultimedia();
  debugPrint('🔄 Syncing ${pending.length} multimedia items...');
  
  // FIXED: Enhanced duplicate detection with file content checking
  final uniqueItems = await _removeDuplicateMultimedia(pending);
  debugPrint('📊 After deduplication: ${uniqueItems.length} unique items to upload');

  final semaphore = Semaphore(_maxConcurrentUploads);
  final futures = <Future>[];

  for (final item in uniqueItems) {
    final future = _processMultimediaItemWithSemaphore(item, token, semaphore);
    futures.add(future);
  }

  await Future.wait(futures, eagerError: false);
}

// FIXED: Enhanced duplicate removal based on actual file content
Future<List<Map<String, dynamic>>> _removeDuplicateMultimedia(
  List<Map<String, dynamic>> pendingItems,
) async {
  final uniqueItems = <String, Map<String, dynamic>>{};
  final seenFileHashes = <String>{};

  for (final item in pendingItems) {
    try {
      final filePath = item['filePath'] as String;
      final file = File(filePath);
      
      if (!await file.exists()) {
        debugPrint('🗑️ Skipping missing file: $filePath');
        await _dbHelper.deleteMultimedia(item['id']);
        continue;
      }

      // Generate file hash for content-based duplicate detection
      final fileBytes = await file.readAsBytes();
      final fileHash = _generateFileHash(fileBytes);
      final fileSize = fileBytes.length;

      // Create unique key: checklistId + fileHash + fileSize
      final uniqueKey = '${item['checklistId']}_${item['mediaType']}_$fileHash';
      
      if (!seenFileHashes.contains(uniqueKey)) {
        uniqueItems[item['id'].toString()] = item;
        seenFileHashes.add(uniqueKey);
        
        // Mark potential duplicates for cleanup
        for (final existingItem in pendingItems) {
          if (existingItem['id'] != item['id']) {
            final existingFilePath = existingItem['filePath'] as String;
            final existingFile = File(existingFilePath);
            
            if (await existingFile.exists()) {
              final existingBytes = await existingFile.readAsBytes();
              final existingHash = _generateFileHash(existingBytes);
              
              if (existingHash == fileHash) {
                debugPrint('⚠️ Found duplicate file: ${existingItem['id']}');
                await _dbHelper.deleteMultimedia(existingItem['id']);
              }
            }
          }
        }
      } else {
        debugPrint('⏭️ Skipping duplicate multimedia ${item['id']} (same content)');
        await _dbHelper.deleteMultimedia(item['id']);
      }
    } catch (e) {
      debugPrint('❌ Error processing multimedia ${item['id']}: $e');
    }
  }

  return uniqueItems.values.toList();
}

String _generateFileHash(Uint8List bytes) {
  final digest = md5.convert(bytes);
  return digest.toString();
}

  Future<void> _processMultimediaItemWithSemaphore(
    Map<String, dynamic> item, 
    String token, 
    Semaphore semaphore
  ) async {
    await semaphore.acquire();
    try {
      await _processWithRetry('Multimedia ${item['id']}', () async {
        final file = File(item['filePath'] as String);
        if (!await file.exists()) {
          await _dbHelper.deleteMultimedia(item['id']);
          debugPrint('🗑️ Deleted missing multimedia file ${item['id']}');
          return;
        }

        // FIXED: Check if already synced using local database flag
        if (item['isSynced'] == 1) {
          debugPrint('⏭️ Multimedia ${item['id']} already marked as synced - skipping');
          return;
        }

        // REMOVED: Server-side duplicate check that was preventing multiple files of same type
        // The backend will handle true duplicates via the 409 response

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
          
          // FIXED: Update checklist multimedia flag immediately after successful upload
          await _dbHelper.update(
            table: 'checklists',
            values: {
              'multimediaUploaded': 1,
              'modifiedAt': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'checklistId = ?',
            whereArgs: [item['checklistId']],
          );
          
          debugPrint('✅ Successfully synced multimedia ${item['id']} (${item['mediaType']})');
        } else if (response.statusCode == 409) {
          // FIXED: Handle duplicate response from server (true duplicate, not just same type)
          debugPrint('⚠️ Multimedia ${item['id']} already exists on server - marking as synced');
          await _dbHelper.updateMultimediaSyncStatus(item['id'], isSuccess: true);
        } else {
          throw Exception('Upload failed with status ${response.statusCode}');
        }
      });
    } catch (e) {
      await _dbHelper.recordSyncAttempt('multimedia', item['id']);
      debugPrint('❌ Failed to sync multimedia ${item['id']}: $e');
    } finally {
      semaphore.release();
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // FIXED: Enhanced method to check if multimedia already uploaded
  Future<bool> _checkMultimediaAlreadyUploaded(String checklistId, String mediaType) async {
    // First check local database
    final db = await _dbHelper.database;
    final localResult = await db.query(
      'multimedia',
      where: 'checklistId = ? AND mediaType = ? AND isSynced = 1',
      whereArgs: [checklistId, mediaType],
      limit: 1,
    );
    
    if (localResult.isNotEmpty) {
      debugPrint('⏭️ Local check: Multimedia already synced for $checklistId ($mediaType)');
      return true;
    }
    
    // If online, also check server
    try {
      final token = _prefs.getString('auth_token');
      if (token != null) {
        final serverStatus = await ApiService.checkMultimediaStatus(
          checklistId: checklistId,
          token: token,
        );
        
        if (serverStatus['hasMultimedia'] == true) {
          final types = List<String>.from(serverStatus['types'] ?? []);
          if (types.contains(mediaType)) {
            debugPrint('⏭️ Server check: Multimedia already exists for $checklistId ($mediaType)');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Server check failed, relying on local database: $e');
    }
    
    return false;
  }

  // Keep all other existing methods unchanged...
  Future<void> _syncWorkflows(String token) async {
    final pending = await _dbHelper.getPendingWorkflows();
    debugPrint('🔄 Syncing ${pending.length} workflows...');
    
    for (final item in pending) {
      try {
        await _processWithRetry('Workflow ${item['workflowId']}', () async {
          final checklists = await _dbHelper.getChecklistsByWorkflow(item['workflowId']);
          final allSynced = checklists.every((c) => c['status'] != 'completed' || c['isSynced'] == 1);

          if (!allSynced && item['status'] == 'completed') {
            debugPrint('⏳ Not all checklists synced for workflow ${item['workflowId']}');
            return;
          }

          if (item['status'] == 'inprogress' && item['startDateTime'] != null) {
            final coordinates = item['startCoordinate']?.split(',');
            if (coordinates == null || coordinates.length != 2) {
              debugPrint('❌ Invalid coordinates for workflow ${item['workflowId']}');
              return;
            }

            final startTime = DateTime.parse(item['startDateTime']);
            final latitude = double.tryParse(coordinates[0]);
            final longitude = double.tryParse(coordinates[1]);

            if (latitude == null || longitude == null) {
              debugPrint('❌ Invalid coordinate values for workflow ${item['workflowId']}');
              return;
            }

            final response = await ApiService.startWorkflow(
              item['workflowId'],
              token,
              latitude: latitude,
              longitude: longitude,
              startTime: startTime,
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
              debugPrint('✅ Successfully synced workflow ${item['workflowId']}');
            }
          } else if (item['status'] == 'completed' && item['endDateTime'] != null) {
            final coordinates = item['endCoordinate']?.split(',');
            if (coordinates == null || coordinates.length != 2) {
              debugPrint('❌ Invalid end coordinates for workflow ${item['workflowId']}');
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
              debugPrint('✅ Successfully completed workflow ${item['workflowId']}');
            }
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('workflows', item['id']);
        debugPrint('❌ Failed to sync workflow ${item['workflowId']}: $e');
      }
    }
  }

  Future<void> _syncChecklists(String token) async {
    final pending = await _dbHelper.getPendingChecklists();
    debugPrint('🔄 Syncing ${pending.length} checklists...');
    
    for (final item in pending) {
      try {
        await _processWithRetry('Checklist ${item['checklistId']}', () async {
          if (item['status'] == 'completed' && item['scanEndDate'] != null) {
            final completionTime = DateTime.parse(item['scanEndDate']);
            final scanStartDate = item['scanStartDate'] != null ? DateTime.parse(item['scanStartDate']).toIso8601String() : null;

            final scans = await _dbHelper.getPendingScans();
            final scan = scans.firstWhere(
              (s) => s['checklistId'] == item['checklistId'],
              orElse: () => throw Exception('No scan found for checklist ${item['checklistId']}'),
            );
            final coordinates = scan['coordinates']?.split(',');
            if (coordinates == null || coordinates.length != 2) {
              throw Exception('Invalid coordinates for checklist ${item['checklistId']}');
            }

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

            final completeResponse = await ApiService.completeChecklists(
              [item['checklistId']],
              token,
              completionTime: completionTime.toIso8601String(),
              scanStartDate: scanStartDate,
            ).timeout(_syncTimeout);

            if (completeResponse != null) {
              await _dbHelper.updateChecklistSyncStatus(item['id']);
              await _dbHelper.updateChecklistCompletionTime(item['checklistId'], completionTime: completionTime);
              debugPrint('✅ Successfully synced checklist ${item['checklistId']}');
            }
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('checklists', item['id']);
        debugPrint('❌ Failed to sync checklist ${item['checklistId']}: $e');
      }
    }
  }

  Future<void> _syncScans(String token) async {
    final pending = await _dbHelper.getPendingScans();
    debugPrint('🔄 Syncing ${pending.length} scans...');
    
    for (final item in pending) {
      try {
        await _processWithRetry('Scan for ${item['checklistId']}', () async {
          final coordinates = item['coordinates']?.split(',');
          if (coordinates == null || coordinates.length != 2) return;

          final scanTime = item['createdAt'] != null
              ? DateTime.parse(item['createdAt'])
              : DateTime.now();

          final response = await ApiService.submitScan(
            scanType: item['scanType'],
            checklistId: item['checklistId'],
            token: token,
            latitude: double.parse(coordinates[0]),
            longitude: double.parse(coordinates[1]),
            scanStartDate: scanTime.toIso8601String(),
          ).timeout(_syncTimeout);

          if (response['message'] == "Scan recorded and checklist updated successfully") {
            await _dbHelper.updateScanSyncStatus(item['id']);
            await _dbHelper.updateChecklistScanTime(
              item['checklistId'],
              scanTime: scanTime,
            );
            debugPrint('✅ Successfully synced scan for checklist ${item['checklistId']}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('scans', item['id']);
        debugPrint('❌ Failed to sync scan for checklist ${item['checklistId']}: $e');
      }
    }
  }

  Future<void> _syncIncidents(String token) async {
    final pending = await _dbHelper.getPendingIncidents();
    debugPrint('🔄 Syncing ${pending.length} incidents...');
    
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
            debugPrint('✅ Successfully synced incident for patrol ${item['patrolId']}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('incidents', item['id']);
        debugPrint('❌ Failed to sync incidents for patrol ${item['patrolId']}: $e');
      }
    }
  }

  Future<void> _syncSOS(String token) async {
    final pending = await _dbHelper.getPendingSOS();
    debugPrint('🔄 Syncing ${pending.length} SOS alerts...');
    
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
            debugPrint('✅ Successfully synced SOS alert for user ${item['userId']}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('sos', item['id']);
        debugPrint('❌ Failed to sync SOS alert for user ${item['userId']}: $e');
      }
    }
  }

  Future<void> _syncSignatures(String token) async {
    final pending = await _dbHelper.getPendingSignatures();
    debugPrint('🔄 Syncing ${pending.length} signatures...');
    
    for (final item in pending) {
      try {
        await _processWithRetry('Signature ${item['id']}', () async {
          final file = File(item['filePath'] as String);
          if (!await file.exists()) {
            await _dbHelper.deleteSignature(item['id']);
            debugPrint('🗑️ Deleted missing signature file ${item['id']}');
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
            debugPrint('✅ Successfully synced signature ${item['id']}');
          } else {
            throw Exception('Upload failed with status ${response.statusCode}');
          }
        });
      } catch (e) {
        await _dbHelper.recordSyncAttempt('signatures', item['id']);
        debugPrint('❌ Failed to sync signature ${item['id']}: $e');
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

  

  Future<void> syncMultimediaStatus(String token) async {
    try {
      final pendingMultimedia = await _dbHelper.getPendingMultimedia();
      
      for (final multimedia in pendingMultimedia) {
        await _dbHelper.update(
          table: 'checklists',
          values: {
            'multimediaUploaded': 1,
            'modifiedAt': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'checklistId = ?',
          whereArgs: [multimedia['checklistId']],
        );
      }
    } catch (e) {
      debugPrint('Error syncing multimedia status: $e');
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
      debugPrint('✅ Refreshed checklist cache for workflow $workflowId');
    } catch (e) {
      debugPrint('❌ Error refreshing checklist cache: $e');
    }
  }
}

class Semaphore {
  final int _maxPermits;
  int _currentPermits;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  Semaphore(this._maxPermits) : _currentPermits = _maxPermits;

  Future<void> acquire() {
    if (_currentPermits > 0) {
      _currentPermits--;
      return Future.value();
    } else {
      final completer = Completer<void>();
      _waiting.add(completer);
      return completer.future;
    }
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _currentPermits = (_currentPermits + 1).clamp(0, _maxPermits);
    }
  }
}
