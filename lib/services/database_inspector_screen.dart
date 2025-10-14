import 'package:flutter/material.dart';
import 'package:patroltracking/services/database_helper.dart';
class DatabaseInspectorScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> userdata;

  const DatabaseInspectorScreen({
    super.key,
    required this.token,
    required this.userdata,
  });

  @override
  State<DatabaseInspectorScreen> createState() => _DatabaseInspectorScreenState();
}

class _DatabaseInspectorScreenState extends State<DatabaseInspectorScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Map<String, List<Map<String, dynamic>>> _databaseData = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDatabaseData();
  }

  Future<void> _loadDatabaseData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final data = await _dbHelper.getAllData();
      setState(() {
        _databaseData = data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading database data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Inspector'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDatabaseData,
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () async {
              await _dbHelper.printTableStats();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Stats printed to console')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              await _dbHelper.exportDatabaseToFile();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database exported to file')),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildDataView(),
    );
  }

  Widget _buildDataView() {
    return ListView(
      children: _databaseData.entries.map((entry) {
        return Card(
          margin: const EdgeInsets.all(8.0),
          child: ExpansionTile(
            title: Row(
              children: [
                Text(
                  '${entry.key} ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text('${entry.value.length} records'),
                  backgroundColor: Colors.blue[100],
                ),
              ],
            ),
            children: [
              if (entry.value.isEmpty)
                const ListTile(
                  title: Text('No data found', style: TextStyle(color: Colors.grey)),
                )
              else
                ...entry.value.map((row) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: row.entries.map((field) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${field.key}: ',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: Text(
                                  field.value?.toString() ?? 'null',
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }).toList(),
            ],
          ),
        );
      }).toList(),
    );
  }
}