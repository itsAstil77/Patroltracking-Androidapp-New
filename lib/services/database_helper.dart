import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'patrol_tracking.db');

    return await openDatabase(
      path,
      version: 9, 
      onCreate: _onCreate, 
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE workflows (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      workflowId TEXT NOT NULL UNIQUE,
      workflowTitle TEXT NOT NULL,
      description TEXT,
      status TEXT,
      startDateTime TEXT,
      endDateTime TEXT,
      scheduledDate TEXT,
      userId TEXT,
      isSynced INTEGER DEFAULT 0,
      syncAttempts INTEGER DEFAULT 0,
      lastSyncAttempt TEXT,
      createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
      modifiedAt TEXT,
      syncedAt TEXT,
      startCoordinate TEXT,
      endCoordinate TEXT,
      isOffline INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE checklists (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      checklistId TEXT NOT NULL UNIQUE,
      workflowId TEXT NOT NULL,
      title TEXT NOT NULL,
      remarks TEXT,
      status TEXT,
      scanStartDate TEXT,
      scanEndDate TEXT,
      scheduledDate TEXT,
      locationCode TEXT,
      isActive INTEGER DEFAULT 1,
      isSynced INTEGER DEFAULT 0,
      syncAttempts INTEGER DEFAULT 0,
      lastSyncAttempt TEXT,
      createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
      modifiedAt TEXT,
      syncedAt TEXT,
      isOffline INTEGER DEFAULT 0,
      FOREIGN KEY (workflowId) REFERENCES workflows (workflowId) ON DELETE CASCADE
    )
  ''');

    await db.execute('''
      CREATE TABLE scans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scanId TEXT,
        checklistId TEXT NOT NULL,
        scanType TEXT NOT NULL,
        coordinates TEXT,
        scannedLocationCode TEXT,
        isSynced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt TEXT,
        createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
        syncedAt TEXT,
        FOREIGN KEY (checklistId) REFERENCES checklists (checklistId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE incidents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        incidentId TEXT,
        patrolId TEXT NOT NULL,
        incidentCodes TEXT NOT NULL,
        isSynced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt TEXT,
        createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
        syncedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sosId TEXT,
        userId TEXT NOT NULL,
        remarks TEXT,
        coordinates TEXT,
        isSynced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt TEXT,
        createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
        syncedAt TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE multimedia (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checklistId TEXT NOT NULL,
        mediaType TEXT NOT NULL,
        filePath TEXT NOT NULL,
        description TEXT,
        userId TEXT NOT NULL,
        createdBy TEXT NOT NULL,
        latitude REAL,
        longitude REAL,
        isSynced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt TEXT,
        createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
        syncedAt TEXT,
        FOREIGN KEY (checklistId) REFERENCES checklists (checklistId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE signatures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checklistId TEXT NOT NULL,
        filePath TEXT NOT NULL,
        userId TEXT NOT NULL,
        isSynced INTEGER DEFAULT 0,
        syncAttempts INTEGER DEFAULT 0,
        lastSyncAttempt TEXT,
        createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
        syncedAt TEXT,
        FOREIGN KEY (checklistId) REFERENCES checklists (checklistId) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_workflows_user ON workflows(userId)');
    await db.execute('CREATE INDEX idx_checklists_workflow ON checklists(workflowId)');
    await db.execute('CREATE INDEX idx_workflows_sync ON workflows(isSynced)');
    await db.execute('CREATE INDEX idx_checklists_sync ON checklists(isSynced)');
    await db.execute('CREATE INDEX idx_scans_sync ON scans(isSynced)');
    await db.execute('CREATE INDEX idx_incidents_sync ON incidents(isSynced)');
    await db.execute('CREATE INDEX idx_sos_sync ON sos(isSynced)');
    await db.execute('CREATE INDEX idx_multimedia_sync ON multimedia(isSynced)');
    await db.execute('CREATE INDEX idx_signatures_sync ON signatures(isSynced)');
    await db.execute('CREATE INDEX idx_workflows_scheduled_date ON workflows(scheduledDate)');
    await db.execute('CREATE INDEX idx_checklists_scheduled_date ON checklists(scheduledDate)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE workflows ADD COLUMN startCoordinate TEXT');
      await db.execute('ALTER TABLE workflows ADD COLUMN endCoordinate TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE multimedia ADD COLUMN syncAttempts INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE multimedia ADD COLUMN lastSyncAttempt TEXT');
      await db.execute('ALTER TABLE multimedia ADD COLUMN syncedAt TEXT');
      await db.execute('ALTER TABLE signatures ADD COLUMN syncAttempts INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE signatures ADD COLUMN lastSyncAttempt TEXT');
      await db.execute('ALTER TABLE signatures ADD COLUMN syncedAt TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('CREATE INDEX idx_workflows_sync ON workflows(isSynced)');
      await db.execute('CREATE INDEX idx_checklists_sync ON checklists(isSynced)');
      await db.execute('CREATE INDEX idx_scans_sync ON scans(isSynced)');
      await db.execute('CREATE INDEX idx_incidents_sync ON incidents(isSynced)');
      await db.execute('CREATE INDEX idx_sos_sync ON sos(isSynced)');
      await db.execute('CREATE INDEX idx_multimedia_sync ON multimedia(isSynced)');
      await db.execute('CREATE INDEX idx_signatures_sync ON signatures(isSynced)');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE workflows ADD COLUMN isOffline INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE checklists ADD COLUMN isOffline INTEGER DEFAULT 0');
      await db.execute('CREATE INDEX idx_workflows_user ON workflows(userId)');
      await db.execute('CREATE INDEX idx_checklists_workflow ON checklists(workflowId)');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE workflows ADD COLUMN description TEXT');
    }
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE workflows ADD COLUMN scheduledDate TEXT');
      
      await db.execute('ALTER TABLE checklists ADD COLUMN scheduledDate TEXT');
      
      await db.execute('CREATE INDEX idx_workflows_scheduled_date ON workflows(scheduledDate)');
      await db.execute('CREATE INDEX idx_checklists_scheduled_date ON checklists(scheduledDate)');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE workflows ADD COLUMN modifiedAt TEXT');
      await db.execute('ALTER TABLE checklists ADD COLUMN modifiedAt TEXT');
    }
    if (oldVersion < 9) { 
      await db.execute('ALTER TABLE scans ADD COLUMN scannedLocationCode TEXT');
    }
    
  }

  Future<int> insertWorkflow(Map<String, dynamic> workflow) async {
    final db = await database;
    return await db.insert(
      'workflows',
      workflow,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getWorkflowsByUser(String userId) async {
    final db = await database;
    return await db.query(
      'workflows',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'createdAt DESC',
    );
  }

  Future<int> updateChecklistScanTime(String checklistId, {required DateTime scanTime}) async {
    final db = await database;
    return await db.update(
      'checklists',
      {
        'scanStartDate': scanTime.toIso8601String(),
        'isSynced': 0,
        'modifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  Future<Map<String, dynamic>?> getWorkflow(String workflowId) async {
    final db = await database;
    final result = await db.query(
      'workflows',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getPendingChecklists([String? workflowId]) async {
    final db = await database;
    final whereClause = workflowId != null ? 'workflowId = ? AND status != ?' : 'status != ?';
    final whereArgs = workflowId != null ? [workflowId, 'completed'] : ['completed'];
    return await db.query(
      'checklists',
      where: whereClause,
      whereArgs: whereArgs,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingWorkflows() async {
    final db = await database;
    return await db.query(
      'workflows',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> updateWorkflowSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'workflows',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
          'modifiedAt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE workflows 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?, modifiedAt = ?
        WHERE id = ?
      ''', [now, now, id]);
    }
  }

  Future<int> updateWorkflowStatus(String workflowId, String status, {String? coordinates}) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = {
      'status': status,
      'isSynced': 0,
      'modifiedAt': now,
    };

    if (status == 'inprogress' && coordinates != null) {
      updates['startDateTime'] = now;
      updates['startCoordinate'] = coordinates;
    } else if (status == 'completed' && coordinates != null) {
      updates['endDateTime'] = now;
      updates['endCoordinate'] = coordinates;
    }

    return await db.update(
      'workflows',
      updates,
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    );
  }

  Future<int> insertChecklist(Map<String, dynamic> checklist) async {
    final db = await database;
    return await db.insert(
      'checklists',
      checklist,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getChecklistsByWorkflow(String workflowId) async {
    final db = await database;
    return await db.query(
      'checklists',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getCachedChecklists(String workflowId) async {
    final db = await database;
    return await db.query(
      'checklists',
      where: 'workflowId = ? AND isSynced = 1 AND LOWER(status) != ?',
      whereArgs: [workflowId, 'completed'],
    );
  }

  Future<int> updateChecklistSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'checklists',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
          'modifiedAt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE checklists 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?, modifiedAt = ?
        WHERE id = ?
      ''', [now, now, id]);
    }
  }

  Future<int> updateChecklistStatus(String checklistId, String status) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    return await db.update(
      'checklists',
      {
        'status': status,
        'scanEndDate': status == 'completed' ? now : null,
        'isSynced': 0,
        'modifiedAt': now,
      },
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  Future<int> insertScan(Map<String, dynamic> scan) async {
    final db = await database;
    return await db.insert('scans', scan);
  }

  Future<List<Map<String, dynamic>>> getPendingScans() async {
    final db = await database;
    return await db.query(
      'scans',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> updateScanSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'scans',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE scans 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?
        WHERE id = ?
      ''', [now, id]);
    }
  }

  // Incident operations
  Future<int> insertIncident(Map<String, dynamic> incident) async {
    final db = await database;
    return await db.insert('incidents', incident);
  }

  Future<List<Map<String, dynamic>>> getPendingIncidents() async {
    final db = await database;
    return await db.query(
      'incidents',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> updateIncidentSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'incidents',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE incidents 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?
        WHERE id = ?
      ''', [now, id]);
    }
  }

  // SOS operations
  Future<int> insertSOS(Map<String, dynamic> sos) async {
    final db = await database;
    return await db.insert('sos', sos);
  }

  Future<List<Map<String, dynamic>>> getPendingSOS() async {
    final db = await database;
    return await db.query(
      'sos',
      where: 'isSynced = ?',
      whereArgs: [0],
    );
  }

  Future<int> updateSOSSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'sos',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE sos 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?
        WHERE id = ?
      ''', [now, id]);
    }
  }

  // Multimedia operations
  Future<int> insertMultimedia(Map<String, dynamic> multimedia) async {
    final db = await database;
    return await db.insert('multimedia', multimedia);
  }

  Future<List<Map<String, dynamic>>> getPendingMultimedia({int? limit}) async {
    final db = await database;
    return await db.query(
      'multimedia',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  Future<int> updateMultimediaSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'multimedia',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE multimedia 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?
        WHERE id = ?
      ''', [now, id]);
    }
  }

  Future<int> deleteMultimedia(int id) async {
    final db = await database;
    final media = await db.query(
      'multimedia',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (media.isNotEmpty) {
      try {
        final file = File(media.first['filePath'] as String);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Error deleting media file: $e');
      }
    }

    return await db.delete('multimedia', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> cleanupSyncedMultimedia() async {
    final db = await database;
    const batchSize = 20;
    var totalDeleted = 0;

    while (true) {
      final batch = await db.query(
        'multimedia',
        where: 'isSynced = ?',
        whereArgs: [1],
        limit: batchSize,
      );

      if (batch.isEmpty) break;

      await db.transaction((txn) async {
        for (final media in batch) {
          try {
            final file = File(media['filePath'] as String);
            if (await file.exists()) await file.delete();
          } catch (e) {
            debugPrint('Error deleting media file: $e');
          }
          await txn.delete(
            'multimedia',
            where: 'id = ?',
            whereArgs: [media['id']],
          );
          totalDeleted++;
        }
      });
    }

    debugPrint('🧹 Deleted $totalDeleted synced multimedia items');
  }

  Future<int> insertSignature(Map<String, dynamic> signature) async {
    final db = await database;
    return await db.insert('signatures', signature);
  }

  Future<List<Map<String, dynamic>>> getPendingSignatures({int? limit}) async {
    final db = await database;
    return await db.query(
      'signatures',
      where: 'isSynced = ?',
      whereArgs: [0],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingChecklistsForWorkflow(String workflowId) async {
    final db = await database;
    return await db.query(
      'checklists',
      where: 'workflowId = ? AND status != ? AND isSynced = ?',
      whereArgs: [workflowId, 'completed', 0],
    );
  }

  Future<List<Map<String, dynamic>>> getSyncedChecklistsForWorkflow(String workflowId) async {
    final db = await database;
    return await db.query(
      'checklists',
      where: 'workflowId = ? AND isSynced = ?',
      whereArgs: [workflowId, 1],
    );
  }

  Future<bool> hasCachedWorkflow(String workflowId) async {
    final db = await database;
    final result = await db.query(
      'workflows',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<int> updateSignatureSyncStatus(int id, {bool isSuccess = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    if (isSuccess) {
      return await db.update(
        'signatures',
        {
          'isSynced': 1,
          'syncedAt': now,
          'syncAttempts': 0,
          'lastSyncAttempt': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      return await db.rawUpdate('''
        UPDATE signatures 
        SET syncAttempts = syncAttempts + 1, lastSyncAttempt = ?
        WHERE id = ?
      ''', [now, id]);
    }
  }

  Future<int> update({
    required String table,
    required Map<String, dynamic> values,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final db = await database;
    return await db.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
    );
  }

  Future<int> deleteSignature(int id) async {
    final db = await database;
    final signature = await db.query(
      'signatures',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (signature.isNotEmpty) {
      try {
        final file = File(signature.first['filePath'] as String);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Error deleting signature file: $e');
      }
    }

    return await db.delete('signatures', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getChecklistsForWorkflowSync(String workflowId) async {
    return await database.then((db) => db.query(
      'checklists',
      where: 'workflowId = ?',
      whereArgs: [workflowId],
    ));
  }

  Future<void> cleanupSyncedSignatures() async {
    final db = await database;
    const batchSize = 20;
    var totalDeleted = 0;

    while (true) {
      final batch = await db.query(
        'signatures',
        where: 'isSynced = ?',
        whereArgs: [1],
        limit: batchSize,
      );

      if (batch.isEmpty) break;

      await db.transaction((txn) async {
        for (final sig in batch) {
          try {
            final file = File(sig['filePath'] as String);
            if (await file.exists()) await file.delete();
          } catch (e) {
            debugPrint('Error deleting signature file: $e');
          }
          await txn.delete(
            'signatures',
            where: 'id = ?',
            whereArgs: [sig['id']],
          );
          totalDeleted++;
        }
      });
    }

    debugPrint('🧹 Deleted $totalDeleted synced signatures');
  }

  Future<bool> hasPendingSyncs() async {
    final db = await database;
    final tables = ['workflows', 'checklists', 'scans', 'incidents', 'sos', 'multimedia', 'signatures'];
    
    for (final table in tables) {
      final result = await db.rawQuery('SELECT 1 FROM $table WHERE isSynced = 0 LIMIT 1');
      if (result.isNotEmpty) return true;
    }
    
    return false;
  }

  Future<int> recordSyncAttempt(String table, int id) async {
    final db = await database;
    return await db.rawUpdate('''
      UPDATE $table 
      SET syncAttempts = syncAttempts + 1, 
          lastSyncAttempt = ?
      WHERE id = ?
    ''', [DateTime.now().toIso8601String(), id]);
  }

  Future<int> updateChecklistCompletionTime(String checklistId, {required DateTime completionTime}) async {
    final db = await database;
    return await db.update(
      'checklists',
      {
        'scanEndDate': completionTime.toIso8601String(),
        'isSynced': 0,
        'modifiedAt': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'checklistId = ?',
      whereArgs: [checklistId],
    );
  }

  Future<List<Map<String, dynamic>>> getChecklistsByWorkflowAndDate(String workflowId, String? scheduledDate) async {
    final db = await database;
    
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

  Future<List<Map<String, dynamic>>> getWorkflowsByScheduledDate(String scheduledDate) async {
    final db = await database;
    return await db.query(
      'workflows',
      where: 'scheduledDate = ?',
      whereArgs: [scheduledDate],
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<String>> getDistinctScheduledDates(String userId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT DISTINCT scheduledDate 
      FROM workflows 
      WHERE userId = ? AND scheduledDate IS NOT NULL AND scheduledDate != ''
      ORDER BY scheduledDate ASC
    ''', [userId]);
    
    return result.map((row) => row['scheduledDate'] as String).toList();
  }
}