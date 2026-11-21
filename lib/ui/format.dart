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
