import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'anim.dart';
import 'theme.dart';

Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 620),
    builder: (_) => const _ThemePicker(),
  );
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeSettings,
      builder: (context, _) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tema',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Elige los colores de la app',
                    style: TextStyle(color: Palette.secondary(context))),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 520 ? 3 : 2;
                  const gap = 12.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (var i = 0; i < appThemes.length; i++)
                        SizedBox(
                          width: w,
                          child: _ThemeCard(
                            theme: appThemes[i],
                            dark: dark,
                            selected: appThemes[i].id == themeSettings.themeId,
                            onTap: () => themeSettings.setTheme(appThemes[i].id),
                          ),
                        )
                            .animate(delay: (50 * i).ms)
                            .fadeIn(duration: Anim.medium)
                            .scale(
                                begin: const Offset(0.9, 0.9),
                                curve: Curves.easeOutBack,
                                duration: Anim.slow),
                    ],
                  );
                }),
                const SizedBox(height: 22),
                const Text('Apariencia',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text('Auto')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Claro')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Oscuro')),
                    ],
                    selected: {themeSettings.mode},
                    onSelectionChanged: (s) => themeSettings.setMode(s.first),
                  ),
                ).animate().fadeIn(delay: 250.ms, duration: Anim.medium),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.dark,
    required this.selected,
    required this.onTap,
  });

  final AppTheme theme;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = dark ? theme.dark : theme.light;
    final fg = dark ? Colors.white : const Color(0xFF111111);

    return Bouncy(
      pressedScale: 0.95,
      hoverScale: 1.03,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          decoration: BoxDecoration(
            color: c.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? c.accent : c.separator,
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ]
                : const [],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mini vista previa de una nota con este tema.
              Container(
                height: 64,
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                              height: 8,
                              width: 60,
                              decoration: BoxDecoration(
                                  color: fg.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(4))),
                          const SizedBox(height: 6),
                          Container(
                              height: 6,
                              width: 90,
                              decoration: BoxDecoration(
                                  color: c.secondary.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                          color: c.accent, shape: BoxShape.circle),
                      child: Icon(Icons.edit, size: 14, color: c.onAccent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(theme.name,
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  AnimatedSwitcher(
                    duration: Anim.medium,
                    transitionBuilder: (w, a) => ScaleTransition(
                      scale: CurvedAnimation(
                          parent: a, curve: Curves.easeOutBack),
                      child: w,
                    ),
                    child: selected
                        ? Icon(Icons.check_circle,
                            key: const ValueKey('si'), color: c.accent, size: 20)
                        : const SizedBox(key: ValueKey('no'), width: 20),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(theme.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.secondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
