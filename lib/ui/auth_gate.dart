import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/note_images.dart';
import '../data/notes_repository.dart';
import '../data/reminders.dart';
import '../data/vault.dart';
import '../data/widget_bridge.dart';
import 'login_screen.dart';
import 'notes_home.dart';

/// Muestra el login o las notas según haya sesión iniciada.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.demo) {
      return const NotesShell(key: ValueKey('demo'), userId: 'demo');
    }
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snap) {
        final session = snap.data?.session ?? auth.currentSession;
        if (session == null) return const LoginScreen();
        return NotesShell(
          key: ValueKey(session.user.id),
          userId: session.user.id,
        );
      },
    );
  }
}

class NotesShell extends StatefulWidget {
  const NotesShell({super.key, required this.userId});
  final String userId;

  @override
  State<NotesShell> createState() => _NotesShellState();
}

class _NotesShellState extends State<NotesShell> with WidgetsBindingObserver {
  late final NotesRepository repo =
      NotesRepository(Supabase.instance.client, widget.userId);
  late final VaultLock vault = VaultLock.forUser(widget.userId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Las notas del Vault solo se ven con el Vault abierto.
    repo.vaultUnlocked = () => vault.unlocked;
    vault.addListener(repo.vaultChanged);
    vault.load();
    // Imágenes de las notas: caché local, subida y cola pendiente.
    NoteImages.instance.attach(
        AppConfig.demo ? null : Supabase.instance.client, widget.userId);
    repo.addListener(_reprogramar);
    repo.start().then((_) {
      if (AppConfig.demo) repo.seedDemo();
    });
  }

  // Todas las notas, también las del Vault (sus avisos no muestran el título).
  void _reprogramar() => Reminders.instance.schedule(repo.allActive);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      repo.sync();
      NoteImages.instance.retryPending();
      // Redibuja los widgets (p. ej. la cuenta atrás de "Próxima tarea").
      WidgetBridge.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vault.removeListener(repo.vaultChanged);
    vault.lock();
    repo.removeListener(_reprogramar);
    repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotesHome(repo: repo);
}
