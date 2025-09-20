import 'package:flutter/material.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/models/workflow.dart';
import 'package:patroltracking/navigationbar.dart';
import '../services/api_service.dart';

class WorkflowScreen extends StatefulWidget {
  final Map<String, dynamic> userdata;
  final String token;
  const WorkflowScreen(
      {super.key, required this.userdata, required this.token});

  @override
  State<WorkflowScreen> createState() => _WorkflowScreenState();
}

class _WorkflowScreenState extends State<WorkflowScreen> {
  late Future<List<WorkflowData>> _futureWorkflows;

  @override
  void initState() {
    super.initState();
    _futureWorkflows =
        ApiService().getCompletedWorkflows(widget.userdata['userId'], widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: Text(
            "Workflows",
            style: AppConstants.headingStyle,
          )),
      drawer: CustomDrawer(userdata: widget.userdata, token: widget.token),
      body: FutureBuilder<List<WorkflowData>>(
        future: _futureWorkflows,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No completed workflows found."));
          }

          final workflows = snapshot.data!;

          return ListView.builder(
            itemCount: workflows.length,
            itemBuilder: (context, index) {
              final wf = workflows[index];
              return Card(
                margin: const EdgeInsets.all(8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ExpansionTile(
                  title: Text(wf.workflow.workflowTitle),
                  subtitle: Text("Status: ${wf.workflow.status}"),
                  children: wf.checklists.map((checklist) {
                    return ListTile(
                      title: Text(checklist.title),
                      subtitle: Text(checklist.remarks),
                      trailing: Text(checklist.status),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}