import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/accounts.dart';
import 'account_dialogs.dart';
import 'anim.dart';
import 'text_menu.dart';
import 'theme.dart';
import 'wave_title.dart';
import 'i18n.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _msg;
  bool _msgIsError = true;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _pass.dispose();
    super.dispose();
  }

  String _traducir(String m) {
    final l = m.toLowerCase();
    if (l.contains('invalid login')) {
      return tr('Usuario o contraseña incorrectos.');
    }
    if (l.contains('not confirmed')) {
      return tr('Tienes que confirmar el correo antes de entrar.');
    }
    if (l.contains('already registered')) {
      return tr('Ese correo ya tiene cuenta.');
    }
    if (l.contains('password')) {
      return tr('La contraseña no es válida (mínimo 6 caracteres).');
    }
    return m;
  }

  Future<void> _submit() async {
    final login = _email.text.trim();
    final pass = _pass.text;
    if (login.isEmpty || pass.isEmpty) {
      setState(() {
        _msg = _register
            ? tr('Escribe tu correo y tu contraseña.')
            : tr('Escribe tu @nombre o correo y tu contraseña.');
        _msgIsError = true;
      });
      return;
    }
    final username = cleanUsername(_username.text);
    if (_register && !validUsername(username)) {
      setState(() {
        _msg = tr('Usa de 3 a 20 letras, números o guiones bajos.');
        _msgIsError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    final client = Supabase.instance.client;
    final auth = client.auth;
    try {
      if (_register) {
        if (await Accounts(client).usernameAvailable(username) == false) {
          throw AccountException(tr('Ese @nombre ya está cogido.'));
        }
        final res = await auth
            .signUp(email: login, password: pass, data: {'username': username});
        if (res.session == null && mounted) {
          setState(() {
            _msg = tr('Cuenta creada. Confirma el correo que te ha llegado '
                'y después entra.');
            _msgIsError = false;
            _register = false;
          });
        }
      } else {
        var email = login;
        if (isUsernameLogin(login)) {
          final found = await Accounts(client).loginEmail(login, pass);
          if (found == null) {
            throw AccountException(tr('Usuario o contraseña incorrectos.'));
          }
          email = found;
        }
        await auth.signInWithPassword(email: email, password: pass);
      }
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _msg = e.message;
          _msgIsError = true;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _msg = _traducir(e.message);
          _msgIsError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _msg = tr('No se pudo conectar. Revisa tu conexión a internet.');
          _msgIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(BuildContext c, String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Palette.card(c),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final accent = Palette.accent(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Icon(Icons.sticky_note_2_rounded, size: 72, color: accent)
                        .animate()
                        .scale(
                            begin: const Offset(0.3, 0.3),
                            duration: 700.ms,
                            curve: Curves.elasticOut)
                        .rotate(
                            begin: -0.08,
                            duration: 700.ms,
                            curve: Curves.elasticOut),
                    const SizedBox(height: 12),
                    ...<Widget>[
                      const Center(
                          child: WaveTitle(text: 'oganesson', fontSize: 40)),
                      const SizedBox(height: 8),
                      Text(
                        tr('Usa la misma cuenta en el móvil y en el PC para que '
                            'las notas se sincronicen solas.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Palette.secondary(context)),
                      ),
                      const SizedBox(height: 28),
                      AnimatedSize(
                        duration: Anim.medium,
                        curve: Anim.curve,
                        child: !_register
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TextField(
                                  key: const ValueKey('registro-nombre'),
                                  contextMenuBuilder: textFieldMenu,
                                  controller: _username,
                                  autocorrect: false,
                                  autofillHints: const [
                                    AutofillHints.newUsername
                                  ],
                                  textInputAction: TextInputAction.next,
                                  decoration: _deco(context, tr('@nombre'),
                                      Icons.person_outline_rounded),
                                ),
                              ),
                      ),
                      TextField(
                        key: const ValueKey('login-usuario'),
                        contextMenuBuilder: textFieldMenu,
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: [
                          _register
                              ? AutofillHints.email
                              : AutofillHints.username
                        ],
                        textInputAction: TextInputAction.next,
                        decoration: _deco(
                            context,
                            _register ? tr('Correo') : tr('@nombre o correo'),
                            Icons.alternate_email),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        contextMenuBuilder: textFieldMenu,
                        controller: _pass,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _submit(),
                        decoration: _deco(
                            context, tr('Contraseña'), Icons.lock_outline),
                      ),
                      AnimatedSize(
                        duration: Anim.medium,
                        curve: Anim.curve,
                        child: _msg == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Text(
                                  _msg!,
                                  key: ValueKey(_msg),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _msgIsError
                                        ? Theme.of(context).colorScheme.error
                                        : Palette.secondary(context),
                                  ),
                                ).animate(key: ValueKey(_msg)).fadeIn().shakeX(
                                    hz: 5,
                                    amount: _msgIsError ? 4 : 0,
                                    duration: 400.ms),
                              ),
                      ),
                      const SizedBox(height: 20),
                      Bouncy(
                        child: SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  )
                                : Text(
                                    _register
                                        ? tr('Crear cuenta')
                                        : tr('Entrar'),
                                    style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!_register)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => recoverAccountPassword(
                                  context,
                                  isUsernameLogin(_email.text)
                                      ? ''
                                      : _email.text.trim()),
                          child: Text(tr('¿Has olvidado la contraseña?')),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _register = !_register;
                                  _msg = null;
                                }),
                        child: Text(_register
                            ? tr('Ya tengo cuenta, quiero entrar')
                            : tr('¿Primera vez? Crear cuenta')),
                      ),
                    ]
                        .animate(interval: 60.ms, delay: 150.ms)
                        .fadeIn(duration: Anim.slow)
                        .slideY(begin: 0.3, curve: Anim.curve),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
