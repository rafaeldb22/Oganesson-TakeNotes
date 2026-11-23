import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/note_factory.dart';
import '../data/notes_repository.dart';
import '../models/note.dart';
import 'anim.dart';
import 'i18n.dart';
import 'text_menu.dart';
import 'theme.dart';

/// Ctrl+Alt+N: apuntar algo sin salir de lo que estabas haciendo. Devuelve
/// la nota creada, o null si se cancela.
Future<Note?> showQuickCapture(BuildContext context, NotesRepository repo) =>
    Navigator.of(context, rootNavigator: true).push<Note>(PageRouteBuilder(
      opaque: true,
      transitionDuration: Anim.medium,
      reverseTransitionDuration: Anim.fast,
      pageBuilder: (_, __, ___) => QuickCapture(repo: repo),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));

class QuickCapture extends StatefulWidget {
  const QuickCapture({super.key, required this.repo});
  final NotesRepository repo;

  @override
  State<QuickCapture> createState() => _QuickCaptureState();
}

class _QuickCaptureState extends State<QuickCapture> {
  final _text = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop();
  }

  void _save() {
    if (_done || _text.text.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(createNoteFrom(widget.repo, text: _text.text));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final empty = _text.text.trim().isEmpty;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _cancel,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _save,
      },
      child: Scaffold(
        backgroundColor: p.card,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.bolt_rounded, size: 20, color: p.accent),
                const SizedBox(width: 6),
                Text(tr('Nota rápida'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
              Expanded(
                child: TextField(
                  key: const ValueKey('captura'),
                  controller: _text,
                  autofocus: autoKeyboard,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  contextMenuBuilder: textFieldMenu,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16, height: 1.4),
                  decoration: InputDecoration(
                    hintText: tr('Escribe y pulsa Ctrl+Intro…'),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _cancel, child: Text(tr('Cancelar'))),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: empty ? null : _save,
                    child: Text(tr('Guardar')),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: Anim.fast),
      ),
    );
  }
}
