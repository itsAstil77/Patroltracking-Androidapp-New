import 'package:flutter/material.dart';

class WorkflowData {
  final Workflow workflow;
  final List<Checklist> checklists;

  WorkflowData({required this.workflow, required this.checklists});

  factory WorkflowData.fromJson(Map<String, dynamic> json) {
    return WorkflowData(
      workflow: Workflow.fromJson(json['workflow'] ?? {}),
      checklists: (json['checklists'] as List<dynamic>? ?? [])
          .map((item) => Checklist.fromJson(item))
          .toList(),
    );
  }
}

class Workflow {
  final String workflowId;
  final String workflowTitle;
  final String description;
  final String status;
  final DateTime startDateTime;
  final DateTime endDateTime;

  Workflow({
    required this.workflowId,
    required this.workflowTitle,
    required this.description,
    required this.status,
    required this.startDateTime,
    required this.endDateTime,
  });

  factory Workflow.fromJson(Map<String, dynamic> json) {
    return Workflow(
      workflowId: json['workflowId'] ?? '',
      workflowTitle: json['workflowTitle'] ?? 'Untitled',
      description: json['description'] ?? '',
      status: json['status'] ?? 'unknown',
      startDateTime: _parseDateTime(json['startDateTime']),
      endDateTime: _parseDateTime(json['endDateTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workflowId': workflowId,
      'workflowTitle': workflowTitle,
      'description': description,
      'status': status,
      'startDateTime': startDateTime.toIso8601String(),
      'endDateTime': endDateTime.toIso8601String(),
      'userId': '', 
      'isSynced': 1, 
    };
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

class Checklist {
  final String checklistId;
  final String title;
  final String remarks;
  final String status;
  final DateTime scanStartDate;
  final DateTime scanEndDate;

  Checklist({
    required this.checklistId,
    required this.title,
    required this.remarks,
    required this.status,
    required this.scanStartDate,
    required this.scanEndDate,
  });

  factory Checklist.fromJson(Map<String, dynamic> json) {
    return Checklist(
      checklistId: json['checklistId'] ?? '',
      title: json['title'] ?? 'No title',
      remarks: json['remarks'] ?? 'No remarks',
      status: json['status'] ?? 'unknown',
      scanStartDate: _parseDateTime(json['scanStartDate']),
      scanEndDate: _parseDateTime(json['scanEndDate']),
    );
  }
}

DateTime _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) {
    return DateTime.fromMillisecondsSinceEpoch(0); 
  }
  try {
    return DateTime.parse(value.toString());
  } catch (e) {
    return DateTime.fromMillisecondsSinceEpoch(0); 
  }
}
