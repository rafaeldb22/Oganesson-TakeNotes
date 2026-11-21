import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../config.dart';
import '../data/vault.dart';
import 'anim.dart';
import 'toast.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';

/// Se asegura de que el Vault esté abierto: lo crea la primera vez o pide la
/// contraseña maestra. Devuelve true si queda abierto.
Future<bool> ensureVaultOpen(BuildContext context, VaultLock vault) async {
  await vault.load();
  if (vault.unlocked) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => vault.state == VaultState.notSet
        ? _NewPasswordDialog(vault: vault, mode: _Mode.create)
        : _UnlockDialog(vault: vault),
  );
  return ok == true && vault.unlocked;
}

/// Cambiar la contraseña maestra (con el Vault abierto).
Future<void> changeVaultPassword(BuildContext context, VaultLock vault) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _NewPasswordDialog(vault: vault, mode: _Mode.change),
  );
  if (ok == true && context.mounted) {
    showToast(context, tr('Contraseña del Vault cambiada'),
        icon: Icons.check_circle_outline_rounded);
  }
}

enum _Mode { create, change, reset }

Widget _header(BuildContext context, IconData icon, String title, String text) {
  final p = Palette.of(context);
  return Column(
    children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 30, color: p.accent),
      ).animate().scale(
          begin: const Offset(0.8, 0.8),
          curve: Curves.easeOutBack,
          duration: Anim.slow),
      const SizedBox(height: 14),
      Text(title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(color: p.secondary, height: 1.35, fontSize: 13.5)),
      const SizedBox(height: 18),
    ],
  );
}

Widget _errorText(BuildContext context, String? error) => AnimatedSize(
      duration: Anim.fast,
      child: error == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ).animate().shakeX(hz: 5, amount: 4),
    );

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.onSubmitted,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => TextField(
        contextMenuBuilder: textFieldMenu,
        controller: widget.controller,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        obscureText: !_show,
        onSubmitted: (_) => widget.onSubmitted?.call(),
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.key_rounded),
          suffixIcon: IconButton(
            tooltip: _show ? tr('Ocultar') : tr('Mostrar'),
            icon: Icon(_show
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
      );
}

Widget _busyLabel(bool busy, String label) => busy
    ? const SizedBox(
        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
    : Text(label);

// ------------------------------------------------------------ desbloquear

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.vault});
  final VaultLock vault;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pass.text.isEmpty || _busy) return;
    final wait = widget.vault.blockedSeconds;
    if (wait > 0) {
      setState(() => _error = 'Demasiados intentos. Espera $wait s');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.unlock(_pass.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _pass.clear();
      setState(() {
        _busy = false;
        _error = tr('Contraseña incorrecta');
      });
    }
  }

  Future<void> _forgot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ResetDialog(vault: widget.vault),
    );
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, Icons.lock_outline_rounded, tr('Vault bloqueado'),
                tr('Escribe la contraseña maestra para ver las notas del Vault.')),
            _PasswordField(
              controller: _pass,
              hint: tr('Contraseña maestra'),
              autofocus: true,
              enabled: !_busy,
              onSubmitted: _submit,
            ),
            _errorText(context, _error),
            const SizedBox(height: 4),
            // Restablecer por correo: solo con SMTP propio configurado en
            // Supabase (AppConfig.emailCodes).
            if (AppConfig.emailCodes)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: Text(tr('¿Has olvidado la contraseña?')),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancelar'))),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busyLabel(_busy, tr('Desbloquear'))),
      ],
    );
  }
}

// ------------------------------------------- crear / cambiar contraseña

