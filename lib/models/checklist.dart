import 'package:flutter/material.dart';
import 'dart:convert';

class EventChecklistGroup {
  final String workflowId;
  final String workflowTitle;
  final String description;
  final String status;
  final DateTime? assignedStart;
  final DateTime? assignedEnd;
  final String? scheduledDate;
  final List<ChecklistItem> checklists;
  final bool isActive;

  EventChecklistGroup({
    required this.workflowId,
    required this.workflowTitle,
    this.description = '',
    required this.status,
    this.assignedStart,
    this.assignedEnd,
    this.scheduledDate,
    required this.checklists,
    this.isActive = true,
  });

  factory EventChecklistGroup.fromJson(Map<String, dynamic> json) {
    return EventChecklistGroup(
      workflowId: json['workflowId'],
      workflowTitle: json['workflowTitle'],
      status: json['status'],
      assignedStart: json['AssignedStart'] != null
          ? DateTime.parse(json['AssignedStart'])
          : null,
      assignedEnd: json['AssignedEnd'] != null
          ? DateTime.parse(json['AssignedEnd'])
          : null,
      scheduledDate: json['scheduledDate'],
      checklists: (json['checklists'] as List?)
              ?.map((c) => ChecklistItem.fromJson(c))
              .toList() ??
          [],
      description: json['description'] ?? '',
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toDbMap(String userId) {
    return {
      'workflowId': workflowId,
      'workflowTitle': workflowTitle,
      'description': description,
      'status': status,
      'startDateTime': assignedStart?.toIso8601String(),
      'endDateTime': assignedEnd?.toIso8601String(),
      'scheduledDate': scheduledDate,
      'userId': userId,
      'isSynced': 0,
    };
  }

  /// ✅ Added copyWith
  EventChecklistGroup copyWith({
    String? workflowId,
    String? workflowTitle,
    String? description,
    String? status,
    DateTime? assignedStart,
    DateTime? assignedEnd,
    String? scheduledDate,
    List<ChecklistItem>? checklists,
    bool? isActive,
  }) {
    return EventChecklistGroup(
      workflowId: workflowId ?? this.workflowId,
      workflowTitle: workflowTitle ?? this.workflowTitle,
      description: description ?? this.description,
      status: status ?? this.status,
      assignedStart: assignedStart ?? this.assignedStart,
      assignedEnd: assignedEnd ?? this.assignedEnd,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      checklists: checklists ?? this.checklists,
      isActive: isActive ?? this.isActive,
    );
  }
}




class ChecklistItem {
  final String checklistId;
  final String title;
  final String status;
  final dynamic locationCode;
  final bool isActive;
  final String? scanStartDate;
  final bool isScanned;
  final bool isCompleted;
  final DateTime? expiryDate;
  final DateTime? assignedStart; 
  final DateTime? assignedEnd;   
  final String? scheduledDate;   

  ChecklistItem({
    required this.checklistId,
    required this.title,
    required this.status,
    this.locationCode,
    this.isActive = true,
    this.scanStartDate,
    this.isScanned = false,
    this.isCompleted = false,
    this.expiryDate,
    this.assignedStart, 
    this.assignedEnd,   
    this.scheduledDate, 
  });

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    dynamic locationCode = json['locationCode'];
    if (locationCode is String && locationCode.startsWith('[')) {
      try {
        locationCode = jsonDecode(locationCode);
      } catch (e) {
        debugPrint('Failed to parse locationCode: $e');
      }
    } else if (locationCode is List) {
      locationCode = List<String>.from(locationCode);
    }

    bool isActive;
    if (json['isActive'] == null) {
      isActive = true;
    } else if (json['isActive'] is bool) {
      isActive = json['isActive'];
    } else if (json['isActive'] is String) {
      isActive = json['isActive'].toLowerCase() == 'true' || json['isActive'] == '1';
    } else {
      isActive = json['isActive'] == 1;
    }

    DateTime? expiryDate;
    if (json['expiryDate'] != null) {
      try {
        expiryDate = DateTime.parse(json['expiryDate']);
      } catch (e) {
        debugPrint('Failed to parse expiryDate: $e');
      }
    }

    DateTime? assignedStart;
    if (json['AssignedStart'] != null) {
      try {
        assignedStart = DateTime.parse(json['AssignedStart']);
      } catch (e) {
        debugPrint('Failed to parse AssignedStart: $e');
      }
    }

    DateTime? assignedEnd;
    if (json['AssignedEnd'] != null) {
      try {
        assignedEnd = DateTime.parse(json['AssignedEnd']);
      } catch (e) {
        debugPrint('Failed to parse AssignedEnd: $e');
      }
    }

    return ChecklistItem(
      checklistId: json['checklistId'],
      title: json['title'],
      status: json['status'],
      locationCode: locationCode,
      isActive: isActive,
      scanStartDate: json['scanStartDate'],
      isScanned: json['scanStartDate'] != null,
      isCompleted: json['status'] == 'completed',
      expiryDate: expiryDate,
      assignedStart: assignedStart, 
      assignedEnd: assignedEnd,     
      scheduledDate: json['scheduledDate'], 
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'checklistId': checklistId,
      'title': title,
      'status': status,
      'locationCode': locationCode is List ? jsonEncode(locationCode) : locationCode,
      'isActive': isActive ? 1 : 0,
      'scanStartDate': scanStartDate,
      'isScanned': isScanned ? 1 : 0,
      'isCompleted': isCompleted ? 1 : 0,
      'expiryDate': expiryDate?.toIso8601String(),
      'AssignedStart': assignedStart?.toIso8601String(), 
      'AssignedEnd': assignedEnd?.toIso8601String(),     
      'scheduledDate': scheduledDate,                    
    };
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    final now = DateTime.now();
    final difference = expiryDate!.difference(now);
    return difference.inDays;
  }

 bool isForDate(String date) {
  if (scheduledDate != null) {
    return scheduledDate == date;
  }
  
  if (assignedStart != null && assignedEnd != null) {
    try {
      final selectedDate = DateTime.parse(date);
      final startDate = DateTime(assignedStart!.year, assignedStart!.month, assignedStart!.day);
      final endDate = DateTime(assignedEnd!.year, assignedEnd!.month, assignedEnd!.day);
      
      return (selectedDate.isAtSameMomentAs(startDate) || selectedDate.isAfter(startDate)) &&
             (selectedDate.isAtSameMomentAs(endDate) || selectedDate.isBefore(endDate));
    } catch (e) {
      debugPrint('Error parsing date in isForDate: $e');
      return false;
    }
  }
  
  return true;
}
}