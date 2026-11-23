import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/accounts.dart';
import 'account_dialogs.dart';
import 'anim.dart';
import 'logo.dart';
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
  bool _showPass = false;
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

  InputDecoration _deco(BuildContext c, String label, IconData icon,
      {Widget? suffix}) {
    final p = Palette.of(c);
    OutlineInputBorder side(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: p.background,
      border: side(p.separator, 1),
      enabledBorder: side(p.separator.withValues(alpha: 0.75), 1),
      focusedBorder: side(p.accent, 1.8),
    );
  }

  void _setMode(bool register) {
    if (_busy || register == _register) return;
    setState(() {
      _register = register;
      _msg = null;
    });
  }

  Widget _message(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    final p = Palette.of(context);
    final color = _msgIsError ? error : p.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        key: ValueKey(_msg),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                _msgIsError
                    ? Icons.error_outline_rounded
                    : Icons.mark_email_read_outlined,
                size: 18,
                color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(_msg!,
                  style: TextStyle(color: color, fontSize: 13, height: 1.35)),
            ),
          ],
        ),
      )
          .animate(key: ValueKey(_msg))
          .fadeIn(duration: Anim.fast)
          .shakeX(hz: 5, amount: _msgIsError ? 3 : 0, duration: 380.ms),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final form = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.separator.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
            blurRadius: 34,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSwitch(register: _register, onChanged: _setMode),
          const SizedBox(height: 16),
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            alignment: Alignment.topCenter,
            child: !_register
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      key: const ValueKey('registro-nombre'),
                      contextMenuBuilder: textFieldMenu,
                      controller: _username,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.newUsername],
                      textInputAction: TextInputAction.next,
                      decoration: _deco(
                          context, tr('@nombre'), Icons.person_outline_rounded),
                    ).animate().fadeIn(duration: Anim.medium).slideY(
                        begin: -0.2, duration: Anim.medium, curve: Anim.curve),
                  ),
          ),
          TextField(
            key: const ValueKey('login-usuario'),
            contextMenuBuilder: textFieldMenu,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: [
              _register ? AutofillHints.email : AutofillHints.username
            ],
            textInputAction: TextInputAction.next,
            decoration: _deco(
                context,
                _register ? tr('Correo') : tr('@nombre o correo'),
                Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('login-clave'),
            contextMenuBuilder: textFieldMenu,
            controller: _pass,
            obscureText: !_showPass,
            autofillHints: [
              _register ? AutofillHints.newPassword : AutofillHints.password
            ],
            onSubmitted: (_) => _submit(),
            decoration: _deco(
              context,
              tr('Contraseña'),
              Icons.lock_outline_rounded,
              suffix: IconButton(
                tooltip: _showPass ? tr('Ocultar') : tr('Mostrar'),
                onPressed: () => setState(() => _showPass = !_showPass),
                icon: AnimatedSwitcher(
                  duration: Anim.fast,
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(
                    _showPass
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    key: ValueKey(_showPass),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            alignment: Alignment.topCenter,
            child: _msg == null
                ? const SizedBox(width: double.infinity)
                : _message(context),
          ),
          const SizedBox(height: 16),
          Bouncy(
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: AnimatedSwitcher(
                  duration: Anim.fast,
                  child: _busy
                      ? const SizedBox(
                          key: ValueKey('cargando'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Row(
                          key: ValueKey(_register),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_register ? tr('Crear cuenta') : tr('Entrar'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 19),
                          ],
                        ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Anim.medium,
            curve: Anim.curve,
            child: _register
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => recoverAccountPassword(
                              context,
                              isUsernameLogin(_email.text)
                                  ? ''
                                  : _email.text.trim()),
                      child: Text(tr('¿Has olvidado la contraseña?')),
                    ),
                  ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 410),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Center(child: _LoginLogo()),
                        const SizedBox(height: 14),
                        const Center(
                            child: WaveTitle(text: 'oganesson', fontSize: 38)),
                        const SizedBox(height: 6),
                        Text(
                          tr('Tus notas, siempre contigo.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.secondary, fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        form,
                      ]
                          .animate(interval: 70.ms, delay: 120.ms)
                          .fadeIn(duration: Anim.slow)
                          .slideY(begin: 0.14, curve: Anim.curve),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector Entrar / Crear cuenta con una pastilla que se desliza.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.register, required this.onChanged});
  final bool register;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget option(String label, bool value) {
      final on = register == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: Center(
                child: AnimatedDefaultTextStyle(
                  duration: Anim.medium,
                  curve: Anim.curve,
                  style: TextStyle(
                    fontFamily:
                        Theme.of(context).textTheme.bodyMedium?.fontFamily,
                    fontSize: 14,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                    color: on ? p.onAccent : p.secondary,
                  ),
                  child: Text(label),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: Anim.slow,
            curve: Curves.easeOutBack,
            alignment: register ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.accent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(children: [
            option(tr('Entrar'), false),
            option(tr('Crear cuenta'), true),
          ]),
        ],
      ),
    );
  }
}

/// El logo se escribe solo al abrir la pantalla.
class _LoginLogo extends StatelessWidget {
  const _LoginLogo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [logoNavyTop, logoNavyBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: logoGold[1].withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 1300),
        curve: Curves.easeInOutCubic,
        builder: (_, v, __) => CustomPaint(
          painter: LogoStrokePainter(progress: v, glow: v),
        ),
      ),
    ).animate().scale(
        begin: const Offset(0.7, 0.7),
        duration: 650.ms,
        curve: Curves.easeOutBack);
  }
}

/// Fondo con manchas de luz del color del tema que se mueven muy despacio.
class _LoginBackdrop extends StatefulWidget {
  const _LoginBackdrop();

  @override
  State<_LoginBackdrop> createState() => _LoginBackdropState();
}

class _LoginBackdropState extends State<_LoginBackdrop>
    with SingleTickerProviderStateMixin {
  late final _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 22));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(_ctrl, p.background, p.accent),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.base, this.accent) : super(repaint: t);
  final Animation<double> t;
  final Color base, accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final a = t.value * 2 * math.pi;
    final side = math.max(size.width, size.height);
    final hsl = HSLColor.fromColor(accent);
    final blobs = [
      (0.18 + 0.08 * math.sin(a), 0.16 + 0.07 * math.cos(a), 0.62, accent, 0.2),
      (
        0.86 + 0.07 * math.cos(a + 1),
        0.34 + 0.09 * math.sin(a + 1),
        0.5,
        hsl.withHue((hsl.hue + 38) % 360).toColor(),
        0.13
      ),
      (
        0.42 + 0.1 * math.sin(a + 3),
        0.94 + 0.05 * math.cos(a + 3),
        0.66,
        hsl.withHue((hsl.hue + 320) % 360).toColor(),
        0.14
      ),
    ];
    for (final (x, y, r, color, alpha) in blobs) {
      final c = Offset(size.width * x, size.height * y);
      final radius = side * r;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(c, radius, [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter o) =>
      o.base != base || o.accent != accent;
}
