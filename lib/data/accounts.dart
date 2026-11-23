import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/i18n.dart';

/// Otra cuenta, vista por su @nombre.
class Person {
  const Person(this.id, this.username, {this.isFriend = false});
  final String id;
  final String username;
  final bool isFriend;
  String get handle => '@$username';
}

class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `@Rafa ` → `rafa`.
String cleanUsername(String s) {
  final t = s.trim().toLowerCase();
  return t.startsWith('@') ? t.substring(1) : t;
}

bool validUsername(String s) =>
    RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(cleanUsername(s));

/// Sin arroba, o empezando por ella, es un @nombre; si no, un correo.
bool isUsernameLogin(String s) {
  final t = s.trim();
  return t.startsWith('@') || !t.contains('@');
}

bool _missingMigration(PostgrestException e) =>
    e.code == 'PGRST202' ||
    e.code == '42883' ||
    e.message.contains('schema cache');

AccountException accountError(Object e) {
  if (e is PostgrestException) {
    final m = e.message;
    if (_missingMigration(e)) {
      return AccountException(
          tr('Falta activar los @nombres en Supabase (migración 012).'));
    }
    if (m.contains('username_taken')) {
      return AccountException(tr('Ese @nombre ya está cogido.'));
    }
    if (m.contains('invalid_username')) {
      return AccountException(
          tr('Usa de 3 a 20 letras, números o guiones bajos.'));
    }
    if (m.contains('too_many_attempts')) {
      return AccountException(
          tr('Demasiados intentos. Espera unos minutos y vuelve a probar.'));
    }
    if (m.contains('too_many')) {
      return AccountException(tr('Has llegado al máximo de amigos.'));
    }
    if (m.contains('no_account')) {
      return AccountException(tr('No hay ninguna cuenta con ese @nombre.'));
    }
    if (m.contains('self')) {
      return AccountException(tr('Esa es tu propia cuenta.'));
    }
  }
  return AccountException(tr('No se ha podido. Revisa la conexión.'));
}

/// @nombres y amigos (funciones de la migración 012).
class Accounts {
  Accounts(this._client);
  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() job) async {
    try {
      return await job();
    } catch (e) {
      throw accountError(e);
    }
  }

  static List<Person> _people(Object? rows) => [
        for (final r in rows as List)
          Person('${r['user_id']}', '${r['username']}',
              isFriend: r['is_friend'] != false),
      ];

  Future<String?> myUsername() =>
      _guard(() async => await _client.rpc('my_username') as String?);

  Future<String> setUsername(String name) => _guard(() async =>
      await _client.rpc('set_username', params: {'p_name': name}) as String);

  /// null si el servidor aún no tiene la migración: no bloquea el registro.
  Future<bool?> usernameAvailable(String name) async {
    try {
      return await _client.rpc('username_available', params: {'p_name': name})
          as bool;
    } on PostgrestException catch (e) {
      if (_missingMigration(e)) return null;
      throw accountError(e);
    } catch (e) {
      throw accountError(e);
    }
  }

  /// Correo de la cuenta, solo si la contraseña es correcta.
  Future<String?> loginEmail(String username, String password) =>
      _guard(() async => await _client.rpc('login_email', params: {
            'p_username': username,
            'p_password': password,
          }) as String?);

  Future<List<Person>> search(String query) => _guard(() async =>
      _people(await _client.rpc('search_users', params: {'p_query': query})));

  Future<List<Person>> friends() =>
      _guard(() async => _people(await _client.rpc('my_friends')));

  Future<void> addFriend(String id) =>
      _guard(() => _client.rpc('add_friend', params: {'p_user': id}));

  Future<void> removeFriend(String id) =>
      _guard(() => _client.rpc('remove_friend', params: {'p_user': id}));
}
