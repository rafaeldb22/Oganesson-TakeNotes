import 'dart:math';

import '../ui/i18n.dart';

DateTime? _parseDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.parse(v).toUtc() : null;

class Note {
  Note({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.rich,
    this.folderId,
    this.remindAt,
    this.dueAt,
    this.done = false,
    this.color,
    this.pinned = false,
    this.deleted = false,
    this.vault = false,
    this.doneAt,
    List<String>? links,
  }) : links = links ?? [];

  /// Cuándo se marcó como completada (para moverla a "Completadas").
  DateTime? doneAt;

  /// Notas enlazadas a mano (clic derecho → Enlazar), por id.
  List<String> links;

  final String id;

  /// Nota guardada en el Vault: oculta hasta desbloquearlo con la contraseña
  /// maestra (y nunca se muestra en los widgets de Android).
  bool vault;

  /// Color elegido para la nota (ARGB). null = colores por defecto.
  int? color;

  /// Texto plano (para la lista, la búsqueda y el widget).
  String content;

  /// Texto con formato (Delta de Quill en JSON). null = solo texto plano.
  String? rich;

  String? folderId;

  /// Notas temporales: inicio del periodo / primer aviso.
  DateTime? remindAt;

  /// Notas temporales: fecha límite.
  DateTime? dueAt;

  /// Tarea completada (deja de avisar).
  bool done;

  bool pinned;
  bool deleted;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isTemporal => dueAt != null;

  /// Inicio del periodo para el calendario y la barra de progreso.
  DateTime get periodStart {
    final s = remindAt ?? createdAt;
    final d = dueAt;
    return d != null && s.isAfter(d) ? d : s;
  }

  /// Fracción del tiempo ya consumido (0 = recién empezada, 1 = vencida).
  double progress([DateTime? now]) {
    final d = dueAt;
    if (d == null) return 0;
    final n = (now ?? DateTime.now()).toUtc();
    final total = d.difference(periodStart).inSeconds;
    if (total <= 0) return n.isBefore(d) ? 0 : 1;
    return (n.difference(periodStart).inSeconds / total).clamp(0.0, 1.0);
  }

  bool isOverdue([DateTime? now]) =>
      dueAt != null && !done && (now ?? DateTime.now()).toUtc().isAfter(dueAt!);

  List<String> get _lines => content
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  /// Primera línea con texto = título (como en Notas de iPhone).
  String get title {
    final l = _lines;
    return l.isEmpty ? tr('Nota nueva') : l.first;
  }

  String get preview {
    final l = _lines;
    return l.length < 2 ? tr('Sin texto adicional') : l.sublist(1).join(' ');
  }

  /// ¿Tiene texto además del título?
  bool get hasPreview {
    return _lines.length >= 2;
  }

  bool get isEmpty => content.trim().isEmpty;

  /// [withVault] = false cuando Supabase aún no tiene las columnas de la
  /// migración 005 (`vault`, `links`, `done_at`): el resto se sigue subiendo.
  Map<String, dynamic> toRow({String? userId, bool withVault = true}) => {
        'id': id,
        if (userId != null) 'user_id': userId,
        'content': content,
        'rich': rich,
        'folder_id': folderId,
        if (withVault) 'vault': vault,
        if (withVault) 'links': links,
        if (withVault) 'done_at': doneAt?.toUtc().toIso8601String(),
        'remind_at': remindAt?.toUtc().toIso8601String(),
        'due_at': dueAt?.toUtc().toIso8601String(),
        'done': done,
        'color': color,
        'pinned': pinned,
        'deleted': deleted,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Note.fromRow(Map<String, dynamic> r) {
    final updated = DateTime.parse(r['updated_at'] as String).toUtc();
    return Note(
      id: r['id'] as String,
      content: (r['content'] as String?) ?? '',
      rich: r['rich'] as String?,
      folderId: r['folder_id'] as String?,
      remindAt: _parseDate(r['remind_at']),
      dueAt: _parseDate(r['due_at']),
      done: r['done'] == true,
      color: r['color'] is num ? (r['color'] as num).toInt() : null,
      pinned: r['pinned'] == true,
      deleted: r['deleted'] == true,
      vault: r['vault'] == true,
      doneAt: _parseDate(r['done_at']),
      links: r['links'] is List
          ? (r['links'] as List).whereType<String>().toList()
          : null,
      createdAt: _parseDate(r['created_at']) ?? updated,
      updatedAt: updated,
    );
  }
}

class Folder {
  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.color,
    this.deleted = false,
  });

  final String id;
  String name;
  int? color;
  bool deleted;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toRow({String? userId}) => {
        'id': id,
        if (userId != null) 'user_id': userId,
        'name': name,
        'color': color,
        'deleted': deleted,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Folder.fromRow(Map<String, dynamic> r) {
    final updated = DateTime.parse(r['updated_at'] as String).toUtc();
    final c = r['color'];
    return Folder(
      id: r['id'] as String,
      name: (r['name'] as String?) ?? '',
      color: c is int ? c : (c is num ? c.toInt() : null),
      deleted: r['deleted'] == true,
      createdAt: _parseDate(r['created_at']) ?? updated,
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
