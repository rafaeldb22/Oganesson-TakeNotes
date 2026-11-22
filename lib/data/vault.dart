import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hash de la contraseña maestra (nunca se guarda la contraseña).
class _PasswordHash {
  _PasswordHash(this.salt, this.iterations, this.hash, this.updatedAt);

  final List<int> salt;
  final int iterations;
  final List<int> hash;
  final DateTime updatedAt;

  String encode() => jsonEncode({
        'v': 1,
        'kdf': 'pbkdf2-sha256',
        'iter': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'updated_at': updatedAt.toIso8601String(),
      });

  static _PasswordHash? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['hash'] == null) return null; // formato antiguo (no válido)
      return _PasswordHash(
        base64Decode(j['salt'] as String),
        (j['iter'] as num).toInt(),
        base64Decode(j['hash'] as String),
        DateTime.parse(j['updated_at'] as String).toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}

enum VaultState { loading, notSet, locked, unlocked }

/// Cerradura del Vault: las notas marcadas como `vault` solo se ven con la
/// contraseña maestra.
///  - La contraseña se guarda como hash PBKDF2-SHA256 (sal aleatoria) en el
///    dispositivo y en la tabla `vaults` de Supabase, así sirve la misma en
///    Windows y Android.
///  - Se bloquea sola, sin avisar, tras [autoLock] sin actividad.
///  - Si se olvida, se cambia con un código de 6 dígitos enviado al correo
///    de la cuenta (Supabase Auth, `signInWithOtp` + `verifyOTP`).
class VaultLock extends ChangeNotifier {
  VaultLock._(this.userId);

  static final _locks = <String, VaultLock>{};

  static VaultLock forUser(String userId) =>
      _locks.putIfAbsent(userId, () => VaultLock._(userId));

  /// Bloquea todo (al cerrar sesión).
  static void lockAll() {
    for (final l in _locks.values) {
      l.lock();
    }
  }

  static const autoLock = Duration(minutes: 5);
  static const minPasswordLength = 6;
  static const _iterations = 210000;

  final String userId;
  VaultState state = VaultState.loading;

  /// true si la contraseña aún no se ha podido guardar en Supabase.
  bool pendingUpload = false;

  _PasswordHash? _hash;
  DateTime _lastActivity = DateTime.now();
  Timer? _timer;
  int _failures = 0;
  DateTime? _blockedUntil;
  bool _loaded = false;

  bool get unlocked => state == VaultState.unlocked;

  String get _prefsKey => 'vault_pass_$userId';
  String get _pendingKey => 'vault_pass_pendiente_$userId';

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Correo de la cuenta (a donde llega el código para cambiar la contraseña).
  String? get email => _client?.auth.currentUser?.email;

  /// Segundos de espera tras varios intentos fallidos (0 = puede intentar).
  int get blockedSeconds {
    final until = _blockedUntil;
    if (until == null) return 0;
    final s = until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s + 1 : 0;
  }

  /// Hay actividad en la app: reinicia los 5 minutos.
  void touch() {
    if (unlocked) _lastActivity = DateTime.now();
  }

  // ---------------------------------------------------------- carga

  /// Lee el hash (dispositivo + Supabase, gana el más reciente).
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final prefs = await SharedPreferences.getInstance();
    var hash = _PasswordHash.decode(prefs.getString(_prefsKey));
    pendingUpload = prefs.getBool(_pendingKey) ?? false;

