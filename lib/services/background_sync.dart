
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:patroltracking/services/sync_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token != null) {
        final syncService = SyncService(
          dbHelper: DatabaseHelper(),
          connectivity: Connectivity(),
          apiService: ApiService(),
          prefs: prefs, // UNCOMMENTED this line
        );
        
        await syncService.syncPendingData();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Background sync error: $e');
      return false;
    }
  });
}

class BackgroundSync {
  static void initialize() {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static void registerSyncTask() {
    Workmanager().registerOneOffTask(
      'syncTask',
      'syncData',
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  static void registerPeriodicSync() {
    Workmanager().registerPeriodicTask(
      'periodicSync',
      'periodicSync',
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}