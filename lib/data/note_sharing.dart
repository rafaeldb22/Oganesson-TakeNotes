import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/i18n.dart';

/// Una persona con acceso a una nota.
class SharePerson {
  const SharePerson(this.email, this.role, this.isOwner);
  final String email;
  final String role; // owner, edit o read
  final bool isOwner;
}

/// Nota de otra cuenta que se ha compartido conmigo.
class IncomingShare {
  const IncomingShare(this.role, this.ownerEmail);
  final String role;
  final String ownerEmail;
  bool get canEdit => role == 'edit';

  Map<String, String> toJson() => {'role': role, 'owner': ownerEmail};
}

class ShareException implements Exception {
  const ShareException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Traduce los errores de las funciones de la migración 010.
ShareException shareError(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (e.code == 'PGRST202' ||
        e.code == '42883' ||
        m.contains('schema cache')) {
      return ShareException(tr(
          'Falta activar las notas compartidas en Supabase (migración 010).'));
    }
    if (m.contains('invalid_email')) {
      return ShareException(tr('Ese correo no es válido.'));
    }
    if (m.contains('no_account')) {
      return ShareException(
          tr('No hay ninguna cuenta de Oganesson con ese correo.'));
    }
    if (m.contains('self')) {
      return ShareException(tr('Esa es tu propia cuenta.'));
    }
    if (m.contains('vault')) {
      return ShareException(
          tr('Las notas del Vault o de la papelera no se pueden compartir.'));
    }
    if (m.contains('too_many')) {
      return ShareException(
          tr('Una nota se comparte con 20 personas como mucho.'));
    }
    if (m.contains('not_owner')) {
      return ShareException(tr('Solo quien creó la nota puede hacer esto.'));
    }
  }
  return ShareException(tr('No se ha podido. Revisa la conexión.'));
}

/// Compartir notas con otras cuentas (funciones de la migración 010).
class NoteSharing {
  NoteSharing(this._client);
  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() job) async {
    try {
      return await job();
    } catch (e) {
      throw shareError(e);
    }
  }

  Future<void> share(String noteId, String email, String role) =>
      _guard(() => _client.rpc('share_note', params: {
            'p_note': noteId,
            'p_email': email,
            'p_role': role,
          }));

  Future<void> unshare(String noteId, String email) => _guard(() => _client
      .rpc('unshare_note', params: {'p_note': noteId, 'p_email': email}));

  Future<void> leave(String noteId) =>
      _guard(() => _client.rpc('leave_note', params: {'p_note': noteId}));

  Future<List<SharePerson>> people(String noteId) => _guard(() async {
        final rows =
            await _client.rpc('note_people', params: {'p_note': noteId});
        return [
          for (final r in rows as List)
            SharePerson('${r['email']}', '${r['role']}', r['is_owner'] == true)
        ];
      });
}
