import 'package:flutter/material.dart';

import 'mock.dart';
import 'theme.dart';

class ReqallMark extends StatelessWidget {
  const ReqallMark({super.key, this.size = 52, this.radius = 10, this.glow = false});

  final double size;
  final double radius;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Rq.border),
        boxShadow: [
          const BoxShadow(color: Color(0x4D000000), blurRadius: 4, offset: Offset(0, 1)),
          if (glow) BoxShadow(color: Rq.accent.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: 1),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset('assets/reqall-mark.png', fit: BoxFit.cover),
    );
  }
}

/// The "re<span>qall</span>" wordmark from the panel hero.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    final style = Rq.mono(size: size, weight: FontWeight.w700).copyWith(letterSpacing: -0.03 * size);
    return Text.rich(TextSpan(style: style, children: [
      const TextSpan(text: 're'),
      TextSpan(text: 'qall', style: style.copyWith(color: Rq.accent)),
    ]));
  }
}

class KindBadge extends StatelessWidget {
  const KindBadge(this.kind, {super.key, this.size = 30});

  final Kind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kind.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: kind.color.withValues(alpha: 0.35)),
      ),
      child: Icon(kind.icon, size: size * 0.55, color: kind.color),
    );
  }
}

class KindChip extends StatelessWidget {
  const KindChip(this.kind, {super.key, this.selected = false, this.onTap});

  final Kind kind;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? kind.color.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? kind.color : Rq.border),
        ),
        child: Text(kind.name, style: Rq.mono(size: 11, color: selected ? kind.color : Rq.textSoft)),
      ),
    );
  }
}

/// The omarchy panel's Remember form: project picker, title, body, kind.
/// Concepts present it in their own chrome (sheet, overlay, inline).
class RememberForm extends StatefulWidget {
  const RememberForm({super.key, this.onSaved, this.dense = false});

  final ValueChanged<String>? onSaved;
  final bool dense;

  @override
  State<RememberForm> createState() => _RememberFormState();
}

class _RememberFormState extends State<RememberForm> {
  Project project = projects.first;
  Kind? kind;
  final title = TextEditingController();
  final body = TextEditingController();
  String? status;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: Rq.body(color: Rq.muted),
        filled: true,
        fillColor: Rq.bgDeep.withValues(alpha: 0.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Rq.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Rq.accent)),
      );

  void _save() {
    if (title.text.trim().isEmpty) {
      setState(() => status = 'Give it a title');
      return;
    }
    widget.onSaved?.call(title.text.trim());
    setState(() {
      status = 'Remembered in ${shortProject(project.name)}';
      title.clear();
      body.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: widget.dense ? 8 : 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<Project>(
          initialValue: project,
          isExpanded: true,
          dropdownColor: Rq.surface,
          decoration: _decoration('Project'),
          style: Rq.mono(size: 13),
          items: [
            for (final p in projects) DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (p) => setState(() => project = p ?? project),
        ),
        gap,
        TextField(controller: title, style: Rq.body(), decoration: _decoration('Title'), onSubmitted: (_) => _save()),
        gap,
        TextField(controller: body, style: Rq.body(), decoration: _decoration('Body (optional)'), minLines: 2, maxLines: 5),
        gap,
        Wrap(spacing: 6, runSpacing: 6, children: [
          GestureDetector(
            onTap: () => setState(() => kind = null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kind == null ? Rq.accent.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kind == null ? Rq.accent : Rq.border),
              ),
              child: Text('auto', style: Rq.mono(size: 11, color: kind == null ? Rq.accent : Rq.textSoft)),
            ),
          ),
          for (final k in Kind.values) KindChip(k, selected: kind == k, onTap: () => setState(() => kind = k)),
        ]),
        gap,
        Row(children: [
          Expanded(
            child: Text(status ?? 'Ctrl+Enter to save', style: Rq.mono(size: 11, color: Rq.muted)),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('Remember'),
            style: FilledButton.styleFrom(backgroundColor: Rq.accent, foregroundColor: Rq.bg),
          ),
        ]),
      ],
    );
  }
}

/// A small floating "← concepts" chip so each concept can get back to the picker.
class ConceptsButton extends StatelessWidget {
  const ConceptsButton({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Rq.bgDeep.withValues(alpha: 0.8),
      shape: const StadiumBorder(side: BorderSide(color: Rq.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.grid_view_rounded, size: 14, color: Rq.accent),
            const SizedBox(width: 6),
            Text(label ?? 'concepts', style: Rq.mono(size: 11, color: Rq.textSoft)),
          ]),
        ),
      ),
    );
  }
}