    final remote = await _fetchRemote();
    if (remote != null &&
        (hash == null || remote.updatedAt.isAfter(hash.updatedAt))) {
      hash = remote;
      await prefs.setString(_prefsKey, remote.encode());
    } else if (hash != null && pendingUpload) {
      await _upload(hash);
    }
    _hash = hash;
    _loaded = true;
    if (!unlocked) {
      state = hash == null ? VaultState.notSet : VaultState.locked;
    }
    notifyListeners();
  }

  Future<_PasswordHash?> _fetchRemote() async {
    final client = _client;
    if (client == null) return null;
    try {
      final row = await client
          .from('vaults')
          .select('data')
          .eq('user_id', userId)
          .maybeSingle();
      return _PasswordHash.decode(row?['data'] as String?);
    } catch (e) {
      debugPrint('Vault: no se pudo leer de Supabase ($e)');
      return null;
    }
  }

  Future<void> _upload(_PasswordHash h) async {
    final client = _client;
    var ok = false;
    if (client != null) {
      try {
        await client.from('vaults').upsert({
          'user_id': userId,
          'data': h.encode(),
          'updated_at': h.updatedAt.toIso8601String(),
        });
        ok = true;
      } catch (e) {
        debugPrint('Vault: no se pudo guardar en Supabase ($e)');
      }
    }
    pendingUpload = !ok;
    try {
      (await SharedPreferences.getInstance()).setBool(_pendingKey, !ok);
    } catch (_) {}
  }

  // ---------------------------------------------------- contraseña

  /// Crea o cambia la contraseña maestra y deja el Vault abierto.
  Future<void> setPassword(String password) async {
    final salt = _randomBytes(16);
    final hash = await _derive(password, salt, _iterations);
    final h = _PasswordHash(salt, _iterations, hash, DateTime.now().toUtc());
    _hash = h;
    await (await SharedPreferences.getInstance())
        .setString(_prefsKey, h.encode());
    _failures = 0;
    _blockedUntil = null;
    _open();
    await _upload(h);
    notifyListeners();
  }

  /// Abre el Vault si la contraseña es correcta.
  Future<bool> unlock(String password) async {
    final h = _hash;
    if (h == null || blockedSeconds > 0) return false;
    final hash = await _derive(password, h.salt, h.iterations);
    if (_equals(hash, h.hash)) {
      _failures = 0;
      _blockedUntil = null;
      _open();
      return true;
    }
    // Tras 5 fallos seguidos, espera creciente (30 s, 60 s, …).
    _failures++;
    if (_failures >= 5) {
      _blockedUntil =
          DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
    }
    notifyListeners();
    return false;
  }

  void lock() {
    _timer?.cancel();
    _timer = null;
    if (unlocked) {
      state = VaultState.locked;
      notifyListeners();
    }
  }

  void _open() {
    state = VaultState.unlocked;
    _lastActivity = DateTime.now();
    _timer?.cancel();
    // Comprueba cada pocos segundos; se bloquea sin avisar.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_lastActivity) >= autoLock) lock();
    });
    notifyListeners();
  }

  // ------------------------------- con la contraseña de la cuenta

  /// Se puede usar la contraseña de la cuenta (sesión con correo).
  bool get canUseAccountPassword => _client != null && email != null;

  /// Comprueba la contraseña de la cuenta de Oganesson para poder cambiar
  /// la del Vault sin saber la actual. true = correcta, false = incorrecta,
  /// null = no se pudo comprobar (sin conexión). Los fallos cuentan para el
  /// bloqueo por intentos, igual que con la contraseña maestra.
  Future<bool?> verifyAccountPassword(String password) async {
    final client = _client;
    final mail = email;
    if (client == null || mail == null || blockedSeconds > 0) return false;
    try {
      final res =
          await client.auth.signInWithPassword(email: mail, password: password);
      if (res.user?.id == userId) {
        _failures = 0;
        _blockedUntil = null;
        return true;
      }
    } on AuthRetryableFetchException catch (e) {
      debugPrint('Vault: sin conexión al comprobar la cuenta (${e.message})');
      return null;
    } on AuthException catch (e) {
      debugPrint('Vault: contraseña de la cuenta incorrecta (${e.message})');
    } catch (e) {
      debugPrint('Vault: no se pudo comprobar la cuenta ($e)');
      return null;
    }
    _failures++;
    if (_failures >= 5) {
      _blockedUntil =
          DateTime.now().add(Duration(seconds: 30 * (_failures - 4)));
    }
    notifyListeners();
    return false;
  }

  // ------------------------------------------- olvidé la contraseña

  /// Envía un código de 6 dígitos al correo de la cuenta.
  Future<void> sendResetCode() async {
    final client = _client;
    final mail = email;
    if (client == null || mail == null) {
      throw StateError('Hace falta haber iniciado sesión con correo');
    }
    await client.auth.signInWithOtp(email: mail, shouldCreateUser: false);
  }

  /// Comprueba el código del correo. Si es válido, se puede poner una
  /// contraseña nueva con [setPassword].
  Future<bool> verifyResetCode(String code) async {
    final client = _client;
    final mail = email;
    if (client == null || mail == null) return false;
    try {
      final res = await client.auth
          .verifyOTP(type: OtpType.email, email: mail, token: code.trim());
      return res.user?.id == userId;
    } on AuthException catch (e) {
      debugPrint('Vault: código no válido (${e.message})');
      return false;
    }
  }

  // ----------------------------------------------------- utilidades

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  /// PBKDF2 en otro isolate para no congelar la interfaz.
  static Future<List<int>> _derive(
      String password, List<int> salt, int iterations) {
    return Isolate.run(() async {
      final k = await Pbkdf2.hmacSha256(iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);
      return k.extractBytes();
    });
  }
}
