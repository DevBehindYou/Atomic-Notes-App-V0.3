import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:atomic_notes/theme/editorial.dart';
import 'package:atomic_notes/utility/component/my_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An isolated draft. Only Done copies editable fields back to the caller,
/// which persists the note through its existing Bloc/repository save path.
class NotesCreaterPage extends StatefulWidget {
  const NotesCreaterPage({required this.note, super.key});
  final Note note;

  @override
  State<NotesCreaterPage> createState() => _NotesCreaterPageState();
}

class _NotesCreaterPageState extends State<NotesCreaterPage> {
  late final Note _draft;
  late final TextEditingController _title;
  late final NoteDocument _document;
  final _scroll = ScrollController();
  final List<TextEditingController> _lines = [];
  final List<FocusNode> _focus = [];
  int _activeLine = -1;
  bool _allowPop = false;
  bool _closing = false;
  bool _confirmingClose = false;

  @override
  void initState() {
    super.initState();
    _draft = Note.fromMap(widget.note.toMap());
    _title = TextEditingController(text: _draft.title);
    _document = NoteDocument.fromNote(_draft);
    for (final line in _document.lines) {
      _lines.add(TextEditingController(text: line.text));
      _focus.add(_newLineFocus());
    }
    _activeLine = _focus.length - 1;
  }

