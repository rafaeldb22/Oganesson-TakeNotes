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

/// create: primera vez · change: con la actual (o la de la cuenta) ·
/// reset: tras el código del correo · account: olvidada, con la de la cuenta.
enum _Mode { create, change, reset, account }

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
    super.key,
    required this.controller,
    required this.hint,
    this.icon = Icons.key_rounded,
    this.autofocus = false,
    this.onSubmitted,
    this.enabled = true,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
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
          prefixIcon: Icon(widget.icon),
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
    // Con la contraseña de la cuenta si hay sesión con correo; si no, con
    // un código por correo (solo con SMTP propio, AppConfig.emailCodes).
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => widget.vault.canUseAccountPassword
          ? _NewPasswordDialog(vault: widget.vault, mode: _Mode.account)
          : _ResetDialog(vault: widget.vault),
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
              autofocus: autoKeyboard,
              enabled: !_busy,
              onSubmitted: _submit,
            ),
            _errorText(context, _error),
            const SizedBox(height: 4),
            // Restablecer con la contraseña de la cuenta (o por correo, solo
            // con SMTP propio configurado en Supabase: AppConfig.emailCodes).
            if (widget.vault.canUseAccountPassword || AppConfig.emailCodes)
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

  /// Cambiar con la contraseña de la cuenta en vez de la del Vault.
  late bool _useAccount = widget.mode == _Mode.account;

  @override
  void dispose() {
    _old.dispose();
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    // Cambiar la contraseña exige escribir la actual o la de la cuenta.
    if (widget.mode == _Mode.change || widget.mode == _Mode.account) {
      if (_old.text.isEmpty) {
        setState(() => _error = _useAccount
            ? tr('Escribe la contraseña de tu cuenta')
            : tr('Escribe la contraseña actual'));
        return;
      }
      setState(() {
        _busy = true;
        _error = null;
      });
      final bool? ok = _useAccount
          ? await widget.vault.verifyAccountPassword(_old.text)
          : await widget.vault.unlock(_old.text);
      if (!mounted) return;
      if (ok != true) {
        setState(() {
          _busy = false;
          _error = ok == null
              ? tr('No se pudo comprobar. Revisa la conexión.')
              : widget.vault.blockedSeconds > 0
                  ? trf('Demasiados intentos. Espera {0} s',
                      [widget.vault.blockedSeconds])
                  : _useAccount
                      ? tr('La contraseña de la cuenta no es correcta')
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
              'se verán con ella. Puedes cambiarla desde ⋯ con la actual o con '
              'la contraseña de tu cuenta.')
        ),
      _Mode.change => (
          Icons.password_rounded,
          tr('Cambiar contraseña del Vault'),
          _useAccount
              ? tr('Escribe la contraseña de tu cuenta y la nueva del Vault.')
              : tr('Escribe la contraseña actual y la nueva.')
        ),
      _Mode.account => (
          Icons.manage_accounts_outlined,
          tr('Restablecer con tu cuenta'),
          trf(
              'Escribe la contraseña de tu cuenta ({0}) y elige una '
              'contraseña maestra nueva.',
              [widget.vault.email ?? ''])
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
            if (widget.mode == _Mode.change ||
                widget.mode == _Mode.account) ...[
              AnimatedSwitcher(
                duration: Anim.medium,
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.25), end: Offset.zero)
                        .animate(CurvedAnimation(parent: a, curve: Anim.curve)),
                    child: c,
                  ),
                ),
                child: _PasswordField(
                    key: ValueKey(_useAccount),
                    controller: _old,
                    hint: _useAccount
                        ? tr('Contraseña de tu cuenta')
                        : tr('Contraseña actual del Vault'),
                    icon: _useAccount
                        ? Icons.account_circle_outlined
                        : Icons.key_rounded,
                    autofocus: autoKeyboard,
                    enabled: !_busy),
              ),
              // Cambiar entre la contraseña del Vault y la de la cuenta.
              if (widget.mode == _Mode.change &&
                  widget.vault.canUseAccountPassword)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _useAccount = !_useAccount;
                              _old.clear();
                              _error = null;
                            }),
                    icon: Icon(
                        _useAccount
                            ? Icons.key_rounded
                            : Icons.account_circle_outlined,
                        size: 18),
                    label: Text(_useAccount
                        ? tr('Usar la contraseña del Vault')
                        : tr('Usar la contraseña de la cuenta')),
                  ),
                )
              else
                const SizedBox(height: 10),
            ],
            _PasswordField(
                controller: _a,
                hint:
                    widget.mode == _Mode.change || widget.mode == _Mode.account
                        ? tr('Contraseña nueva')
                        : tr('Contraseña maestra'),
                autofocus: autoKeyboard &&
                    widget.mode != _Mode.change &&
                    widget.mode != _Mode.account,
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
                  autofocus: autoKeyboard,
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
