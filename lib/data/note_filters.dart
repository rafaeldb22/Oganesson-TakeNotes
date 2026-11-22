import '../models/note.dart';

/// Periodo del filtro por fecha de última modificación.
enum DateFilter { any, today, week, month }

/// Filtros de búsqueda combinables.
class NoteFilters {
  const NoteFilters({
    this.date = DateFilter.any,
    this.folderId,
    this.color,
    this.withImages = false,
    this.withTasks = false,
  });

  final DateFilter date;

  /// Carpeta concreta; '' = notas sin carpeta; null = todas.
  final String? folderId;
  final int? color;
  final bool withImages;
  final bool withTasks;

  /// Identifica la combinación (la lista se reconstruye si cambia).
  int get signature =>
      Object.hash(date, folderId, color, withImages, withTasks);

  bool get isActive =>
      date != DateFilter.any ||
      folderId != null ||
      color != null ||
      withImages ||
      withTasks;

  int get count =>
      (date != DateFilter.any ? 1 : 0) +
      (folderId != null ? 1 : 0) +
      (color != null ? 1 : 0) +
      (withImages ? 1 : 0) +
      (withTasks ? 1 : 0);

  bool matches(Note n, {DateTime? now}) {
    if (withImages && !n.hasImages) return false;
    if (withTasks && !n.hasChecklist && !n.isTemporal) return false;
    if (color != null && n.color != color) return false;
    if (folderId != null && (n.folderId ?? '') != folderId) return false;
    if (date != DateFilter.any) {
      final t = (now ?? DateTime.now()).toLocal();
      final today = DateTime(t.year, t.month, t.day);
      final from = switch (date) {
        DateFilter.today => today,
        DateFilter.week => DateTime(t.year, t.month, t.day - 6),
        DateFilter.month => DateTime(t.year, t.month - 1, t.day),
        DateFilter.any => today,
      };
      if (n.updatedAt.toLocal().isBefore(from)) return false;
    }
    return true;
  }
}
