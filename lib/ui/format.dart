const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
const _dias = [
  'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "14:05", "Ayer", "martes" o "21/11/26", como en la lista de Notas.
String fechaCorta(DateTime utc) {
  final d = utc.toLocal();
  final now = DateTime.now();
  final hoy = DateTime(now.year, now.month, now.day);
  final dia = DateTime(d.year, d.month, d.day);
  final diff = hoy.difference(dia).inDays;
  if (diff <= 0) return '${d.hour}:${_two(d.minute)}';
  if (diff == 1) return 'Ayer';
  if (diff < 7) return _dias[d.weekday - 1];
  return '${d.day}/${d.month}/${_two(d.year % 100)}';
}

/// "21 de noviembre de 2026, 0:14"
String fechaLarga(DateTime utc) {
  final d = utc.toLocal();
  return '${d.day} de ${_meses[d.month - 1]} de ${d.year}, '
      '${d.hour}:${_two(d.minute)}';
}

const mesesNombre = _meses;

String nombreMes(int month, int year) =>
    '${_meses[month - 1][0].toUpperCase()}${_meses[month - 1].substring(1)} $year';

/// "14 nov, 18:30"
String fechaMedia(DateTime utc) {
  final d = utc.toLocal();
  return '${d.day} ${_meses[d.month - 1].substring(0, 3)}, '
      '${d.hour}:${_two(d.minute)}';
}

/// "quedan 2 d 4 h", "quedan 35 min", "vencida hace 3 h".
String tiempoRestante(DateTime dueUtc, {bool done = false}) {
  if (done) return 'completada';
  final diff = dueUtc.difference(DateTime.now().toUtc());
  final past = diff.isNegative;
  final d = diff.abs();
  String txt;
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    txt = h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
  } else if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    txt = m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  } else {
    txt = '${d.inMinutes.clamp(1, 59)} min';
  }
  return past ? 'vencida hace $txt' : 'quedan $txt';
}

/// Grupo temporal para ordenar las notas temporales por tiempo.
String grupoTemporal(DateTime dueUtc, {bool done = false}) {
  if (done) return 'Completadas';
  final d = dueUtc.toLocal();
  final now = DateTime.now();
  final hoy = DateTime(now.year, now.month, now.day);
  final dia = DateTime(d.year, d.month, d.day);
  if (dueUtc.isBefore(now.toUtc())) return 'Vencidas';
  final diff = dia.difference(hoy).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Mañana';
  if (diff < 7) return 'Esta semana';
  if (diff < 31) return 'Este mes';
  return 'Más adelante';
}

const ordenGrupos = [
  'Vencidas', 'Hoy', 'Mañana', 'Esta semana', 'Este mes', 'Más adelante',
  'Completadas',
];