class _NewPasswordDialog extends StatefulWidget {
  const _NewPasswordDialog({required this.vault, required this.mode});
  final VaultLock vault;
  final _Mode mode;

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _old = TextEditingController();
  final _a = TextEditingController();
  final _b = TextEditingController();
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
    // Cambiar la contraseña exige escribir la actual.
    if (widget.mode == _Mode.change) {
      if (_old.text.isEmpty) {
        setState(() => _error = tr('Escribe la contraseña actual'));
        return;
      }
      setState(() => _busy = true);
      final ok = await widget.vault.unlock(_old.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = widget.vault.blockedSeconds > 0
              ? trf('Demasiados intentos. Espera {0} s',
                  [widget.vault.blockedSeconds])
              : tr('La contraseña actual no es correcta');
        });
        return;
      }
      setState(() => _busy = false);
    }
    if (_a.text.length < VaultLock.minPasswordLength) {
      setState(() =>
          _error = trf('Mínimo {0} caracteres', [VaultLock.minPasswordLength]));
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
    await widget.vault.setPassword(_a.text);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, title, text) = switch (widget.mode) {
      _Mode.create => (
          Icons.shield_outlined,
          tr('Crea tu Vault'),
          tr('Elige una contraseña maestra. Las notas que muevas al Vault solo '
              'se verán con ella. Puedes cambiarla desde ⋯ escribiendo la '
              'actual.')
        ),
      _Mode.change => (
          Icons.password_rounded,
          tr('Cambiar contraseña del Vault'),
          tr('Escribe la contraseña actual y la nueva.')
        ),
      _Mode.reset => (
          Icons.lock_reset_rounded,
          tr('Nueva contraseña'),
          tr('Código correcto. Elige una contraseña maestra nueva.')
        ),
    };
    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context, icon, title, text),
            if (widget.mode == _Mode.change) ...[
              _PasswordField(
                  controller: _old,
                  hint: tr('Contraseña actual'),
                  autofocus: true,
                  enabled: !_busy),
              const SizedBox(height: 10),
            ],
            _PasswordField(
                controller: _a,
                hint: widget.mode == _Mode.change
                    ? tr('Contraseña nueva')
                    : tr('Contraseña maestra'),
                autofocus: widget.mode != _Mode.change,
                enabled: !_busy),
            const SizedBox(height: 10),
            _PasswordField(
                controller: _b,
                hint: tr('Repite la contraseña'),
                enabled: !_busy,
                onSubmitted: _submit),
            _errorText(context, _error),
          ],
        ),
      ),
      actions: [
        if (widget.mode != _Mode.reset)
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancelar'))),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busyLabel(
                _busy,
                widget.mode == _Mode.create
                    ? tr('Crear Vault')
                    : tr('Guardar'))),
      ],
    );
  }
}

// ------------------------------------- olvidé la contraseña (código)

class _ResetDialog extends StatefulWidget {
  const _ResetDialog({required this.vault});
  final VaultLock vault;

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// "rafa@gmail.com" → "r•••@gmail.com"
  String _masked(String? mail) {
    if (mail == null) return tr('tu correo');
    final at = mail.indexOf('@');
    if (at <= 1) return mail;
    return '${mail[0]}•••${mail.substring(at)}';
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.vault.sendResetCode();
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = tr('No se pudo enviar el código. Inténtalo más tarde.'));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.verifyResetCode(code);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = tr('Código incorrecto o caducado');
      });
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _NewPasswordDialog(vault: widget.vault, mode: _Mode.reset),
    );
    if (mounted) Navigator.pop(context, changed == true);
  }

  @override
  Widget build(BuildContext context) {
    final mail = _masked(widget.vault.email);
    return AlertDialog(
      content: SizedBox(
        width: 360,
        child: AnimatedSize(
          duration: Anim.medium,
          curve: Anim.curve,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(
                  context,
                  Icons.mark_email_unread_outlined,
                  tr('Cambiar contraseña'),
                  _sent
                      ? trf(
                          'Hemos enviado un código de 6 dígitos a {0}. '
                          'Escríbelo aquí.',
                          [mail])
                      : trf(
                          'Te enviaremos un código a {0} para poner una '
                          'contraseña maestra nueva.',
                          [mail])),
              if (_sent)
                TextField(
                  contextMenuBuilder: textFieldMenu,
                  controller: _code,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  onChanged: (v) {
                    if (v.trim().length == 6) _verify();
                  },
                  style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 10,
                      fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                      hintText: '000000', counterText: ''),
                ).animate().fadeIn(duration: Anim.medium),
              _errorText(context, _error),
              if (_sent)
                TextButton(
                  onPressed: _busy ? null : _send,
                  child: Text(tr('Reenviar código')),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancelar'))),
        FilledButton(
          onPressed: _busy ? null : (_sent ? _verify : _send),
          child:
              _busyLabel(_busy, _sent ? tr('Comprobar') : tr('Enviar código')),
        ),
      ],
    );
  }
}
