import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';

/// Elegir el idioma de la app (español / inglés).
Future<void> showLanguagePicker(BuildContext context) async {
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('Idioma')),
      children: [
        for (final e in AppLanguage.supported.entries)
          ListTile(
            leading: Icon(
              e.key == appLanguage.code
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: e.key == appLanguage.code ? Palette.accent(ctx) : null,
            ),
            title: Text(e.value),
            subtitle: Text(e.key == 'es' ? tr('Español') : tr('Inglés')),
            onTap: () => Navigator.pop(ctx, e.key),
          ),
      ],
    ),
  );
  if (code != null) await appLanguage.set(code);
}
