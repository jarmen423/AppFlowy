import 'dart:convert';

/// Represents metadata for a View that is linked to a local file on disk
/// (for live two-way Markdown / plain text editing).
///
/// Stored as JSON in the ViewPB.extra field under ViewExtKeys.linkedFileKey.
class LinkedFileInfo {
  const LinkedFileInfo({
    required this.path,
    this.type = 'markdown',
    this.linkedAt,
  });

  /// Absolute path to the local file (source of truth for content).
  final String path;

  /// 'markdown' | 'text' (extensible).
  final String type;

  /// Milliseconds since epoch when the link was created/updated.
  final int? linkedAt;

  factory LinkedFileInfo.fromJson(Map<String, dynamic> json) {
    return LinkedFileInfo(
      path: json['path'] as String? ?? '',
      type: json['type'] as String? ?? 'markdown',
      linkedAt: json['linked_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'type': type,
        if (linkedAt != null) 'linked_at': linkedAt,
      };

  @override
  String toString() => 'LinkedFileInfo(path: $path, type: $type)';

  /// Convenience: create a JSON string suitable for ViewPB.extra (or a sub-key).
  String toJsonString() => jsonEncode(toJson());

  static LinkedFileInfo? tryFromJsonString(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return LinkedFileInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
