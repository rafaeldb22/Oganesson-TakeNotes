import '../models/note.dart';
import 'i18n.dart';

const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _daysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

bool get _en => appLanguage.isEnglish;

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
const _dias = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
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
  if (diff == 1) return _en ? 'Yesterday' : 'Ayer';
  if (diff < 7) return (_en ? _daysEn : _dias)[d.weekday - 1];
  return _en
      ? '${d.month}/${d.day}/${_two(d.year % 100)}'
      : '${d.day}/${d.month}/${_two(d.year % 100)}';
}

/// "120 palabras · 640 caracteres" (sin contar imágenes ni saltos de línea).
/// Un día, pasado o futuro: "hoy", "mañana", "ayer" o "vie 5 dic".
/// (`fechaCorta` es para "cuándo se editó": hoy da la hora.)
String fechaDia(DateTime when) {
  final d = when.toLocal();
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (diff == 0) return _en ? 'today' : 'hoy';
  if (diff == 1) return _en ? 'tomorrow' : 'mañana';
  if (diff == -1) return _en ? 'yesterday' : 'ayer';
  final wd =
      (_en ? _daysEn : _dias)[d.weekday - 1].substring(0, 3).toLowerCase();
  final month = _en
      ? _monthsEn[d.month - 1].substring(0, 3)
      : _meses[d.month - 1].substring(0, 3);
  final year = d.year == now.year ? '' : ' ${d.year}';
  return _en ? '$wd, $month ${d.day}$year' : '$wd ${d.day} $month$year';
}

String textStats(String text) {
  final t = text.replaceAll('￼', '');
  final words = RegExp(r'\S+').allMatches(t).length;
  final chars = t.replaceAll('\n', '').length;
  return '${trn(words, '{0} palabra', '{0} palabras')} · '
      '${trn(chars, '{0} carácter', '{0} caracteres')}';
}

/// "21 de noviembre de 2026, 0:14"
String fechaLarga(DateTime utc) {
  final d = utc.toLocal();
  if (_en) {
    return '${_monthsEn[d.month - 1]} ${d.day}, ${d.year}, '
        '${d.hour}:${_two(d.minute)}';
  }
  return '${d.day} de ${_meses[d.month - 1]} de ${d.year}, '
      '${d.hour}:${_two(d.minute)}';
}

const mesesNombre = _meses;

String nombreMes(int month, int year) => _en
    ? '${_monthsEn[month - 1]} $year'
    : '${_meses[month - 1][0].toUpperCase()}${_meses[month - 1].substring(1)} $year';

/// "14 nov, 18:30"
String fechaMedia(DateTime utc) {
  final d = utc.toLocal();
  if (_en) {
    return '${_monthsEn[d.month - 1].substring(0, 3)} ${d.day}, '
        '${d.hour}:${_two(d.minute)}';
  }
  return '${d.day} ${_meses[d.month - 1].substring(0, 3)}, '
      '${d.hour}:${_two(d.minute)}';
}

/// Fecha límite de una nota: sin hora si es de todo el día.
String fechaNota(Note n) {
  final text = fechaMedia(n.dueAt!);
  return n.isAllDay ? text.substring(0, text.lastIndexOf(',')) : text;
}

/// Duración legible con minutos redondeados y sin partes a cero:
/// "2 d", "2 d 3 h", "5 h 30 min", "45 min".
String duracionTexto(Duration d) {
  final mins = (d.inSeconds.abs() / 60).round();
  final days = mins ~/ 1440;
  final hours = (mins % 1440) ~/ 60;
  final m = mins % 60;
  if (days >= 1) return hours == 0 ? '$days d' : '$days d $hours h';
  if (hours >= 1) return m == 0 ? '$hours h' : '$hours h $m min';
  return '$m min';
}

/// "quedan 2 d 4 h", "quedan 35 min", "vencida hace 3 h".
String tiempoRestante(DateTime dueUtc, {bool done = false}) {
  if (done) return _en ? 'completed' : 'completada';
  final diff = dueUtc.toUtc().difference(DateTime.now().toUtc());
  // Menos de medio minuto: vence ahora mismo.
  if (diff.inSeconds.abs() < 30) return _en ? 'due now' : 'vence ahora';
  final txt = duracionTexto(diff);
  if (_en) return diff.isNegative ? 'overdue by $txt' : '$txt left';
  return diff.isNegative ? 'vencida hace $txt' : 'quedan $txt';
}

/// Tiempo de una nota temporal: "Hoy · quedan 5 h" en su día, "terminó hace
/// 2 días" para un evento pasado, o lo que queda / lo vencido.
String tiempoNota(Note n) {
  if (n.done) return tiempoRestante(n.dueAt!, done: true);
  final end = n.barEnd!;
  if (n.isToday()) {
    final left = duracionTexto(end.difference(DateTime.now().toUtc()));
    return _en ? 'Today · $left left' : 'Hoy · quedan $left';
  }
  if (!n.checkable && n.isPast()) {
    final ago = duracionTexto(DateTime.now().toUtc().difference(end));
    return _en ? 'ended $ago ago' : 'terminó hace $ago';
  }
  return tiempoRestante(end);
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
  'Vencidas',
  'Hoy',
  'Mañana',
  'Esta semana',
  'Este mes',
  'Más adelante',
  'Completadas',
];

/// Iniciales de los días de la semana (lunes primero) en el idioma actual.
List<String> get diasIniciales => _en
    ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
    : const ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
