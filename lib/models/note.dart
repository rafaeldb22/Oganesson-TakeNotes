import 'dart:math';

class Note {
  Note({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.deleted = false,
  });

  final String id;
  String content;
  bool pinned;
  bool deleted;
  final DateTime createdAt;
  DateTime updatedAt;

  List<String> get _lines => content
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  /// Primera línea con texto = título (como en Notas de iPhone).
  String get title {
    final l = _lines;
    return l.isEmpty ? 'Nota nueva' : l.first;
  }

  String get preview {
    final l = _lines;
    return l.length < 2 ? 'Sin texto adicional' : l.sublist(1).join(' ');
  }

  bool get isEmpty => content.trim().isEmpty;

  Map<String, dynamic> toRow({String? userId}) => {
        'id': id,
        if (userId != null) 'user_id': userId,
        'content': content,
        'pinned': pinned,
        'deleted': deleted,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Note.fromRow(Map<String, dynamic> r) {
    final updated = DateTime.parse(r['updated_at'] as String).toUtc();
    final createdRaw = r['created_at'];
    return Note(
      id: r['id'] as String,
      content: (r['content'] as String?) ?? '',
      pinned: r['pinned'] == true,
      deleted: r['deleted'] == true,
      createdAt:
          createdRaw is String ? DateTime.parse(createdRaw).toUtc() : updated,
      updatedAt: updated,
    );
  }
}

/// UUID v4 sin dependencias externas.
String newNoteId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
