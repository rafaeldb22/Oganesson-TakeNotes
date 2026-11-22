/// Cada cuánto se repite una tarea.
enum RepeatRule {
  daily('daily'),
  weekdays('weekdays'),
  weekly('weekly'),
  monthly('monthly'),
  yearly('yearly');

  const RepeatRule(this.id);
  final String id;

  static RepeatRule? parse(String? id) {
    for (final r in values) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Siguiente fecha (hora local) posterior a [from] y a [after], si se da.
  /// Si la tarea lleva días vencida se salta lo ya pasado. Los meses cortos
  /// usan su último día, sin perder el día original en los siguientes.
  DateTime next(DateTime from, {DateTime? after}) {
    var step = 1;
    while (true) {
      final d = _advance(from, step++);
      if (after == null || d.isAfter(after)) return d;
    }
  }

  DateTime _advance(DateTime d, int n) {
    DateTime at(int y, int m, int day) =>
        DateTime(y, m, day, d.hour, d.minute, d.second);
    switch (this) {
      case RepeatRule.daily:
        return at(d.year, d.month, d.day + n);
      case RepeatRule.weekly:
        return at(d.year, d.month, d.day + 7 * n);
      case RepeatRule.weekdays:
        var r = d;
        for (var i = 0; i < n; i++) {
          r = at(r.year, r.month, r.day + 1);
          while (r.weekday > DateTime.friday) {
            r = at(r.year, r.month, r.day + 1);
          }
        }
        return r;
      case RepeatRule.monthly:
        final last = DateTime(d.year, d.month + n + 1, 0).day;
        return at(d.year, d.month + n, d.day > last ? last : d.day);
      case RepeatRule.yearly:
        final last = DateTime(d.year + n, d.month + 1, 0).day;
        return at(d.year + n, d.month, d.day > last ? last : d.day);
    }
  }
}
