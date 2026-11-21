import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'toast.dart';
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
              controller: _a,
              obscureText: !_show,
              enabled: !_busy,
              decoration: _deco(tr('Contraseña nueva')),
            ),
            const SizedBox(height: 10),
            TextField(
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
