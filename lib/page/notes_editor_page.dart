import 'package:atomic_notes/database/note.dart';
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
  late final TextEditingController _body;
  final _scroll = ScrollController();
  final List<TextEditingController> _items = [];
  final List<FocusNode> _focus = [];
  bool _allowPop = false;
  bool _closing = false;

  bool get _isTodo => _draft.kind == NoteKind.todo;

  @override
  void initState() {
    super.initState();
    _draft = Note.fromMap(widget.note.toMap());
    _title = TextEditingController(text: _draft.title);
    _body = TextEditingController(text: _draft.body);
    for (final item in _draft.items) {
      _items.add(TextEditingController(text: item.text));
      _focus.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _scroll.dispose();
    for (final controller in _items) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  // Snapshot without mutating the list backing the live text fields. Copying
  // a checklist with blank rows must not misalign its controllers.
  Note _snapshot() {
    final result = Note.fromMap(_draft.toMap());
    result.title = _title.text;
    result.body = _isTodo ? '' : _body.text;
    result.items = _isTodo
        ? [
            for (var i = 0; i < _items.length; i++)
              if (_items[i].text.trim().isNotEmpty)
                TodoItem(text: _items[i].text, done: _draft.items[i].done),
          ]
        : [];
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
    if (_closing) return;
    if (!_changed) {
      _finish(false);
      return;
    }
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
    if (!mounted) return;
    if (action == 'save') _finish(true);
    if (action == 'discard') _finish(false);
  }

  void _switchKind() {
    FocusScope.of(context).unfocus();
    setState(() {
      if (_isTodo) {
        // Always use the live fields, never an earlier copy of the text body.
        _body.text = _items.map((item) => item.text).join('\n');
        _draft.kind = NoteKind.text;
      } else {
        final lines = _body.text.split('\n');
        final prior = [
          for (var i = 0; i < _items.length; i++)
            TodoItem(text: _items[i].text, done: _draft.items[i].done),
        ];
        for (final controller in _items) {
          controller.dispose();
        }
        for (final node in _focus) {
          node.dispose();
        }
        _items.clear();
        _focus.clear();
        _draft.items = [
          for (var i = 0; i < lines.length; i++)
            TodoItem(
              text: lines[i],
              done:
                  i < prior.length &&
                  prior[i].text == lines[i] &&
                  prior[i].done,
            ),
        ];
        for (final item in _draft.items) {
          _items.add(TextEditingController(text: item.text));
          _focus.add(FocusNode());
        }
        _draft.kind = NoteKind.todo;
      }
    });
  }

  void _addItem({int? after}) {
    final node = FocusNode();
    setState(() {
      final index = after == null ? _items.length : after + 1;
      _draft.items.insert(index, TodoItem(text: ''));
      _items.insert(index, TextEditingController());
      _focus.insert(index, node);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.contains(node)) node.requestFocus();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _draft.items.removeAt(index);
      _items.removeAt(index).dispose();
      _focus.removeAt(index).dispose();
    });
  }

  Future<void> _copy() async {
    final snapshot = _snapshot();
    final body = _isTodo
        ? snapshot.items
              .map((item) => '${item.done ? "[x]" : "[ ]"} ${item.text}')
              .join('\n')
        : snapshot.body;
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
                              tooltip: _draft.pinned
                                  ? 'Unpin note'
                                  : 'Pin note',
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
                              if (_isTodo) ...[
                                for (var i = 0; i < _items.length; i++)
                                  _itemRow(i),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _addItem,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add item'),
                                  ),
                                ),
                              ] else
                                TextField(
                                  key: const ValueKey('note-body'),
                                  controller: _body,
                                  keyboardType: TextInputType.multiline,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  maxLines: null,
                                  minLines: 5,
                                  style: AppType.bodyLg,
                                  cursorColor: AppColors.signal,
                                  decoration: _decoration('Start writing…'),
                                  onChanged: (_) => setState(() {}),
                                ),
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
                              onPressed: _switchKind,
                              tooltip: _isTodo
                                  ? 'Switch to text'
                                  : 'Switch to checklist',
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.ink,
                                foregroundColor: AppColors.paper,
                              ),
                              icon: Icon(
                                _isTodo ? Icons.notes : Icons.checklist,
                              ),
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

  Widget _itemRow(int index) {
    return Row(
      key: ObjectKey(_items[index]),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _draft.items[index].done,
          activeColor: AppColors.signal,
          semanticLabel: 'Complete item ${index + 1}',
          onChanged: (value) =>
              setState(() => _draft.items[index].done = value!),
        ),
        Expanded(
          child: TextField(
            key: ValueKey('note-item-$index'),
            controller: _items[index],
            focusNode: _focus[index],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: null,
            onSubmitted: (_) => _addItem(after: index),
            onChanged: (_) => setState(() {}),
            style: AppType.bodyMd.copyWith(
              decoration: _draft.items[index].done
                  ? TextDecoration.lineThrough
                  : null,
            ),
            decoration: _decoration('List item'),
          ),
        ),
        IconButton(
          onPressed: () => _removeItem(index),
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
      snapshot.body,
      ...snapshot.items.map((item) => item.text),
    ].join(' ').trim();
    final words = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    return Wrap(
      spacing: AppSpace.lg,
      runSpacing: AppSpace.xs,
      children: [
        MonoLabel('$words WORDS', small: true),
        if (_isTodo)
          MonoLabel(
            '${snapshot.doneCount} / ${snapshot.items.length} DONE',
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
