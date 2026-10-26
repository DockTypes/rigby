import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/models/app_settings.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/widgets/rigby_mascot.dart';
import '../../chat/widgets/voice_visualizer.dart';


class RigbySettingsSheet extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const RigbySettingsSheet({super.key, this.onSettingsChanged});

  @override
  State<RigbySettingsSheet> createState() => _RigbySettingsSheetState();
}

class _RigbySettingsSheetState extends State<RigbySettingsSheet> {
  final ValueNotifier<double> _idleAmplitude = ValueNotifier(0.0);

  @override
  void dispose() {
    _idleAmplitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);
    final sheetBg = isDark ? const Color(0xFF080808) : Colors.white;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: BoxDecoration(
            color: sheetBg.withValues(alpha: isDark ? 0.95 : 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: fg.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 14),
              Container(
                width: 40, height: 3,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              RigbyMascot(
                state: VisualizerState.idle,
                amplitude: _idleAmplitude,
                size: 100,
              ),
              const SizedBox(height: 10),
              Text(
                'SETĂRI Rigby',
                style: TextStyle(
                  color: fg.withValues(alpha: 0.35),
                  fontSize: 9,
                  letterSpacing: 4.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              Divider(
                color: fg.withValues(alpha: 0.08),
                height: 1, indent: 24, endIndent: 24,
              ),

              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, bottomPad + 24),
                  children: [
                    _SectionLabel(label: 'APARENȚĂ'),
                    const SizedBox(height: 10),
                    _SegmentedSetting(
                      icon: Icons.dark_mode_outlined,
                      title: 'Temă',
                      subtitle: 'Aspect vizual al aplicației',
                      options: const ['Dark', 'Light', 'System'],
                      values: const ['dark', 'light', 'system'],
                      selected: AppSettings.theme,
                      onChanged: (v) {
                        setState(() => AppSettings.applyTheme(v));
                        widget.onSettingsChanged?.call();
                      },
                    ),

                    const SizedBox(height: 20),

                    _SectionLabel(label: 'VOCE & LIMBĂ'),
                    const SizedBox(height: 10),
                    _SegmentedSetting(
                      icon: Icons.language_outlined,
                      title: 'Limbă Recunoaștere',
                      subtitle: 'Limba în care vorbești cu Rigby',
                      options: const ['🇷🇴 RO', '🇺🇸 EN', '🇫🇷 FR'],
                      values: const ['ro_RO', 'en_US', 'fr_FR'],
                      selected: AppSettings.sttLocale,
                      onChanged: (v) {
                        setState(() => AppSettings.sttLocale = v);
                        TtsService().applyLocale(v);
                        widget.onSettingsChanged?.call();
                      },
                    ),

                    const SizedBox(height: 12),

                    _SegmentedSetting(
                      icon: Icons.record_voice_over_outlined,
                      title: 'Tip Voce',
                      subtitle: 'Locală (gratis) sau ElevenLabs (premium)',
                      options: const ['Locală', 'ElevenLabs'],
                      values: const ['local', 'eleven'],
                      selected: AppSettings.useLocalTts ? 'local' : 'eleven',
                      onChanged: (v) {
                        final useLocal = v == 'local';
                        setState(() {
                          AppSettings.useLocalTts = useLocal;
                          TtsService.useLocal = useLocal;
                        });
                        widget.onSettingsChanged?.call();
                      },
                    ),

                    const SizedBox(height: 20),

                    _SectionLabel(label: 'PERSONALITATE AI'),
                    const SizedBox(height: 10),
                    _SegmentedSetting(
                      icon: Icons.psychology_outlined,
                      title: 'Mod Răspuns',
                      subtitle: 'Cum îți vorbește Rigby',
                      options: const ['Formal', 'Prietenos', 'Concis'],
                      values: const ['formal', 'prietenos', 'concis'],
                      selected: AppSettings.aiPersonality,
                      onChanged: (v) {
                        setState(() => AppSettings.aiPersonality = v);
                        widget.onSettingsChanged?.call();
                      },
                    ),

                    const SizedBox(height: 30),

                    _SectionLabel(label: 'DESPRE'),
                    const SizedBox(height: 10),
                    _InfoTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Rigby AI',
                      subtitle: 'v1.0.0 • Gemini 2.5 Flash + ElevenLabs',
                    ),
                    const SizedBox(height: 8),
                    _InfoTile(
                      icon: Icons.school_outlined,
                      title: 'Asistent Academic',
                      subtitle: 'Creat pentru studenți cu minte deschisă 🎓',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);
    return Text(
      label,
      style: TextStyle(
        color: fg.withValues(alpha: 0.30),
        fontSize: 9,
        letterSpacing: 2.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SegmentedSetting extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> options;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SegmentedSetting({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fg.withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: fg.withValues(alpha: 0.55)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: fg.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  Text(subtitle,
                      style: TextStyle(
                          color: fg.withValues(alpha: 0.35),
                          fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(options.length, (i) {
              final isSelected = values[i] == selected;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(values[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(right: i < options.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? fg.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: fg.withValues(alpha: isSelected ? 0.30 : 0.10),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      options[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg.withValues(alpha: isSelected ? 1.0 : 0.40),
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InfoTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = isDark ? AppColors.neonWhite : const Color(0xFF0D0D0D);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fg.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg.withValues(alpha: 0.40)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.72),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              Text(subtitle,
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.35),
                      fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}


