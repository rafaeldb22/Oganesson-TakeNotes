import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/notes_repository.dart';
import '../data/reminders.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo.addListener(_reprogramar);
    repo.start().then((_) {
      if (AppConfig.demo) repo.seedDemo();
    });
  }

  void _reprogramar() => Reminders.instance.schedule(repo.notes);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) repo.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    repo.removeListener(_reprogramar);
    repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NotesHome(repo: repo);
}
