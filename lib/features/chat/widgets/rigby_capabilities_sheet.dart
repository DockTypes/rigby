import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class _Capability {
  final IconData icon;
  final String title;
  final String description;
  final List<String> examples;
  const _Capability({
    required this.icon,
    required this.title,
    required this.description,
    this.examples = const [],
  });
}

class _CapabilityGroup {
  final String title;
  final List<_Capability> items;
  const _CapabilityGroup({required this.title, required this.items});
}

const List<_CapabilityGroup> _groups = [
  _CapabilityGroup(
    title: 'Voce',
    items: [
      _Capability(
        icon: Icons.mic_none_rounded,
        title: 'Activare prin voce',
        description:
            'Spune „Rigby" oricând (chiar și cu app-ul în background) și încep să te ascult.',
      ),
      _Capability(
        icon: Icons.record_voice_over_outlined,
        title: 'Două voci',
        description:
            'Voce locală gratuită sau ElevenLabs premium — schimbă din setări.',
      ),
    ],
  ),
  _CapabilityGroup(
    title: 'Orar FMI Ovidius',
    items: [
      _Capability(
        icon: Icons.today_rounded,
        title: 'Orar pe zile',
        description: 'Îți afișez orele filtrate pentru grupa ta, cu sală și profesor.',
        examples: ['Ce am azi?', 'Ce am mâine?', 'Ce am vineri?'],
      ),
      _Capability(
        icon: Icons.calendar_view_week_rounded,
        title: 'Orar săptămânal',
        description: 'Toată săptămâna sau filtrat pe pară/impară.',
        examples: ['Orarul săptămânii', 'Ce am în săptămâna pară?'],
      ),
    ],
  ),
  _CapabilityGroup(
    title: 'Universitate',
    items: [
      _Capability(
        icon: Icons.school_outlined,
        title: 'Burse, taxe, regulament',
        description:
            'Răspund pe baza documentelor oficiale FMI Ovidius (regulament, burse, taxe, sesiuni, Erasmus).',
        examples: [
          'Câte restanțe pot avea?',
          'Cât e bursa de performanță?',
          'Când e sesiunea de iarnă?',
        ],
      ),
    ],
  ),
  _CapabilityGroup(
    title: 'Productivitate',
    items: [
      _Capability(
        icon: Icons.timer_outlined,
        title: 'Cronometru / focus',
        description:
            'Pornesc un timer cu indicator persistent în Dynamic Island. Swipe pentru a-l închide.',
        examples: ['Pornește un timer de 50 de minute', 'Anulează timerul'],
      ),
      _Capability(
        icon: Icons.notifications_active_outlined,
        title: 'Memento-uri',
        description: 'Setez notificări locale pentru o oră anume.',
        examples: ['Amintește-mi mâine la 10 să predau proiectul'],
      ),
    ],
  ),
  _CapabilityGroup(
    title: 'Comenzi rapide',
    items: [
      _Capability(
        icon: Icons.access_time_rounded,
        title: 'Oră și dată',
        description: 'Răspuns instant, fără rețea.',
        examples: ['Cât e ora?', 'Ce dată e azi?'],
      ),
      _Capability(
        icon: Icons.flash_on_outlined,
        title: 'Conversație generală',
        description: 'Întreabă-mă orice — folosesc Gemini pentru răspunsuri naturale.',
      ),
    ],
  ),
  _CapabilityGroup(
    title: 'AI Vision',
    items: [
      _Capability(
        icon: Icons.camera_alt_outlined,
        title: 'Fotografiază și rezolvă',
        description:
            'Fă o poză la un exercițiu, ecuație, text sau cod — Rigby analizează imaginea și îți explică.',
        examples: ['Rigby, uită-te la asta', 'Analizează ce scrie aici'],
      ),
    ],
  ),
];


class RigbyCapabilitiesSheet extends StatefulWidget {
  const RigbyCapabilitiesSheet({super.key});

  @override
  State<RigbyCapabilitiesSheet> createState() => _RigbyCapabilitiesSheetState();
}

class _RigbyCapabilitiesSheetState extends State<RigbyCapabilitiesSheet>
    with SingleTickerProviderStateMixin {
  static const int _stagger = 50;
  static const int _itemDuration = 380;
  static const double _slideFrom = 18.0;

  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    int rows = 1;
    for (final g in _groups) {
      rows += 1 + g.items.length;
    }
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: rows * _stagger + _itemDuration),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    int idx = 0;
    final header = _animatedRow(
      idx++,
      _Header(onClose: () => Navigator.of(context).pop()),
    );

    final List<Widget> rows = [];
    for (final group in _groups) {
      rows.add(_animatedRow(idx++, _GroupTitle(title: group.title)));
      for (final cap in group.items) {
        rows.add(_animatedRow(
          idx++,
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CapabilityCard(cap: cap),
          ),
        ));
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 38, height: 4,
            decoration: BoxDecoration(
              color: AppColors.textMuted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          header,
          const Divider(height: 1, color: AppColors.borderSubtle),
          Flexible(
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 14, 20, mq.padding.bottom + 24),
              physics: const BouncingScrollPhysics(),
              children: rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _animatedRow(int index, Widget child) {
    final total = _ctrl.duration!.inMilliseconds;
    final start = (index * _stagger) / total;
    final end = ((index * _stagger) + _itemDuration) / total;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final raw = (_ctrl.value - start) / (end - start);
        final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * _slideFrom),
            child: child,
          ),
        );
      },
    );
  }
}


class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ce pot să fac',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Asistent vocal pentru studenți FMI Ovidius'.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppColors.textSecondary, size: 22),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String title;
  const _GroupTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 18, bottom: 12),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 0.5, color: AppColors.border)),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  final _Capability cap;
  const _CapabilityCard({required this.cap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.neonWhite.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.neonWhite.withValues(alpha: 0.10),
                width: 0.5,
              ),
            ),
            child: Icon(cap.icon, size: 18, color: AppColors.neonWhiteDim),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cap.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cap.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                    letterSpacing: 0.1,
                  ),
                ),
                if (cap.examples.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: cap.examples
                        .map((e) => _ExamplePill(text: e))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamplePill extends StatelessWidget {
  final String text;
  const _ExamplePill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        '„$text"',
        style: const TextStyle(
          color: AppColors.neonWhiteFaint,
          fontSize: 10.5,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}


Future<void> showRigbyCapabilitiesSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const RigbyCapabilitiesSheet(),
  );
}
