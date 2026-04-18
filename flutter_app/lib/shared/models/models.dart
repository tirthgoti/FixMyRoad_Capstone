// Helper — Supabase returns count() as [{count: N}] list
int _parseCount(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is Map) return (first['count'] as num?)?.toInt() ?? 0;
  }
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// models/report.dart
// ─────────────────────────────────────────────────────────────────────────────
class Report {
  final String id;
  final String citizenId;
  final String? assignedTo;
  final String status;
  final String? description;
  final String imageUrl;
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime submittedAt;
  final DateTime updatedAt;
  final int upvoteCount;
  final AiResult? aiResult;
  final Profile? citizen;
  final Profile? engineer;

  const Report({
    required this.id,
    required this.citizenId,
    this.assignedTo,
    required this.status,
    this.description,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
    this.address,
    required this.submittedAt,
    required this.updatedAt,
    this.upvoteCount = 0,
    this.aiResult,
    this.citizen,
    this.engineer,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id:          json['id']?.toString() ?? '',
        citizenId:   json['citizen_id']?.toString() ?? '',
        assignedTo:  json['assigned_to']?.toString(),
        status:      json['status']?.toString() ?? 'submitted',
        description: json['description']?.toString(),
        imageUrl:    json['image_url']?.toString() ?? '',
        latitude:    (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude:   (json['longitude'] as num?)?.toDouble() ?? 0.0,
        address:     json['address']?.toString(),
        submittedAt: json['submitted_at'] != null
            ? DateTime.tryParse(json['submitted_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        updatedAt:   json['updated_at'] != null
            ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        upvoteCount: _parseCount(json['upvote_count']),
        aiResult: json['ai_results'] != null
            ? AiResult.fromJson(json['ai_results'])
            : null,
        citizen: json['citizen'] != null
            ? Profile.fromJson(json['citizen'])
            : null,
        engineer: json['engineer'] != null
            ? Profile.fromJson(json['engineer'])
            : null,
      );

  String get severityLabel {
    final s = aiResult?.severity ?? 'unknown';
    switch (s) {
      case 'deep':     return 'Deep';
      case 'moderate': return 'Moderate';
      case 'shallow':  return 'Shallow';
      default:         return 'Analyzing...';
    }
  }

  String get statusLabel {
    switch (status) {
      case 'submitted':     return 'Submitted';
      case 'under_review':  return 'Under Review';
      case 'assigned':      return 'Assigned';
      case 'in_progress':   return 'In Progress';
      case 'fixed':         return 'Fixed';
      case 'rejected':      return 'Rejected';
      default:              return status;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// models/ai_result.dart
// ─────────────────────────────────────────────────────────────────────────────
class AiResult {
  final String id;
  final String reportId;
  final double? relativeDepth;
  final double? maxDepth;
  final String? severity;
  final double? potholeAreaPx;
  final double? confidence;
  final double? repairCostMin;
  final double? repairCostMax;
  final double? priorityScore;
  final String? depthMapUrl;
  final String? heatmapUrl;
  final String? beforeAfterUrl;
  final double? asphaltKg;
  final double? labourHours;
  final double? materialCostEst;
  final DateTime? processedAt;

  const AiResult({
    required this.id,
    required this.reportId,
    this.relativeDepth,
    this.maxDepth,
    this.severity,
    this.potholeAreaPx,
    this.confidence,
    this.repairCostMin,
    this.repairCostMax,
    this.priorityScore,
    this.depthMapUrl,
    this.heatmapUrl,
    this.beforeAfterUrl,
    this.asphaltKg,
    this.labourHours,
    this.materialCostEst,
    this.processedAt,
  });

  factory AiResult.fromJson(Map<String, dynamic> json) => AiResult(
        id:       json['id']?.toString() ?? '',
        reportId: json['report_id']?.toString() ?? '',
        relativeDepth: (json['relative_depth'] as num?)?.toDouble(),
        maxDepth: (json['max_depth'] as num?)?.toDouble(),
        severity: json['severity']?.toString(),
        potholeAreaPx: (json['pothole_area_px'] as num?)?.toDouble(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        repairCostMin: (json['repair_cost_min'] as num?)?.toDouble(),
        repairCostMax: (json['repair_cost_max'] as num?)?.toDouble(),
        priorityScore: (json['priority_score'] as num?)?.toDouble(),
        depthMapUrl: json['depth_map_url'],
        heatmapUrl: json['heatmap_url'],
        beforeAfterUrl: json['before_after_url'],
        asphaltKg: (json['asphalt_kg'] as num?)?.toDouble(),
        labourHours: (json['labour_hours'] as num?)?.toDouble(),
        materialCostEst: (json['material_cost_est'] as num?)?.toDouble(),
        processedAt: json['processed_at'] != null
            ? DateTime.parse(json['processed_at'])
            : null,
      );

  String get costRangeLabel {
    if (repairCostMin == null || repairCostMax == null) return 'Calculating...';
    return '₹${repairCostMin!.toStringAsFixed(0)} – ₹${repairCostMax!.toStringAsFixed(0)}';
  }

  /// True when the AI has returned at least one meaningful signal.
  /// Use this instead of checking [severity] alone, since the backend can
  /// write severity before finishing numeric analysis.
  bool get hasAiSignals =>
      severity != null ||
      (relativeDepth ?? 0) > 0 ||
      (potholeAreaPx ?? 0) > 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// models/profile.dart
// ─────────────────────────────────────────────────────────────────────────────
class Profile {
  final String id;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final String? fcmToken;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.fullName,
    this.phone,
    this.avatarUrl,
    required this.role,
    this.fcmToken,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id:        json['id']?.toString() ?? '',
        fullName:  json['full_name']?.toString(),
        phone:     json['phone']?.toString(),
        avatarUrl: json['avatar_url']?.toString(),
        role:      json['role']?.toString() ?? 'citizen',
        fcmToken:  json['fcm_token']?.toString(),
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
      );

  bool get isEngineer => role == 'engineer';
  bool get isAdmin    => role == 'admin';

  String get displayName => fullName ?? 'User';
  String get initials {
    final parts = (fullName ?? 'U').trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// models/notification_model.dart
// ─────────────────────────────────────────────────────────────────────────────
class NotificationModel {
  final String id;
  final String userId;
  final String? reportId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    this.reportId,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: json['id'],
        userId: json['user_id'],
        reportId: json['report_id'],
        title: json['title'],
        body: json['body'],
        isRead: json['is_read'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// models/status_history.dart
// ─────────────────────────────────────────────────────────────────────────────
class StatusHistory {
  final String id;
  final String reportId;
  final String changedBy;
  final String? oldStatus;
  final String newStatus;
  final String? note;
  final DateTime changedAt;
  final Profile? changer;

  const StatusHistory({
    required this.id,
    required this.reportId,
    required this.changedBy,
    this.oldStatus,
    required this.newStatus,
    this.note,
    required this.changedAt,
    this.changer,
  });

  factory StatusHistory.fromJson(Map<String, dynamic> json) => StatusHistory(
        id: json['id'],
        reportId: json['report_id'],
        changedBy: json['changed_by'],
        oldStatus: json['old_status'],
        newStatus: json['new_status'],
        note: json['note'],
        changedAt: DateTime.parse(json['changed_at']),
        changer: json['changer'] != null
            ? Profile.fromJson(json['changer'])
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// models/draft_report.dart  — for offline queue
// ─────────────────────────────────────────────────────────────────────────────
class DraftReport {
  final int? localId;
  final String imagePath;
  final double latitude;
  final double longitude;
  final String? address;
  final String? description;
  final DateTime createdAt;

  const DraftReport({
    this.localId,
    required this.imagePath,
    required this.latitude,
    required this.longitude,
    this.address,
    this.description,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': localId,
        'image_path': imagePath,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'description': description,
        'created_at': createdAt.toIso8601String(),
      };

  factory DraftReport.fromMap(Map<String, dynamic> map) => DraftReport(
        localId: map['id'],
        imagePath: map['image_path'],
        latitude: map['latitude'],
        longitude: map['longitude'],
        address: map['address'],
        description: map['description'],
        createdAt: DateTime.parse(map['created_at']),
      );
}