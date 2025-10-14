import 'package:patroltracking/services/api_service.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:developer';
import 'package:patroltracking/models/workflow.dart';
import 'package:patroltracking/models/checklist.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class OfflineService {
  final DatabaseHelper _dbHelper;

  OfflineService(this._dbHelper);

  Future<void> cacheWorkflows(List<EventChecklistGroup> workflows, String userId) async {
    final db = await _dbHelper.database;
    
    await db.transaction((txn) async {
      for (var workflow in workflows) {
        await txn.insert(
          'workflows',
          {
            'workflowId': workflow.workflowId,
            'workflowTitle': workflow.workflowTitle,
            'description': workflow.description,
            'status': workflow.status,
            'startDateTime': workflow.assignedStart?.toIso8601String(),
            'endDateTime': workflow.assignedEnd?.toIso8601String(),
            'scheduledDate': workflow.scheduledDate,
            'userId': userId,
            'isSynced': 1,
            'isOffline': 0,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (var checklist in workflow.checklists) {
          final locationCode = checklist.locationCode is List
              ? jsonEncode(checklist.locationCode)
              : checklist.locationCode?.toString() ?? '';

          await txn.insert(
            'checklists',
            {
              'checklistId': checklist.checklistId,
              'workflowId': workflow.workflowId,
              'title': checklist.title,
              'status': checklist.status,
              'locationCode': locationCode,
              'scheduledDate': workflow.scheduledDate,
              'isActive': checklist.isActive ? 1 : 0,
              'multimediaUploaded': 0, // Initialize as 0
              'isSynced': 1,
              'isOffline': 0,
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  Future<List<EventChecklistGroup>> getOfflineWorkflows(String userId, {String? scheduledDate}) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'userId = ?';
    List<dynamic> whereArgs = [userId];
    
    if (scheduledDate != null) {
      whereClause += ' AND scheduledDate = ?';
      whereArgs.add(scheduledDate);
    }
    
    final List<Map<String, dynamic>> workflowMaps = await db.query(
      'workflows',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );

    final List<EventChecklistGroup> workflows = [];
    
    for (var workflowMap in workflowMaps) {
      // Get checklists for this workflow and scheduled date
      final checklists = await getOfflineChecklistsForSchedule(
        workflowMap['workflowId'], 
        workflowMap['scheduledDate']
      );
      
      workflows.add(EventChecklistGroup(
        workflowId: workflowMap['workflowId'],
        workflowTitle: workflowMap['workflowTitle'],
        description: workflowMap['description'],
        status: workflowMap['status'],
        assignedStart: workflowMap['startDateTime'] != null 
            ? DateTime.parse(workflowMap['startDateTime']) 
            : null,
        assignedEnd: workflowMap['endDateTime'] != null 
            ? DateTime.parse(workflowMap['endDateTime']) 
            : null,
        scheduledDate: workflowMap['scheduledDate'],
        checklists: checklists.map((c) => ChecklistItem(
          checklistId: c['checklistId'],
          title: c['title'],
          status: c['status'],
          locationCode: c['locationCode'],
          isActive: c['isActive'] == 1,
          isScanned: c['scanStartDate'] != null,
          isCompleted: c['status'] == 'completed',
          scheduledDate: c['scheduledDate'],
        )).toList(),
      ));
    }
    
    return workflows;
  }

  Future<List<Map<String, dynamic>>> getOfflineChecklistsForSchedule(
    String workflowId, 
    String? scheduledDate
  ) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'workflowId = ?';
    List<dynamic> whereArgs = [workflowId];
    
    if (scheduledDate != null) {
      whereClause += ' AND scheduledDate = ?';
      whereArgs.add(scheduledDate);
    } else {
      whereClause += ' AND (scheduledDate IS NULL OR scheduledDate = "")';
    }
    
    return await db.query(
      'checklists',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getOfflineChecklists(String workflowId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'checklists',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
      orderBy: 'createdAt DESC',
    );
  }

  Future<int> startWorkflowOffline(
    String workflowId, 
    String coordinates, {
    DateTime? startTime,
  }) async {
    final db = await _dbHelper.database;
    final actualStartTime = startTime ?? DateTime.now();
    
    return await db.update(
      'workflows',
      {
        'status': 'inprogress',
        'startCoordinate': coordinates,
        'startDateTime': actualStartTime.toUtc().toIso8601String(),
        'isSynced': 0,
        'isOffline': 1,
        'modifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );
  }

  Future<int> completeWorkflowOffline(String workflowId, String coordinates) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc();
    
    return await db.update(
      'workflows',
      {
        'status': 'completed',
        'endDateTime': now.toIso8601String(),
        'endCoordinate': coordinates,
        'isSynced': 0,
        'isOffline': 1,
        'modifiedAt': now.toIso8601String(),
      },
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );
  }

  Future<int> updateChecklistOffline(String checklistId, String status, {DateTime? completionTime}) async {
    final db = await _dbHelper.database;
    final now = completionTime ?? DateTime.now().toUtc();

    final updates = {
      'status': status,
      'isSynced': 0,
      'isOffline': 1,
      'modifiedAt': now.toIso8601String(),
    };

    if (status == 'completed') {
      updates['scanEndDate'] = now.toIso8601String();
    }

    return await db.update(
      'checklists',
      updates,
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  Future<bool> hasMultimedia(String checklistId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'multimedia',
      where: 'checklistId = ?',
      whereArgs: [checklistId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> hasScan(String checklistId) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'scans',
      where: 'checklistId = ?',
      whereArgs: [checklistId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> updateChecklistScanStatus(String checklistId) async {
    final db = await _dbHelper.database;
    await db.update(
      'checklists',
      {
        'status': 'scanned',
        'scanStartDate': DateTime.now().toUtc().toIso8601String(),
        'isSynced': 0,
        'modifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  Future<int> completeChecklistsOffline(List<String> checklistIds) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toUtc().toIso8601String();
    
    return await db.rawUpdate('''
      UPDATE checklists 
      SET status = 'completed', 
          scanEndDate = ?,
          isSynced = 0,
          modifiedAt = ?,
          isOffline = 1
      WHERE checklistId IN (${checklistIds.map((_) => '?').join(',')})
    ''', [now, now, ...checklistIds]);
  }

  Future<List<Map<String, dynamic>>> getPendingChecklists(String workflowId) async {
    final db = await _dbHelper.database;
    return await db.query(
      'checklists',
      where: 'workflowId = ? AND status != ?',
      whereArgs: [workflowId, 'completed'],
    );
  }

  Future<List<Map<String, dynamic>>> getValidOfflineChecklists(
    String workflowId, 
    {String? scheduledDate}
  ) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'workflowId = ? AND status != ?';
    List<dynamic> whereArgs = [workflowId, 'completed'];
    
    if (scheduledDate != null) {
      whereClause += ' AND scheduledDate = ?';
      whereArgs.add(scheduledDate);
    } else {
      whereClause += ' AND (scheduledDate IS NULL OR scheduledDate = "")';
    }
    
    final checklists = await db.query(
      'checklists',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'status ASC, scanStartDate DESC, title ASC', 
    );

    return checklists.map((checklist) {
      final locationCodeRaw = checklist['locationCode'] as String?;
      dynamic locationCode;
      if (locationCodeRaw != null) {
        try {
          locationCode = jsonDecode(locationCodeRaw);
        } catch (e) {
          locationCode = locationCodeRaw;
        }
      } else {
        locationCode = '';
      }
      return {
        ...checklist,
        'locationCode': locationCode,
      };
    }).toList();
  }

  Future<void> syncOnlineCompletions(String workflowId, String token, String patrolId) async {
    final db = await _dbHelper.database;
    try {
      final updatedChecklists = await ApiService.fetchWorkflowPatrolChecklists(
        workflowId: workflowId,
        patrolId: patrolId,
        token: token,
      );

      await db.transaction((txn) async {
        for (final checklist in updatedChecklists) {
          final locationCode = checklist['locationCode'] is List
              ? jsonEncode(checklist['locationCode'])
              : checklist['locationCode']?.toString() ?? '';

          // Check if multimedia exists in database for this checklist
          final multimediaResult = await txn.query(
            'multimedia',
            where: 'checklistId = ?',
            whereArgs: [checklist['checklistId']],
            limit: 1,
          );
          
          final hasMultimedia = multimediaResult.isNotEmpty;

          await txn.update(
            'checklists',
            {
              'status': checklist['status'],
              'scanStartDate': checklist['scanStartDate'],
              'scanEndDate': checklist['scanEndDate'],
              'locationCode': locationCode,
              'multimediaUploaded': hasMultimedia ? 1 : 0,
              'isSynced': 1,
              'isOffline': 0,
              'syncedAt': DateTime.now().toUtc().toIso8601String(),
              'modifiedAt': DateTime.now().toUtc().toIso8601String(),
            },
            where: 'checklistId = ?',
            whereArgs: [checklist['checklistId']],
          );
        }
      });
    } catch (e) {
      debugPrint('Error syncing online completions: $e');
    }
  }

  Future<bool> areAllChecklistsCompletedForSchedule(
    String workflowId, 
    String scheduledDate
  ) async {
    final db = await _dbHelper.database;
    
    final pendingChecklists = await db.query(
      'checklists',
      where: 'workflowId = ? AND scheduledDate = ? AND status != ?',
      whereArgs: [workflowId, scheduledDate, 'completed'],
    );
    
    return pendingChecklists.isEmpty;
  }

  Future<List<String>> getScheduledDatesForWorkflow(String workflowId) async {
    final db = await _dbHelper.database;
    
    final result = await db.rawQuery('''
      SELECT DISTINCT scheduledDate 
      FROM checklists 
      WHERE workflowId = ? AND scheduledDate IS NOT NULL AND scheduledDate != ''
      ORDER BY scheduledDate ASC
    ''', [workflowId]);
    
    return result.map((row) => row['scheduledDate'] as String).toList();
  }

  Future<List<ChecklistItem>> getChecklistsForWorkflow(String workflowId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'checklists',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );
    
    return List.generate(maps.length, (i) {
      return ChecklistItem(
        checklistId: maps[i]['checklistId'],
        title: maps[i]['title'],
        status: maps[i]['status'],
        locationCode: maps[i]['locationCode'],
        isActive: maps[i]['isActive'] == 1,
        scheduledDate: maps[i]['scheduledDate'],
      );
    });
  }

  Future<int> saveScanOffline({
    required String checklistId,
    required String scanType,
    required String coordinates,
    String? scannedLocationCode
  }) async {
    return await _dbHelper.insertScan({
      'checklistId': checklistId,
      'scanType': scanType,
      'coordinates': coordinates,
      'scannedLocationCode': scannedLocationCode,
      'isSynced': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> saveMultimediaOffline({
    required String checklistId,
    required String userId,
    required String filePath,
    required String mediaType,
    String? description,
  }) async {
    return await _dbHelper.insertMultimedia({
      'checklistId': checklistId,
      'userId': userId,
      'filePath': filePath,
      'mediaType': mediaType,
      'description': description ?? '',
      'createdAt': DateTime.now().toIso8601String(),
      'isSynced': 0,
    });
  }

  Future<int> saveSOSOffline({
    required String userId,
    required String remarks,
    required String coordinates,
  }) async {
    return await _dbHelper.insertSOS({
      'userId': userId,
      'remarks': remarks,
      'coordinates': coordinates,
      'isSynced': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> saveIncidentOffline({
    required String patrolId,
    required List<String> incidentCodes,
  }) async {
    return await _dbHelper.insertIncident({
      'patrolId': patrolId,
      'incidentCodes': incidentCodes.join(','),
      'isSynced': 0,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  

  // New method to update multimedia status for a checklist
  Future<void> updateChecklistMultimediaStatus(String checklistId, bool hasMultimedia) async {
    final db = await _dbHelper.database;
    await db.update(
      'checklists',
      {
        'multimediaUploaded': hasMultimedia ? 1 : 0,
        'modifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }
}