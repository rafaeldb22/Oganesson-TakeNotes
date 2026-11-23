import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'toast.dart';
import 'text_menu.dart';
import 'i18n.dart';

/// Cambiar la contraseña de la cuenta escribiendo la actual.
Future<void> changeAccountPassword(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _AccountPasswordDialog(),
  );
  if (ok == true && context.mounted) {
    showToast(context, tr('Contraseña de la cuenta cambiada'),
        icon: Icons.check_circle_outline_rounded);
  }
}

/// Recuperar la contraseña con un código enviado al correo.
Future<void> recoverAccountPassword(BuildContext context, String email) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RecoverPasswordDialog(email: email),
    );

class _RecoverPasswordDialog extends StatefulWidget {
  const _RecoverPasswordDialog({required this.email});
  final String email;

  @override
  State<_RecoverPasswordDialog> createState() => _RecoverPasswordDialogState();
}

class _RecoverPasswordDialogState extends State<_RecoverPasswordDialog> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _sent = false;
  bool _verified = false; // El código solo vale una vez.
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = tr('Ese correo no es válido.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = tr('No se pudo enviar el código. Inténtalo más tarde.'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_busy) return;
    final code = _code.text.trim();
    if (!_verified && code.length < 6) {
      setState(() => _error = tr('Código incorrecto o caducado'));
      return;
    }
    if (_a.text.length < 6) {
      setState(() => _error = trf('Mínimo {0} caracteres', [6]));
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = tr('Las contraseñas no coinciden'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (!_verified) {
        await auth.verifyOTP(
            type: OtpType.recovery, email: _email.text.trim(), token: code);
        _verified = true;
      }
      await auth.updateUser(UserAttributes(password: _a.text));
      if (!mounted) return;
      showToast(context, tr('Contraseña de la cuenta cambiada'),
          icon: Icons.check_circle_outline_rounded);
      Navigator.pop(context);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = !_verified
              ? tr('Código incorrecto o caducado')
              : e.message.toLowerCase().contains('different')
                  ? tr('La contraseña nueva debe ser distinta de la anterior')
                  : e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('No se pudo conectar. Revisa tu conexión a internet.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.mark_email_unread_outlined),
      title: Text(tr('Recuperar contraseña')),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  _sent
                      ? tr('Si hay una cuenta con ese correo, te llegará un código. Mira también en spam.')
                      : tr('Te enviaremos un código para poner una contraseña nueva.'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextField(
                contextMenuBuilder: textFieldMenu,
                controller: _email,
                enabled: !_busy && !_sent,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: tr('Correo'),
                  prefixIcon: const Icon(Icons.alternate_email),
                ),
              ),
              if (_sent) ...[
                const SizedBox(height: 10),
                TextField(
                  contextMenuBuilder: textFieldMenu,
                  controller: _code,
                  autofocus: true,
                  enabled: !_busy && !_verified,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  maxLength: 10,
                  decoration: InputDecoration(
                    hintText: tr('Código del correo'),
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  contextMenuBuilder: textFieldMenu,
                  controller: _a,
                  obscureText: true,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    hintText: tr('Contraseña nueva'),
                    prefixIcon: const Icon(Icons.key_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  contextMenuBuilder: textFieldMenu,
                  controller: _b,
                  obscureText: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: tr('Repite la contraseña nueva'),
                    prefixIcon: const Icon(Icons.key_rounded),
                  ),
                ),
                if (!_verified)
                  TextButton(
                    onPressed: _busy ? null : _send,
                    child: Text(tr('Reenviar código')),
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: Text(tr('Cancelar'))),
        FilledButton(
          onPressed: _busy ? null : (_sent ? _save : _send),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_sent ? tr('Cambiar') : tr('Enviar código')),
        ),
      ],
    );
  }
}

class _AccountPasswordDialog extends StatefulWidget {
  const _AccountPasswordDialog();

  @override
  State<_AccountPasswordDialog> createState() => _AccountPasswordDialogState();
}

class _AccountPasswordDialogState extends State<_AccountPasswordDialog> {
  final _old = TextEditingController();
  final _a = TextEditingController();
  final _b = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final auth = Supabase.instance.client.auth;
    final email = auth.currentUser?.email;
    if (email == null) {
      setState(() => _error = tr('No hay ninguna sesión iniciada'));
      return;
    }
    if (_a.text.length < 6) {
      setState(() => _error = trf('Mínimo {0} caracteres', [6]));
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = tr('Las contraseñas no coinciden'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Comprueba la contraseña actual volviendo a iniciar sesión.
      await auth.signInWithPassword(email: email, password: _old.text);
    } on AuthException {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr('La contraseña actual no es correcta');
        });
      }
      return;
    }
    try {
      await auth.updateUser(UserAttributes(password: _a.text));
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.key_rounded),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.manage_accounts_outlined),
      title: Text(tr('Cambiar contraseña de la cuenta')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              contextMenuBuilder: textFieldMenu,
              controller: _old,
              autofocus: true,
              obscureText: !_show,
              enabled: !_busy,
              decoration: _deco(tr('Contraseña actual')).copyWith(
                suffixIcon: IconButton(
                  tooltip: _show ? tr('Ocultar') : tr('Mostrar'),
                  icon: Icon(_show
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              contextMenuBuilder: textFieldMenu,
              controller: _a,
              obscureText: !_show,
              enabled: !_busy,
              decoration: _deco(tr('Contraseña nueva')),
            ),
            const SizedBox(height: 10),
            TextField(
              contextMenuBuilder: textFieldMenu,
              controller: _b,
              obscureText: !_show,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
              decoration: _deco(tr('Repite la contraseña nueva')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancelar'))),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('Cambiar')),
        ),
      ],
    );
  }
}
