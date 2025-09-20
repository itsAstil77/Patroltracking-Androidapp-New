import 'package:flutter/material.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/patrol/patrolMultimediaScreen.dart';
import 'package:patroltracking/services/api_service.dart';

class PatrolIncidentScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String token;

  const PatrolIncidentScreen({
    super.key,
    required this.user,
    required this.token,
  });

  @override
  _PatrolIncidentScreenState createState() => _PatrolIncidentScreenState();
}

class _PatrolIncidentScreenState extends State<PatrolIncidentScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allIncidents = [];
  List<Map<String, dynamic>> _filteredIncidents = [];
  final Map<String, bool> _selectedIncidents = {};
  final Map<String, String> _incidentNameMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIncidents();
  }

  void _loadIncidents() async {
    try {
      final incidents = await ApiService.fetchIncidents(widget.token);
      setState(() {
        _allIncidents = incidents;
        _filteredIncidents = List.from(incidents);
        for (var incident in incidents) {
          final code = incident['code'];
          final name = incident['incident'];
          _selectedIncidents[code] = false;
          _incidentNameMap[code] = name;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading incidents: $e")),
      );
    }
  }

  void _filterIncidents(String query) {
    setState(() {
      _filteredIncidents = _allIncidents
          .where((incident) =>
              incident['incident'].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _sendIncidents() async {
    List<String> selectedCodes = _selectedIncidents.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No incidents selected")),
      );
      return;
    }

    try {
      final response = await ApiService.sendIncidents(
        token: widget.token,
        patrolId: widget.user['userId'],
        incidentCodes: selectedCodes,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['message'] ?? 'Incidents sent.')),
      );

      setState(() {
        _selectedIncidents.updateAll((key, value) => false);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text("Incidents", style: AppConstants.headingStyle)),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelStyle: AppConstants.normalPurpleFontStyle,
                      labelText: "Search Incidents",
                      prefixIcon:
                          Icon(Icons.search, color: AppConstants.primaryColor),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _filterIncidents,
                  ),
                  SizedBox(height: 10),
                  SizedBox(
                    height: 250,
                    child: ListView.builder(
                      itemCount: _filteredIncidents.length,
                      itemBuilder: (context, index) {
                        String code = _filteredIncidents[index]['code'] ?? '';
                        String name =
                            _filteredIncidents[index]['incident'] ?? '';
                        return CheckboxListTile(
                          checkColor: AppConstants.fontColorWhite,
                          title: Text(
                            name,
                            style: AppConstants.normalPurpleFontStyle,
                          ),
                          value: _selectedIncidents[code],
                          onChanged: (bool? value) {
                            setState(() {
                              _selectedIncidents[code] = value ?? false;
                            });
                          },
                        );
                      },
                    ),
                  ),
                  SizedBox(height: 50),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.location_on,
                              color: AppConstants.primaryColor),
                          label: Text(
                            "Checkpoint",
                            style: AppConstants.selectedButtonFontStyle,
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text("Assign Checkpoint clicked")),
                            );
                          },
                        ),
                      ),
                      SizedBox(width: 10), 
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.add_photo_alternate,
                              color: AppConstants.primaryColor),
                          label: Text(
                            "Add MME",
                            style: AppConstants.selectedButtonFontStyle,
                          ),
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PatrolMultimediaScreen(
                                  checklistId: '',
                                  user: widget.user,
                                  token: widget.token, mode: 'notbymenu',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: Icon(Icons.send, color: AppConstants.primaryColor),
                    label: Text(
                      "Send Incidents",
                      style: AppConstants.selectedButtonFontStyle,
                    ),
                    onPressed: _sendIncidents,
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
