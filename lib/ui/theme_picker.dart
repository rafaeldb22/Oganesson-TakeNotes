import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'anim.dart';
import 'theme.dart';
import 'i18n.dart';

Future<void> showThemePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
        maxWidth: 620, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
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
                Text(tr('Tema'),
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(tr('Elige los colores de la app'),
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
                            onTap: () =>
                                themeSettings.setTheme(appThemes[i].id),
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
                Text(tr('Apariencia'),
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto_outlined),
                          label: Text(tr('Auto'))),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text(tr('Claro'))),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text(tr('Oscuro'))),
                    ],
                    selected: {themeSettings.mode},
                    onSelectionChanged: (s) => themeSettings.setMode(s.first),
                  ),
                ).animate().fadeIn(delay: 250.ms, duration: Anim.medium),
                const SizedBox(height: 22),
                Text(tr('Fuente'),
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (i, f) in appFonts.indexed)
                      _FontChip(
                        font: f,
                        selected: f.id == themeSettings.fontId,
                        onTap: () => themeSettings.setFont(f.id),
                      )
                          .animate(delay: (300 + 40 * i).ms)
                          .fadeIn(duration: Anim.medium)
                          .slideY(begin: 0.2, curve: Anim.curve),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Muestra "Aa" y el nombre en la propia fuente.
class _FontChip extends StatelessWidget {
  const _FontChip(
      {required this.font, required this.selected, required this.onTap});
  final AppFont font;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final style = TextStyle(
        fontFamily: font.family,
        fontFamilyFallback: font.fallback.isEmpty ? null : font.fallback);
    return Bouncy(
      pressedScale: 0.95,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Anim.medium,
          curve: Anim.curve,
          width: 104,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.12) : p.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? p.accent : Colors.transparent, width: 1.6),
          ),
          child: Column(children: [
            Text('Aa',
                style: style.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: selected ? p.accent : null)),
            const SizedBox(height: 4),
            Text(tr(font.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(fontSize: 12.5, color: p.secondary)),
          ]),
        ),
      ),
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
    final c = dark ? theme.dark : theme.lightSoft;
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
                    child: Text(tr(theme.name),
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                  AnimatedSwitcher(
                    duration: Anim.medium,
                    transitionBuilder: (w, a) => ScaleTransition(
                      scale:
                          CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                      child: w,
                    ),
                    child: selected
                        ? Icon(Icons.check_circle,
                            key: const ValueKey('si'),
                            color: c.accent,
                            size: 20)
                        : const SizedBox(key: ValueKey('no'), width: 20),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(tr(theme.description),
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