  FocusNode _newLineFocus() {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) _activeLine = _focus.indexOf(node);
    });
    return node;
  }

  @override
  void dispose() {
    _title.dispose();
    _scroll.dispose();
    for (final controller in _lines) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  Note _snapshot() {
    final result = _document.toNote(_draft);
    result.title = _title.text;
    return result;
  }

  bool get _changed => _snapshot().contentSig != widget.note.contentSig;

  void _finish(bool save) {
    if (_closing) return;
    _closing = true;
    if (save) {
      final edited = _snapshot();
      // Leave sync versions, dirty state and timestamps to the repository.
      widget.note
        ..title = edited.title
        ..body = edited.body
        ..kind = edited.kind
        ..items = edited.items
        ..pinned = edited.pinned;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(save);
    });
  }

  Future<void> _requestClose() async {
    if (_closing || _confirmingClose) return;
    if (!_changed) {
      _finish(false);
      return;
    }
    _confirmingClose = true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save your changes?'),
        content: const Text('Choose Save to keep this draft, or keep editing.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    _confirmingClose = false;
    if (!mounted) return;
    if (action == 'save') _finish(true);
    if (action == 'discard') _finish(false);
  }

  void _insertLine({required bool checklist, int? after}) {
    final active = after ?? _activeLine;
    final index = active.clamp(-1, _document.lines.length - 1);
    final selection = index < 0 ? null : _lines[index].selection;
    final caret =
        selection != null && selection.isValid ? selection.extentOffset : null;
    final node = _newLineFocus();
    late final int inserted;
    setState(() {
      final priorCount = _lines.length;
      inserted = checklist
          ? _document.insertChecklistAfter(index, caretOffset: caret)
          : _document.insertTextAfter(index, caretOffset: caret);
      if (index >= 0 && _lines[index].text != _document.lines[index].text) {
        _lines[index].text = _document.lines[index].text;
      }
      _lines.insert(inserted, TextEditingController());
      _focus.insert(inserted, node);
      if (_document.lines.length == priorCount + 2) {
        _lines.insert(inserted + 1,
            TextEditingController(text: _document.lines[inserted + 1].text));
        _focus.insert(inserted + 1, _newLineFocus());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.contains(node)) node.requestFocus();
    });
  }

  void _removeLine(int index) {
    setState(() {
      _document.removeAt(index);
      _lines.removeAt(index).dispose();
      _focus.removeAt(index).dispose();
    });
  }

  Future<void> _copy() async {
    final snapshot = _snapshot();
    final body = snapshot.kind == NoteKind.todo && !_document.isMixed
        ? snapshot.items
            .map((item) => '${item.done ? "[x]" : "[ ]"} ${item.text}')
            .join('\n')
        : _document.lines
            .map((line) => line.isChecklist
                ? '${line.done ? "- [x]" : "- [ ]"} ${line.text}'
                : line.text)
            .join('\n');
    try {
      await Clipboard.setData(
        ClipboardData(
          text: snapshot.title.trim().isEmpty
              ? body
              : '${snapshot.title}\n\n$body',
        ),
      );
      if (!mounted) return;
      const MySnackBar(
        text: 'Copied to clipboard',
        sec: 1200,
      ).showMySnackBar(context);
    } on PlatformException {
      if (!mounted) return;
      const MySnackBar(
        text: 'Could not copy. Your draft is still here.',
        sec: 2000,
      ).showMySnackBar(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 400;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                          vertical: AppSpace.sm,
                        ),
                        child: Row(
                          children: [
                            IconButton.filled(
                              onPressed: _requestClose,
                              tooltip: 'Back to notes',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.ink,
                                foregroundColor: AppColors.paper,
                              ),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!compact) const MonoLabel('NOTES'),
                                  const EditorialHeading(
                                    'Edit note',
                                    style: AppType.headlineMd,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(
                                () => _draft.pinned = !_draft.pinned,
                              ),
                              tooltip:
                                  _draft.pinned ? 'Unpin note' : 'Pin note',
                              isSelected: _draft.pinned,
                              color: AppColors.signal,
                              icon: const Icon(Icons.push_pin_outlined),
                              selectedIcon: const Icon(Icons.push_pin),
                            ),
                            IconButton(
                              onPressed: _copy,
                              tooltip: 'Copy note',
                              icon: const Icon(Icons.copy_outlined),
                            ),
                          ],
                        ),
                      ),
                      const HairRule(color: AppColors.ink),
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.all(
                              AppSpace.screenMargin,
                            ),
                            children: [
                              Wrap(
                                spacing: AppSpace.md,
                                runSpacing: AppSpace.xs,
                                children: [
                                  MonoLabel(
                                    'EDITED ${_stamp(widget.note.updatedAt)}',
                                    small: true,
                                  ),
                                  const MonoLabel(
                                    'SAVE WITH DONE',
                                    small: true,
                                    color: AppColors.signal,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpace.md),
                              TextField(
                                key: const ValueKey('note-title'),
                                controller: _title,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: null,
                                style: AppType.displayLg,
                                cursorColor: AppColors.signal,
                                decoration: _decoration('Title'),
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: AppSpace.md),
                              for (var i = 0; i < _document.lines.length; i++)
                                _lineRow(i),
                            ],
                          ),
                        ),
                      ),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.screenMargin,
                            vertical: AppSpace.sm,
                          ),
                          child: _statistics(),
                        ),
                      const HairRule(color: AppColors.ink),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                          vertical: AppSpace.sm,
                        ),
                        child: Row(
                          children: [
                            IconButton.filled(
                              onPressed: () => _insertLine(checklist: false),
                              tooltip: 'Add text line',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.ink,
                                foregroundColor: AppColors.paper,
                              ),
                              icon: const Icon(Icons.notes),
                            ),
                            const SizedBox(width: AppSpace.xs),
                            IconButton.filled(
                              onPressed: () => _insertLine(checklist: true),
                              tooltip: 'Add checklist line',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.ink,
                                foregroundColor: AppColors.paper,
                              ),
                              icon: const Icon(Icons.checklist),
                            ),
                            const Spacer(),
                            DecoratedBox(
                              decoration: const BoxDecoration(
                                borderRadius: AppRadius.std,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.ink,
                                    offset: Offset(3, 3),
                                  ),
                                ],
                              ),
                              child: FilledButton.icon(
                                onPressed: () => _finish(true),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.signal,
                                  foregroundColor: AppColors.paper,
                                  minimumSize: const Size(100, 48),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: AppRadius.std,
                                  ),
                                ),
                                icon: const Icon(Icons.check),
                                label: const Text('Done'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lineRow(int index) {
    final line = _document.lines[index];
    if (!line.isChecklist) {
      return TextField(
        key: ValueKey(index == 0 ? 'note-body' : 'note-text-$index'),
        controller: _lines[index],
        focusNode: _focus[index],
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        maxLines: null,
        minLines: _document.lines.length == 1 ? 5 : null,
        style: AppType.bodyLg,
        cursorColor: AppColors.signal,
        decoration: _decoration('Start writing…'),
        onChanged: (value) =>
            setState(() => _document.replaceText(index, value)),
      );
    }
    return Row(
      key: ObjectKey(_lines[index]),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: line.done,
          activeColor: AppColors.signal,
          semanticLabel: 'Complete item ${index + 1}',
          onChanged: (value) =>
              setState(() => _document.setDone(index, value!)),
        ),
        Expanded(
          child: TextField(
            key: ValueKey('note-item-$index'),
            controller: _lines[index],
            focusNode: _focus[index],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: null,
            onSubmitted: (_) => _insertLine(checklist: true, after: index),
            onChanged: (value) =>
                setState(() => _document.replaceText(index, value)),
            style: AppType.bodyMd.copyWith(
              decoration: line.done ? TextDecoration.lineThrough : null,
            ),
            decoration: _decoration('List item'),
          ),
        ),
        IconButton(
          onPressed: () => _removeLine(index),
          tooltip: 'Remove item ${index + 1}',
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }

  Widget _statistics() {
    final snapshot = _snapshot();
    final text = [
      snapshot.title,
      ..._document.lines.map((line) => line.text),
    ].join(' ').trim();
    final words = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    return Wrap(
      spacing: AppSpace.lg,
      runSpacing: AppSpace.xs,
      children: [
        MonoLabel('$words WORDS', small: true),
        if (snapshot.kind == NoteKind.todo || _document.hasChecklist)
          MonoLabel(
            '${_document.lines.where((line) => line.isChecklist && line.done).length} / ${_document.lines.where((line) => line.isChecklist).length} DONE',
            small: true,
            color: AppColors.signal,
          ),
      ],
    );
  }

  static InputDecoration _decoration(String hint) => InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: hint,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      );

  static String _stamp(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
  }
}
