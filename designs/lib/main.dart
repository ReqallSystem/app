import 'package:flutter/material.dart';

import 'concepts/console.dart';
import 'concepts/constellation.dart';
import 'concepts/hearth.dart';
import 'concepts/stream.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';

void main() {
  runApp(const ReqallApp());
}

class Concept {
  const Concept(this.route, this.name, this.tagline, this.icon, this.colors, this.builder);
  final String route;
  final String name;
  final String tagline;
  final IconData icon;
  final List<Color> colors;
  final WidgetBuilder builder;
}

final concepts = <Concept>[
  Concept('/hearth', 'Hearth', 'The omarchy panel, warmed up: glowing hero, live counters, Remember sheet.',
      Icons.local_fire_department_outlined, const [Color(0xFF4A2A2A), Color(0xFF2B1D1D)], (_) => const HearthConcept()),
  Concept('/constellation', 'Constellation', 'Your memory as a star map: projects are suns, records orbit, links glow.',
      Icons.auto_awesome_outlined, const [Color(0xFF1A1426), Color(0xFF2B1D1D)], (_) => const ConstellationConcept()),
  Concept('/stream', 'Stream', 'A river of memories through time, with a capture bar that floats above it.',
      Icons.waves_outlined, const [Color(0xFF2B1D1D), Color(0xFF3A2620)], (_) => const StreamConcept()),
  Concept('/console', 'Console', 'Keyboard-first and TUI-flavoured: j/k, a command palette, omarchy at heart.',
      Icons.terminal_outlined, const [Color(0xFF141010), Color(0xFF231818)], (_) => const ConsoleConcept()),
];

class ReqallApp extends StatelessWidget {
  const ReqallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reqall',
      debugShowCheckedModeBanner: false,
      theme: Rq.theme(),
      initialRoute: '/',
      routes: {
        '/': (_) => const ConceptPicker(),
        for (final c in concepts) c.route: c.builder,
      },
    );
  }
}

class ConceptPicker extends StatelessWidget {
  const ConceptPicker({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-0.6, -1), radius: 1.4, colors: [Color(0xFF3D2828), Rq.bg]),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
                children: [
                  Row(children: [
                    const ReqallMark(size: 44, glow: true),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Wordmark(size: 24),
                      Text('UI concept workshop', style: Rq.mono(size: 12, color: Rq.accent)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    'Four directions for the Flutter app, all on the same mock account. Open one and poke at it.',
                    style: Rq.body(color: Rq.textSoft),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(builder: (context, box) {
                    final columns = box.maxWidth > 640 ? 2 : 1;
                    final width = (box.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(spacing: 16, runSpacing: 16, children: [
                      for (var i = 0; i < concepts.length; i++)
                        SizedBox(width: width, child: _ConceptCard(index: i + 1, concept: concepts[i])),
                    ]);
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConceptCard extends StatefulWidget {
  const _ConceptCard({required this.index, required this.concept});
  final int index;
  final Concept concept;

  @override
  State<_ConceptCard> createState() => _ConceptCardState();
}

class _ConceptCardState extends State<_ConceptCard> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.concept;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pushNamed(c.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 180,
          padding: const EdgeInsets.all(20),
          transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c.colors),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hover ? Rq.accent : Rq.border),
            boxShadow: [
              if (hover) BoxShadow(color: Rq.accent.withValues(alpha: 0.2), blurRadius: 28),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(c.icon, color: Rq.accent, size: 28),
              const Spacer(),
              Text('0${widget.index}', style: Rq.mono(size: 13, color: Rq.muted)),
            ]),
            const Spacer(),
            Text(c.name, style: Rq.display(size: 26)),
            const SizedBox(height: 6),
            Text(c.tagline, style: Rq.body(size: 13, color: Rq.textSoft), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
