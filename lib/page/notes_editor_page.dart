import 'dart:async';
import 'dart:convert';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/editor/editor_popup.dart';
import 'package:atomic_notes/editor/note_image_viewer.dart';
import 'package:atomic_notes/editor/rich_selection_toolbar.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
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
  const NotesCreaterPage(
      {required this.note,
      this.onDelete,
      this.imageInput,
      this.speechInput,
      super.key});
  final VoidCallback? onDelete;
  final EditorImageInput? imageInput;
  final EditorSpeechInput? speechInput;
  final Note note;

  @override
  State<NotesCreaterPage> createState() => _NotesCreaterPageState();
}

class _NotesCreaterPageState extends State<NotesCreaterPage>
    with WidgetsBindingObserver {
  late final Note _draft;
  late final TextEditingController _title;
  late final NoteDocument _document;
  final _scroll = ScrollController();
  final _titleFocus = FocusNode();
  final List<RichNoteController> _lines = [];
  late final EditorImageInput _imageInput;
  late final EditorSpeechInput _speechInput;
  final Map<String, Uint8List> _images = {};
  bool _picking = false, _listening = false, _starting = false;
  bool _speechExplained = false, _applyingSpeech = false;
  int _speechSession = 0;
  RichNoteController? _speechTarget;
  String _speechBefore = "", _speechAfter = "", _speechExpected = "";
  TextSelection? _speechSelection;
  final List<FocusNode> _focus = [];
  int _activeLine = -1;
  bool _allowPop = false;
  bool _closing = false;
  bool _confirmingClose = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imageInput = widget.imageInput ?? PlatformEditorImageInput();
    _speechInput = widget.speechInput ?? PlatformEditorSpeechInput();
    _draft = Note.fromMap(widget.note.toMap());
    _title = TextEditingController(text: _draft.title);
    _document = NoteDocument.fromNote(_draft);
    _titleFocus.addListener(() {
      if (_titleFocus.hasFocus && (_listening || _starting)) _cancelSpeech();
    });
    for (final line in _document.lines) {
      _lines.add(_controller(line));
      _focus.add(_newLineFocus());
    }
    _activeLine = _focus.length - 1;
  }

  RichNoteController _controller(NoteLine line) {
    final controller = RichNoteController(text: line.text, styles: line.styles);
    controller.addListener(() {
      if (!mounted || _closing || _document.isReadOnly) return;
      final index = _lines.indexOf(controller);
      if (index < 0 || _document.lines[index].isImage) return;
      if ((_listening || _starting) &&
          !_applyingSpeech &&
          controller == _speechTarget &&
          (controller.text != _speechExpected ||
              controller.selection != _speechSelection)) {
        _cancelSpeech();
      }
      _document.replaceText(index, controller.text);
      _document.replaceStyles(index, controller.styles);
      setState(() {});
    });
    return controller;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission UI can temporarily make the window inactive before listening.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive && !_starting)) {
      _cancelSpeech();
    }
  }

  FocusNode _newLineFocus() {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus) {
        _activeLine = _focus.indexOf(node);
        if ((_listening || _starting) &&
            _activeLine >= 0 &&
            _lines[_activeLine] != _speechTarget) {
          _cancelSpeech();
        }
      }
    });
    return node;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speechSession++;
    unawaited(_speechInput.cancel());
    _title.dispose();
    _titleFocus.dispose();
    _scroll.dispose();
    for (final controller in _lines) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  Note _snapshot({bool removeEmptyLines = false}) {
    final result = _document.toNote(_draft, removeEmptyLines: removeEmptyLines);
    if (!_document.isReadOnly) result.title = _title.text;
    return result;
  }

  bool get _changed =>
      !_document.isReadOnly && _snapshot().contentSig != widget.note.contentSig;

  void _finish(bool save) {
    if (_closing || _picking || _starting) return;
    if (save) {
      if (_document.isReadOnly) return;
      final edited = _snapshot(removeEmptyLines: true);
      final error = NoteContentBudget.errorFor(edited);
      if (error != null) {
        _message(
            '$error. Shorten the note or remove an image; your draft is still here.');
        return;
      }
      // Leave sync versions, dirty state and timestamps to the repository.
      widget.note
        ..title = edited.title
        ..body = edited.body
        ..kind = edited.kind
        ..items = edited.items
        ..pinned = edited.pinned;
      widget.note.important = edited.important;
    }
    _closing = true;
    _cancelSpeech();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(save);
    });
  }

  Future<void> _requestClose() async {
    if (_closing || _confirmingClose || _picking || _starting) return;
    _cancelSpeech();
    if (!_changed) {
      _finish(false);
      return;
    }
    _confirmingClose = true;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => EditorPopup(
        title: 'Save your changes?',
        content: const Text('Choose Save to keep this draft, or keep editing.'),
        actions: [
          EditorPopupButton(
            label: 'Keep editing',
            onPressed: () => Navigator.pop(context, 'keep'),
          ),
          EditorPopupButton(
            label: 'Discard',
            tone: EditorPopupActionTone.destructive,
            onPressed: () => Navigator.pop(context, 'discard'),
          ),
          EditorPopupButton(
            label: 'Save',
            tone: EditorPopupActionTone.primary,
            onPressed: () => Navigator.pop(context, 'save'),
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
    if (_document.isReadOnly) return;
    _cancelSpeech();
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
      _lines.insert(inserted, _controller(_document.lines[inserted]));
      _activeLine = inserted;
      _focus.insert(inserted, node);
      if (_document.lines.length == priorCount + 2) {
        _lines.insert(inserted + 1, _controller(_document.lines[inserted + 1]));
        _focus.insert(inserted + 1, _newLineFocus());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.contains(node)) node.requestFocus();
    });
  }

  void _removeLine(int index) {
    if (_document.isReadOnly) return;
    _cancelSpeech();
    setState(() {
      _document.removeAt(index);
      _lines.removeAt(index).dispose();
      _focus.removeAt(index).dispose();
      if (index < _activeLine) _activeLine--;
      _activeLine = _activeLine.clamp(-1, _lines.length - 1);
    });
  }

  Future<void> _copy() async {
    final snapshot = _snapshot();
    final body = snapshot.kind == NoteKind.todo && !_document.isMixed
        ? snapshot.items
            .map((item) => '${item.done ? "[x]" : "[ ]"} ${item.text}')
            .join('\n')
        : _document.lines
            .map((line) => line.isImage
                ? "[Image]"
                : line.isChecklist
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
                          horizontal: AppSpace.sm,
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
                                  if (!compact)
                                    const MonoLabel('NOTES / EDITOR'),
                                  const EditorialHeading(
                                    'Edit note',
                                    style: AppType.headlineSm,
                                    maxLines: 1,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _document.isReadOnly
                                  ? null
                                  : () => setState(
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
                              onPressed: _document.isReadOnly
                                  ? null
                                  : () => setState(
                                        () => _draft.important =
                                            !_draft.important,
                                      ),
                              tooltip: _draft.important
                                  ? 'Unmark important'
                                  : 'Mark important',
                              isSelected: _draft.important,
                              color: AppColors.signal,
                              icon: const Icon(Icons.label_important_outline),
                              selectedIcon: const Icon(Icons.label_important),
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
                                  MonoLabel(
                                    _document.isReadOnly
                                        ? 'Unsupported format · read-only'
                                        : _changed
                                            ? 'SAVE WITH DONE'
                                            : widget.note.isEmpty
                                                ? 'UNSAVED DRAFT'
                                                : 'ON DEVICE',
                                    small: true,
                                    color: AppColors.signal,
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpace.md),
                              TextField(
                                key: const ValueKey('note-title'),
                                readOnly: _document.isReadOnly,
                                controller: _title,
                                focusNode: _titleFocus,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                maxLines: null,
                                style: AppType.displayLg.copyWith(
                                  fontSize: AppType.displayLg.fontSize! * 2 / 3,
                                ),
                                cursorColor: AppColors.signal,
                                decoration: _decoration('Title'),
                                onChanged: (_) => setState(() {}),
                              ),
                              _tags(),
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
                          horizontal: AppSpace.sm,
                          vertical: AppSpace.sm,
                        ),
                        child: Row(children: [
                          Expanded(
                              child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(children: [
                                    _round('Add text line', Icons.notes,
                                        () => _insertLine(checklist: false)),
                                    _round(
                                        'Add checklist line',
                                        Icons.checklist,
                                        () => _insertLine(checklist: true)),
                                    _round('Add image', Icons.image_outlined,
                                        _pickImage),
                                    _round(
                                        _listening
                                            ? 'Stop dictation'
                                            : 'Dictate text',
                                        _listening
                                            ? Icons.stop
                                            : Icons.mic_none,
                                        _dictate,
                                        active: _listening),
                                    _round('Delete note', Icons.delete_outline,
                                        _delete,
                                        destructive: true),
                                  ]))),
                          const SizedBox(width: 8),
                          FilledButton(
                              onPressed:
                                  _document.isReadOnly || _picking || _starting
                                      ? null
                                      : () => _finish(true),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.signal,
                                  foregroundColor: AppColors.paper,
                                  minimumSize: const Size(76, 48),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: AppRadius.std)),
                              child: const Text('Done')),
                        ]),
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
    if (line.isImage) {
      final data = line.imageBase64!;
      final bytes = _images.putIfAbsent(data, () => base64Decode(data));
      return Column(key: ObjectKey(_lines[index]), children: [
        Semantics(
          button: true,
          label: 'View note image',
          child: Tooltip(
            message: 'View note image',
            child: InkWell(
              onTap: () => _viewImage(bytes),
              borderRadius: AppRadius.std,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Image.memory(bytes,
                    height: 220,
                    fit: BoxFit.contain,
                    semanticLabel: 'Note image',
                    errorBuilder: (_, __, ___) =>
                        const Text('Image could not be displayed')),
              ),
            ),
          ),
        ),
        TextButton.icon(
            onPressed: () => _removeLine(index),
            icon: const Icon(Icons.close),
            label: const Text('Remove image')),
      ]);
    }
    if (!line.isChecklist) {
      return TextField(
        key: ValueKey(index == 0 ? 'note-body' : 'note-text-$index'),
        readOnly: _document.isReadOnly,
        contextMenuBuilder: (context, state) => _selectionMenu(state, index),
        controller: _lines[index],
        focusNode: _focus[index],
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        maxLines: null,
        minLines: _document.lines.length == 1 ? 5 : null,
        style: AppType.bodyLg,
        cursorColor: AppColors.signal,
        decoration: _decoration('Start writing…'),
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
            readOnly: _document.isReadOnly,
            contextMenuBuilder: (context, state) =>
                _selectionMenu(state, index),
            controller: _lines[index],
            focusNode: _focus[index],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            maxLines: null,
            onSubmitted: (_) => _insertLine(checklist: true, after: index),
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

  Future<void> _viewImage(Uint8List bytes) async {
    _cancelSpeech();
    // Unfocus the text node itself: unfocusing its route scope only clears
    // the parent scope, leaving a remembered text focus to reopen the keyboard.
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      builder: (_) => NoteImageViewer(bytes: bytes),
    );
  }

  Widget _selectionMenu(EditableTextState state, int index) =>
      _document.isReadOnly
          ? AdaptiveTextSelectionToolbar.editableText(editableTextState: state)
          : RichSelectionToolbar(editable: state, controller: _lines[index]);

  void _message(String text) {
    if (mounted) MySnackBar(text: text, sec: 3000).showMySnackBar(context);
  }

  Widget _round(String tooltip, IconData icon, VoidCallback action,
          {bool destructive = false, bool active = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: IconButton.filled(
            onPressed:
                _document.isReadOnly || _picking || _starting ? null : action,
            tooltip: tooltip,
            style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: destructive
                    ? AppColors.error
                    : active
                        ? AppColors.signal
                        : AppColors.ink,
                foregroundColor: AppColors.paper),
            icon: Icon(icon)),
      );

  Widget _tags() => _document.isReadOnly
      ? const SizedBox.shrink()
      : Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final tag in _document.tags)
              InputChip(
                  label: Text('#$tag', style: AppType.labelMono),
                  deleteButtonTooltipMessage: 'Remove tag $tag',
                  onDeleted: () => setState(() => _document
                      .setTags(_document.tags.where((v) => v != tag).toList())),
                  side: const BorderSide(color: AppColors.ink),
                  backgroundColor: AppColors.paper,
                  shape: const StadiumBorder(),
                  materialTapTargetSize: MaterialTapTargetSize.padded),
            Tooltip(
                message: 'Add tag',
                child: TextButton.icon(
                    onPressed: _document.tags.length < 12 ? _addTag : null,
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tag'))),
          ],
        );

  Future<void> _addTag() async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
        context: context,
        builder: (context) => EditorPopup(
              title: 'Add tag',
              content: TextField(
                  key: const ValueKey('note-tag-input'),
                  controller: controller,
                  autofocus: true,
                  maxLength: 40,
                  maxLines: 1,
                  style: AppType.bodyLg,
                  cursorColor: AppColors.signal,
                  decoration: const InputDecoration(
                      hintText: 'For example, morning',
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.signal,
                              width: AppStroke.hairline))),
                  onSubmitted: (value) => Navigator.pop(context, value)),
              actions: [
                EditorPopupButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
                EditorPopupButton(
                  label: 'Add',
                  tone: EditorPopupActionTone.primary,
                  onPressed: () => Navigator.pop(context, controller.text),
                ),
              ],
            ));
    // Let the outgoing dialog release its field before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || tag == null) return;
    try {
      setState(() => _document.setTags(
          [..._document.tags, tag.trim().replaceFirst(RegExp(r'^#+'), '')]));
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _pickImage() async {
    if (_picking || _document.isReadOnly) return;
    if (_document.imageCount >= NoteDocument.maxImagesPerNote) {
      _message(NoteDocument.imageLimitMessage);
      return;
    }
    _cancelSpeech();
    final remaining = NoteContentBudget.maxImageBytes - _document.imageBytes;
    if (remaining <= 0) {
      _message('Image space is full. Remove an image first.');
      return;
    }
    setState(() => _picking = true);
    try {
      final maxBytes =
          remaining.clamp(1, PlatformEditorImageInput.maxImageBytes);
      final image = await _imageInput.pickJpeg(maxBytes: maxBytes);
      if (!mounted || image == null) return;
      if (_document.imageCount >= NoteDocument.maxImagesPerNote) {
        _message(NoteDocument.imageLimitMessage);
        return;
      }
      if (NoteImageContent.decode(image).length > maxBytes) {
        _message(
            'The image must fit under 24 KB and the remaining note image space. Your draft is still here.');
        return;
      }
      final candidate = NoteDocument.fromNote(_snapshot());
      final index = _activeLine.clamp(-1, candidate.lines.length - 1);
      candidate.insertImageAfter(index, image);
      final error = NoteContentBudget.errorFor(candidate.toNote(_snapshot()));
      if (error != null) {
        _message('$error. Shorten the note before adding this image.');
        return;
      }
      setState(() {
        final inserted = _document.insertImageAfter(index, image);
        _lines.insert(inserted, _controller(_document.lines[inserted]));
        _focus.insert(inserted, _newLineFocus());
        _activeLine = inserted;
      });
    } on EditorMediaException catch (error) {
      _message(error.message);
    } catch (_) {
      _message(
          'Could not add this image. Choose a smaller image; your draft is still here.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _cancelSpeech() {
    _speechSession++;
    _speechTarget = null;
    _speechSelection = null;
    unawaited(_speechInput.cancel());
    if (mounted && (_listening || _starting)) {
      setState(() {
        _listening = false;
        _starting = false;
      });
    }
  }

  Future<void> _dictate() async {
    if (_document.isReadOnly || _starting) return;
    if (_listening) {
      await _speechInput.stop();
      return;
    }
    if (!_speechExplained) {
      final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => EditorPopup(
                title: 'Dictate into your note',
                content: const Text(
                    'Your device speech service converts speech into text and may send audio to its provider. Atomic Notes does not save an audio recording. Microphone access is requested only when you start.'),
                actions: [
                  EditorPopupButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  EditorPopupButton(
                    label: 'Start dictation',
                    tone: EditorPopupActionTone.primary,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ));
      if (!mounted || accepted != true) return;
      _speechExplained = true;
    }
    if (_activeLine < 0 ||
        _activeLine >= _lines.length ||
        _document.lines[_activeLine].isImage) {
      _insertLine(checklist: false);
    }
    final controller = _lines[_activeLine];
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    _speechBefore = controller.text.substring(0, start);
    _speechAfter = controller.text.substring(end);
    _speechExpected = controller.text;
    _speechSelection = controller.selection;
    _speechTarget = controller;
    final session = ++_speechSession;
    var ended = false;
    var received = false;
    setState(() => _starting = true);
    try {
      final ready = await _speechInput.start(
        onResult: (words, finalResult) {
          if (!mounted ||
              _closing ||
              session != _speechSession ||
              _speechTarget != controller ||
              !_lines.contains(controller)) {
            return;
          }
          if (controller.text != _speechExpected) {
            _cancelSpeech();
            return;
          }
          if (words.trim().isEmpty) return;
          received = true;
          final prefix = _speechBefore.isNotEmpty &&
                  !RegExp(r'\s$').hasMatch(_speechBefore)
              ? ' '
              : '';
          final suffix = _speechAfter.isNotEmpty &&
                  !RegExp(r'^\s|^[.,!?;:]').hasMatch(_speechAfter)
              ? ' '
              : '';
          final inserted = '$prefix${words.trim()}$suffix';
          _speechExpected = '$_speechBefore$inserted$_speechAfter';
          _speechSelection = TextSelection.collapsed(
              offset: _speechBefore.length + inserted.length);
          _applyingSpeech = true;
          controller.value = TextEditingValue(
              text: _speechExpected, selection: _speechSelection!);
          _applyingSpeech = false;
        },
        onError: (message) {
          if (mounted && session == _speechSession) {
            _cancelSpeech();
            _message(message);
          }
        },
        onStopped: () {
          ended = true;
          if (mounted && session == _speechSession) {
            setState(() => _listening = false);
          }
        },
      );
      if (!mounted || session != _speechSession) {
        await _speechInput.cancel();
        return;
      }
      setState(() {
        _starting = false;
        _listening = ready && !ended;
      });
      if (!ready && !received && !ended) {
        _message(
            'Speech recognition is unavailable or microphone access was denied. You can keep typing.');
      }
    } catch (_) {
      if (mounted && session == _speechSession) {
        _cancelSpeech();
        _message('Could not start dictation. Your draft is still here.');
      }
    }
  }

  Future<void> _delete() async {
    _cancelSpeech();
    final saved = widget.onDelete != null;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => EditorPopup(
              title: saved ? 'Move note to Recycle Bin?' : 'Discard this note?',
              content: Text(saved
                  ? 'The saved note can be restored from the Recycle Bin. Unsaved changes will be discarded.'
                  : 'This unsaved draft will be discarded.'),
              actions: [
                EditorPopupButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context, false),
                ),
                EditorPopupButton(
                  label: saved ? 'Move to Recycle Bin' : 'Discard',
                  tone: EditorPopupActionTone.destructive,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ));
    if (!mounted || accepted != true) return;
    widget.onDelete?.call();
    _finish(false);
  }

  Widget _statistics() {
    final snapshot = _snapshot();
    final text = [
      snapshot.title,
      ..._document.lines
          .where((line) => !line.isImage)
          .map((line) => line.text),
    ].join(' ').trim();
    final words = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    return Wrap(
      spacing: AppSpace.lg,
      runSpacing: AppSpace.xs,
      children: [
        MonoLabel('$words WORDS', small: true),
        MonoLabel('${(words / 200).ceil().clamp(1, 9999)} MIN READ',
            small: true),
        if (_listening || _starting)
          const MonoLabel('LISTENING…', small: true, color: AppColors.signal),
        if (snapshot.kind == NoteKind.todo || _document.hasChecklist)
          MonoLabel(
            '${_document.lines.where((line) => line.isChecklist && line.text.trim().isNotEmpty && line.done).length} / ${_document.lines.where((line) => line.isChecklist && line.text.trim().isNotEmpty).length} DONE',
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
