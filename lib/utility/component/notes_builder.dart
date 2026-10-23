import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:flutter/material.dart';

/// A note card. Renders either a text note or a checklist, and doubles as the
/// selection target in multi-select mode.
///
/// Long-press enters selection; the Slidable swipe-to-delete it used to carry
/// is gone, replaced by multi-select, which handles one note and twenty the
/// same way.
class NotesBulder extends StatelessWidget {
  final Note note;
  final bool selected;
  final bool selectionMode;
  final bool featured;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Ticking a checklist row straight from the card.
  final void Function(int index) onToggleItem;

  Color get _accent =>
      note.important ? AppColors.importantTitle : AppColors.signal;
  Color get _bodyColor =>
      note.important ? AppColors.onImportantSurface : AppColors.onSurface;
  Color get _metadataColor =>
      note.important ? AppColors.onImportantSurface : AppColors.slateData;

  const NotesBulder({
    required this.note,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleItem,
    this.featured = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bool untitled = note.title.trim().isEmpty;
    final document = NoteDocument.fromNote(note);
    final mixedChecklist = note.kind == NoteKind.text &&
        (document.hasChecklist || NoteDocument.hasRichContent(note));
    final tasks = document.lines.where((line) => line.isChecklist).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md - 2),
          decoration: BoxDecoration(
            color: note.important
                ? AppColors.importantSurface
                : AppColors.surfaceLowest,
            borderRadius: AppRadius.std,
            border: Border.all(
              color: selected
                  ? _accent
                  : note.important
                      ? AppColors.importantOutline
                      : featured
                          ? AppColors.ink
                          : AppColors.outlineVariant,
              width: selected ? AppStroke.offset : AppStroke.rule,
            ),
            boxShadow: featured
                ? const [
                    BoxShadow(color: AppColors.signal, offset: Offset(4, 4)),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MonoLabel(_dateLabel(note.updatedAt),
                        small: true, color: _metadataColor),
                  ),
                  if (note.important)
                    Icon(Icons.label_important,
                        size: 16,
                        color: _accent,
                        semanticLabel: 'Important note'),
                  if (note.pinned)
                    Icon(
                      Icons.push_pin,
                      size: 16,
                      color: _accent,
                      semanticLabel: 'Pinned',
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: EditorialHeading(
                      untitled ? 'Untitled' : note.title,
                      style:
                          (featured ? AppType.headlineMd : AppType.headlineSm)
                              .copyWith(
                        color: note.important
                            ? AppColors.importantTitle
                            : untitled
                                ? AppColors.outline
                                : AppColors.ink,
                      ),
                      maxLines: 2,
                    ),
                  ),
                  if (selectionMode) ...[
                    const SizedBox(width: AppSpace.sm),
                    _Tick(on: selected, important: note.important),
                  ],
                ],
              ),
              if (mixedChecklist)
                _mixedContent(document)
              else if (note.kind == NoteKind.todo)
                _checklist()
              else if (note.body.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs + 2),
                Text(
                  note.body,
                  maxLines: featured ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyMd.copyWith(color: _bodyColor),
                ),
              ],
              if ((note.kind == NoteKind.todo || mixedChecklist) &&
                  tasks.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                MonoLabel(
                  '${tasks.where((line) => line.done).length} / ${tasks.length} DONE',
                  small: true,
                  color: _accent,
                ),
              ],
              if (document.tags.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(document.tags.map((tag) => '#$tag').join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.labelMono.copyWith(color: _metadataColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _dateLabel(DateTime value) {
    final date = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final day = DateTime(date.year, date.month, date.day);
    String pad(int n) => n.toString().padLeft(2, '0');
    if (day == today) return 'TODAY ${pad(date.hour)}:${pad(date.minute)}';
    if (day == yesterday) return 'YESTERDAY';
    final stamp = '${pad(date.month)}-${pad(date.day)}';
    return date.year == now.year ? stamp : '${date.year}-$stamp';
  }

  Widget _mixedContent(NoteDocument document) {
    final lines = document.lines;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length && i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: lines[i].isImage
                  ? Row(children: [
                      Icon(Icons.image_outlined, size: 20, color: _bodyColor),
                      const SizedBox(width: AppSpace.sm),
                      Text('Image',
                          style: AppType.bodySm.copyWith(color: _bodyColor)),
                    ])
                  : lines[i].isChecklist
                      ? GestureDetector(
                          onTap: selectionMode ? null : () => onToggleItem(i),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _Tick(
                                    on: lines[i].done,
                                    small: true,
                                    important: note.important),
                                const SizedBox(width: AppSpace.sm),
                                Expanded(
                                    child: Text(lines[i].text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppType.bodySm.copyWith(
                                            color: _bodyColor,
                                            decoration: lines[i].done
                                                ? TextDecoration.lineThrough
                                                : null))),
                              ]))
                      : Text(lines[i].text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.bodyMd.copyWith(color: _bodyColor)),
            ),
          if (lines.length > 4)
            MonoLabel('+${lines.length - 4} MORE',
                small: true, color: _metadataColor),
        ],
      ),
    );
  }

  Widget _checklist() {
    final rows = note.items.take(4).toList();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                // In selection mode the whole card is the target, so don't
                // let a tick steal the tap.
                onTap: selectionMode ? null : () => onToggleItem(i),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Tick(
                        on: rows[i].done,
                        small: true,
                        important: note.important),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        rows[i].text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodySm.copyWith(
                          decoration:
                              rows[i].done ? TextDecoration.lineThrough : null,
                          color: note.important
                              ? AppColors.onImportantSurface
                              : rows[i].done
                                  ? AppColors.outline
                                  : AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (note.items.length > rows.length)
            MonoLabel('+${note.items.length - rows.length} MORE',
                small: true, color: _metadataColor),
        ],
      ),
    );
  }
}

/// Square checkbox — the design system calls for 0-radius controls, and a
/// solid Signal block for the checked state.
class _Tick extends StatelessWidget {
  final bool on;
  final bool small;
  final bool important;
  const _Tick({required this.on, this.small = false, this.important = false});

  @override
  Widget build(BuildContext context) {
    final s = small ? 14.0 : 18.0;
    return Container(
      height: s,
      width: s,
      decoration: BoxDecoration(
        color: on
            ? (important ? AppColors.importantTitle : AppColors.signal)
            : Colors.transparent,
        border: Border.all(
          color: important
              ? AppColors.importantOutline
              : on
                  ? AppColors.signal
                  : AppColors.outline,
          width: AppStroke.rule,
        ),
      ),
      child: on
          ? Icon(Icons.check,
              size: s - 4,
              color: important ? AppColors.importantSurface : Colors.white)
          : null,
    );
  }
}
