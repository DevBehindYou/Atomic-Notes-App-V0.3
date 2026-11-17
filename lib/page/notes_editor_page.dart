import 'dart:async';
import 'dart:convert';
import 'package:atomic_notes/editor/editor_media.dart';
import 'package:atomic_notes/editor/note_image_decode.dart';
import 'package:atomic_notes/editor/note_image_viewer.dart';
import 'package:atomic_notes/editor/rich_selection_toolbar.dart';
import 'package:atomic_notes/editor/rich_text_controller.dart';
import 'package:atomic_notes/database/note.dart';
import 'package:atomic_notes/database/note_document.dart';
import 'package:atomic_notes/database/note_word_limit.dart';
import 'package:atomic_notes/database/notes_source.dart';
import 'package:atomic_notes/state/notes/notes_bloc.dart';
import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:atomic_notes/ui/buttons/atomic_button.dart';
import 'package:atomic_notes/ui/buttons/atomic_icon_button.dart';
import 'package:atomic_notes/ui/chips/tag_chip.dart';
import 'package:atomic_notes/ui/controls/atomic_checkbox.dart';
import 'package:atomic_notes/ui/fields/atomic_text_field.dart';
import 'package:atomic_notes/ui/motion/atomic_pressable.dart';
import 'package:atomic_notes/ui/overlays/atomic_dialog.dart';
import 'package:atomic_notes/ui/overlays/atomic_sheet.dart';
import 'package:atomic_notes/ui/overlays/atomic_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An isolated draft. Only Done copies editable fields back to the caller,
/// which persists the note through its existing Bloc/repository save path.
///
/// With [onSave], the editor owns the save: Done hands a fresh copy of the
/// draft to [onSave] and stays open, with input locked, until that attempt's
/// result. It closes once, on success; on failure the draft stays editable
/// with Retry, Edit and Discard. Without it, Done copies the fields into
/// [note] and closes with `true` for the caller to save.
class NotesCreaterPage extends StatefulWidget {
  const NotesCreaterPage(
      {required this.note,
      this.onDelete,
      this.onSave,
      this.imageInput,
      this.speechInput,
      super.key});
  final VoidCallback? onDelete;
  final Future<NoteSaveResult> Function(Note note)? onSave;
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
  late final NoteWordLimit _wordLimit;
  final _scroll = ScrollController();
  final _titleFocus = FocusNode();
  final List<RichNoteController> _lines = [];
  final _contentRevision = ValueNotifier<int>(0);
  late final EditorImageInput _imageInput;
  late final EditorSpeechInput _speechInput;
  final Map<String, Uint8List> _images = {};
  // One size-bounded thumbnail provider per image, reused across builds.
  final Map<String, ResizeImage> _thumbnails = {};
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

  /// The draft's account or session changed before it was stored (review
  /// R14). Nothing of the draft is built from then on, even while another
  /// route covers this one and the close has to wait.
  bool _retired = false;

  /// The save attempt this editor is waiting for; a result for any other
  /// attempt is ignored.
  Object? _attempt;
  bool get _saving => _attempt != null;

  /// No edit may land while a save is pending or the editor is closing: the
  /// pending attempt is a snapshot, and success closes the editor.
  bool get _locked => _saving || _closing;
  bool _confirmingClose = false;
  bool _confirmingImageRemoval = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _imageInput = widget.imageInput ?? PlatformEditorImageInput();
    _speechInput = widget.speechInput ?? PlatformEditorSpeechInput();
    _draft = Note.fromMap(widget.note.toMap());
    _title = TextEditingController(text: _draft.title);
    _document = NoteDocument.fromNote(_draft);
    _wordLimit = NoteWordLimit(originalWords: _wordCount);
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
    var previousValue = controller.value;
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
      final nextValue = controller.value;
      final valueChanged = previousValue != nextValue;
      final textChanged = previousValue.text != nextValue.text;
      previousValue = nextValue;
      // Caret and IME range updates belong to EditableText. They must still
      // fence dictation above, but do not change the document or its metadata.
      // A style toggle notifies without changing TextEditingValue, so it must
      // continue through this path even when the text is unchanged.
      if (valueChanged && !textChanged) return;
      // Fields cannot take focus while locked; this guards programmatic edits.
      if (_locked) return;
      _document.replaceText(index, controller.text);
      _document.replaceStyles(index, controller.styles);
      _contentRevision.value++;
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
    _contentRevision.dispose();
    _titleFocus.dispose();
    _scroll.dispose();
    for (final controller in _lines) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    for (final bytes in _images.values) {
      _releaseImage(bytes);
    }
    _images.clear();
    for (final thumbnail in _thumbnails.values) {
      NoteImageDecode.release(thumbnail);
    }
    _thumbnails.clear();
    super.dispose();
  }

  void _releaseImage(Uint8List bytes) {
    // MemoryImage keys compare byte-buffer identity. Only release this draft's
    // keys; keep live listeners (including an open image viewer) attached.
    PaintingBinding.instance.imageCache
        .evict(MemoryImage(bytes), includeLive: false);
  }

  Note _snapshot({bool removeEmptyLines = false}) {
    final result = _document.toNote(_draft, removeEmptyLines: removeEmptyLines);
    if (!_document.isReadOnly) result.title = _title.text;
    return result;
  }

  // The document already compares its editable projection with the initial
  // lines/tags. Serializing and hashing the full note here would repeat that
  // work on every edit just to update a label or decide whether to prompt.
  bool get _changed =>
      !_document.isReadOnly &&
      (_document.hasChanges ||
          _title.text != widget.note.title ||
          _draft.pinned != widget.note.pinned ||
          _draft.important != widget.note.important);

  void _finish(bool save) {
    if (_closing || _saving || _picking || _starting) return;
    if (save) {
      if (_document.isReadOnly) return;
      final wordError = _wordLimit.errorFor(_wordCount);
      if (wordError != null) {
        _cancelSpeech();
        _message(wordError);
        return;
      }
      final edited = _snapshot(removeEmptyLines: true);
      final error = NoteContentBudget.errorFor(edited);
      if (error != null) {
        // A title error is about the title alone; the others are size limits
        // that shortening the note or removing an image can resolve.
        _message(error == NoteContentBudget.titleError
            ? '$error. Your draft is still here.'
            : '$error. Shorten the note or remove an image; your draft is still here.');
        return;
      }
      // Leave sync versions, dirty state and timestamps to the repository.
      // An owned save gets its own copy, so no attempt alters the draft.
      final target = widget.onSave == null ? widget.note : widget.note.copy();
      target
        ..title = edited.title
        ..body = edited.body
        ..kind = edited.kind
        ..items = edited.items
        ..pinned = edited.pinned;
      target.important = edited.important;
      if (widget.onSave != null) {
        unawaited(_submit(target));
        return;
      }
    }
    _close(save);
  }

  /// The route this editor runs in, and a result waiting for that route to
  /// be on top of its navigator again (review R11).
  ModalRoute<Object?>? _route;
  bool? _pendingResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    // Covering routes come and go; finish once this route is current again.
    if (_pendingResult != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeIfCurrent());
    }
  }

  void _close(bool save) {
    if (_closing) return;
    _closing = true;
    _cancelSpeech();
    _pendingResult = save;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _completeIfCurrent());
  }

  /// Pops this editor's own route with its result, only while that route is
  /// the top of its own navigator. A covered editor waits; a removed or
  /// replaced one has nothing left to complete. Never pops another route.
  void _completeIfCurrent() {
    final result = _pendingResult;
    final route = _route;
    if (result == null || !mounted || route == null) return;
    if (!route.isActive) {
      _pendingResult = null;
      return;
    }
    if (!route.isCurrent) return;
    _pendingResult = null;
    route.navigator?.pop(result);
  }

  /// Saves one snapshot through [NotesCreaterPage.onSave] and acts on that
  /// attempt's result only.
  Future<void> _submit(Note snapshot) async {
    final attempt = Object();
    _cancelSpeech();
    // Where to return the caret if the draft goes back to editing.
    final focusBefore = FocusManager.instance.primaryFocus;
    FocusScope.of(context).unfocus();
    setState(() => _attempt = attempt);
    NoteSaveResult result;
    try {
      result = await widget.onSave!(snapshot);
    } catch (error, stackTrace) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'atomic_notes editor',
          context: ErrorDescription('while saving a note')));
      result = NoteSaveFailed(error);
    }
    if (!mounted || !identical(_attempt, attempt)) return;
    setState(() {
      _attempt = null;
      if (result case NoteSaveRetired(reason: NoteSaveRetirement.contextChanged)) {
        _retired = true;
      }
    });
    switch (result) {
      case NoteSaveSucceeded():
        _close(true);
      case NoteSaveSkipped():
        _close(false);
      case NoteSaveRetired(reason: NoteSaveRetirement.contextChanged):
        // The account or session changed: this draft must not stay on screen
        // for whoever is signed in now, nor be saved into their notes. It is
        // already hidden; the close still waits for this route to be on top.
        _close(false);
      case NoteSaveRetired(reason: NoteSaveRetirement.deleted):
        await _tellAndClose(
            'This note was deleted before your changes were stored, so they were not saved.');
      case NoteSaveRetired(reason: NoteSaveRetirement.replaced):
        await _offerRetry(
            'This note changed elsewhere before your edit was stored. Your draft is still here.',
            focusBefore);
      case NoteSaveFailed(:final error):
        await _offerRetry(
            error is StateError
                ? '${error.message} Your draft is still here.'
                : 'This note could not be stored on this device. Your draft is still here.',
            focusBefore);
      case NoteSaveRejected():
        await _offerRetry(
            'The notes list closed before this note was saved. Your draft is still here.',
            focusBefore);
    }
  }

  Future<void> _tellAndClose(String message) async {
    if (!mounted || _closing) return;
    _confirmingClose = true;
    await showAtomicDialog<void>(
      context: context,
      title: 'Not saved',
      body: message,
      actions: const [
        AtomicDialogAction(
          label: 'Close',
          result: null,
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    _confirmingClose = false;
    if (mounted) _close(false);
  }

  /// After a failed save: try again, keep editing, or leave without saving.
  /// Editing returns the caret to where it was before Done.
  Future<void> _offerRetry(String message, [FocusNode? focusBefore]) async {
    if (!mounted || _closing) return;
    _confirmingClose = true;
    final action = await showAtomicDialog<String>(
      context: context,
      title: 'Not saved',
      body: message,
      actions: const [
        AtomicDialogAction(
          label: 'Discard',
          result: 'discard',
          variant: AtomicButtonVariant.danger,
        ),
        AtomicDialogAction(label: 'Edit', result: 'edit'),
        AtomicDialogAction(
          label: 'Retry',
          result: 'retry',
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    _confirmingClose = false;
    if (!mounted) return;
    if (action == 'retry') {
      _finish(true);
    } else if (action == 'discard') {
      _close(false);
    } else if (focusBefore != null && focusBefore.context != null) {
      focusBefore.requestFocus();
    }
  }

  Future<void> _requestClose() async {
    if (_closing || _saving || _confirmingClose || _picking || _starting) {
      return;
    }
    _cancelSpeech();
    if (!_changed) {
      _finish(false);
      return;
    }
    _confirmingClose = true;
    final action = await showAtomicDialog<String>(
      context: context,
      title: 'Save your changes?',
      body: 'Choose Save to keep this draft, or keep editing.',
      actions: const [
        AtomicDialogAction(label: 'Keep editing', result: 'keep'),
        AtomicDialogAction(
          label: 'Discard',
          result: 'discard',
          variant: AtomicButtonVariant.danger,
        ),
        AtomicDialogAction(
          label: 'Save',
          result: 'save',
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    _confirmingClose = false;
    if (!mounted) return;
    if (action == 'save') _finish(true);
    if (action == 'discard') _finish(false);
  }

  void _insertLine({required bool checklist, int? after}) {
    if (_document.isReadOnly || _locked) return;
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
    if (_document.isReadOnly || _locked) return;
    _cancelSpeech();
    final removedImage = _document.lines[index].imageBase64;
    setState(() {
      _document.removeAt(index);
      _lines.removeAt(index).dispose();
      _focus.removeAt(index).dispose();
      if (index < _activeLine) _activeLine--;
      _activeLine = _activeLine.clamp(-1, _lines.length - 1);
    });
    if (removedImage != null &&
        !_document.lines.any((line) => line.imageBase64 == removedImage)) {
      final bytes = _images.remove(removedImage);
      if (bytes != null) _releaseImage(bytes);
      final thumbnail = _thumbnails.remove(removedImage);
      if (thumbnail != null) NoteImageDecode.release(thumbnail);
    }
  }

  Future<void> _confirmRemoveImage(int index) async {
    if (_document.isReadOnly ||
        _locked ||
        _confirmingImageRemoval ||
        index < 0 ||
        index >= _lines.length ||
        !_document.lines[index].isImage) {
      return;
    }
    // The modal decision is asynchronous. Retain the row identity so another
    // row mutation cannot turn this index into a different image or text row.
    final target = _lines[index];
    _confirmingImageRemoval = true;
    _cancelSpeech();
    bool? remove;
    try {
      remove = await showAtomicDialog<bool>(
        context: context,
        title: 'Remove image?',
        body:
            'Remove this image from the draft? Choose Done to save the change.',
        icon: AtomicIcons.trash,
        destructive: true,
        actions: const [
          AtomicDialogAction(label: 'Keep image', result: false),
          AtomicDialogAction(
            label: 'Remove image',
            result: true,
            variant: AtomicButtonVariant.danger,
          ),
        ],
      );
    } finally {
      _confirmingImageRemoval = false;
    }
    if (!mounted || _closing || remove != true) return;
    final currentIndex = _lines.indexOf(target);
    if (currentIndex >= 0 && _document.lines[currentIndex].isImage) {
      _removeLine(currentIndex);
    }
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
      const AtomicSnackBar(
        text: 'Copied to clipboard',
        millis: 1200,
      ).show(context);
    } on PlatformException {
      if (!mounted) return;
      const AtomicSnackBar(
        text: "Couldn't copy. Your draft is still here.",
        millis: 2000,
        error: true,
      ).show(context);
    }
  }

  /// The "…" menu: Copy note, and Move to Recycle Bin (a saved note) or
  /// Discard note (a new one). Delete keeps its own confirmation.
  Future<void> _showActions() async {
    if (_locked) return;
    final canDelete = !_document.isReadOnly && !_picking && !_starting;
    final saved = widget.onDelete != null;
    final action = await showAtomicSheet<_EditorAction>(
      context: context,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AtomicSheetAction(
            icon: AtomicIcons.copy,
            label: 'Copy note',
            onTap: () => Navigator.of(sheet).pop(_EditorAction.copy),
          ),
          if (canDelete)
            AtomicSheetAction(
              icon: AtomicIcons.trash,
              label: saved ? 'Move to Recycle Bin' : 'Discard note',
              destructive: true,
              onTap: () => Navigator.of(sheet).pop(_EditorAction.delete),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case _EditorAction.copy:
        await _copy();
      case _EditorAction.delete:
        await _delete();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      // While a save is in flight the draft is the submitted snapshot:
      // input waits for its result. A retired draft is not built at all.
      child: _retired ? const _RetiredDraft() : _PendingSaveLock(
        locked: _saving,
        child: LayoutBuilder(builder: (context, constraints) {
          // The space left for the editor above the keyboard, as before.
          final keyboard = MediaQuery.viewInsetsOf(context).bottom;
          final compact = constraints.maxHeight -
                  keyboard -
                  MediaQuery.paddingOf(context).vertical <
              400;
          final margin = AtomicSpace.screenMargin(
              constraints.maxWidth.clamp(0.0, _maxWidth).toDouble());
          return Scaffold(
            backgroundColor: c.canvas,
            // The toolbar rides on the keyboard by itself (below), so the
            // scaffold's floating messages sit above the toolbar, never
            // over Done.
            resizeToAvoidBottomInset: false,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: ListView(
                            controller: _scroll,
                            padding: EdgeInsets.fromLTRB(
                                margin, AtomicSpace.x2, margin, AtomicSpace.x4),
                            children: [
                              _FieldName(
                                  name: 'Title',
                                  controller: _title,
                                  child: TextField(
                                    key: const ValueKey('note-title'),
                                    readOnly: _document.isReadOnly || _locked,
                                    controller: _title,
                                    focusNode: _titleFocus,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    maxLines: null,
                                    style: AtomicType.headlineLarge
                                        .copyWith(color: c.textPrimary),
                                    cursorColor: c.textPrimary,
                                    decoration: _decoration(
                                        'Title', AtomicType.headlineLarge),
                                    onChanged: (_) => _contentRevision.value++,
                                  )),
                              _tags(),
                              const SizedBox(height: AtomicSpace.x3),
                              ValueListenableBuilder<int>(
                                valueListenable: _contentRevision,
                                builder: (context, _, __) => _meta(compact),
                              ),
                              Divider(
                                  height: AtomicSpace.x6,
                                  thickness: 1,
                                  color: c.outline),
                              for (var i = 0; i < _document.lines.length; i++)
                                _lineRow(i),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            bottomNavigationBar: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: SafeArea(
                top: false,
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _maxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                margin, AtomicSpace.x2, margin, 0),
                            child: ValueListenableBuilder<int>(
                              valueListenable: _contentRevision,
                              builder: (context, _, __) => _statistics(),
                            ),
                          ),
                        _toolbar(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static const double _maxWidth = 760;

  /// Back, then the pin and important toggles and the "…" menu. The note's
  /// own title below is the page heading.
  Widget _header() {
    final editable = !(_document.isReadOnly || _locked);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AtomicSpace.x2, vertical: AtomicSpace.x1),
      child: Row(
        children: [
          _NamedButton(AtomicIconButton(
            icon: AtomicIcons.arrowLeft,
            tooltip: 'Back to notes',
            onPressed: _requestClose,
          )),
          const Spacer(),
          _NamedButton(AtomicIconButton(
            icon: AtomicIcons.pin,
            toggledIcon: AtomicIcons.pinFilled,
            toggled: _draft.pinned,
            tooltip: _draft.pinned ? 'Unpin note' : 'Pin note',
            onPressed: editable
                ? () => setState(() => _draft.pinned = !_draft.pinned)
                : null,
          )),
          const SizedBox(width: AtomicSpace.x1),
          _NamedButton(AtomicIconButton(
            icon: AtomicIcons.star,
            toggledIcon: AtomicIcons.starFilled,
            toggled: _draft.important,
            tooltip: _draft.important ? 'Unmark important' : 'Mark important',
            onPressed: editable
                ? () => setState(() => _draft.important = !_draft.important)
                : null,
          )),
          const SizedBox(width: AtomicSpace.x1),
          _NamedButton(AtomicIconButton(
            icon: AtomicIcons.dots,
            tooltip: 'More actions',
            onPressed: _showActions,
          )),
        ],
      ),
    );
  }

  /// "Edited 9 Nov, 19:37 · Unsaved changes · 3000 MAX", wrapping as needed.
  Widget _meta(bool compact) {
    final c = context.colors;
    final changed = _changed;
    return _Dotted([
      _caption('Edited ${_stamp(widget.note.updatedAt)}'),
      _caption(
        _document.isReadOnly
            ? 'Unsupported format · read-only'
            : changed
                ? 'Unsaved changes'
                : widget.note.isEmpty
                    ? 'New note'
                    : 'Saved on this device',
        color: changed ? c.accentText : null,
      ),
      if (compact) _wordCountLabel(_wordCount),
      _caption(_wordLimit.label),
    ]);
  }

  Widget _caption(String text, {Color? color}) => Text(text,
      style: AtomicType.bodySmall
          .copyWith(color: color ?? context.colors.textSecondary));

  /// Text and checklist tools, image and dictation, then Done: one raised
  /// pill above the keyboard. The tools scroll at large text; Done stays.
  Widget _toolbar() {
    final c = context.colors;
    final tools = [
      _tool('Add text line', AtomicIcons.letterT,
          () => _insertLine(checklist: false)),
      _tool('Add checklist line', AtomicIcons.listCheck,
          () => _insertLine(checklist: true)),
      _tool('Add image', AtomicIcons.photoPlus, _pickImage),
      _tool(
          _listening ? 'Stop dictation' : 'Dictate text',
          _listening ? AtomicIcons.playerStop : AtomicIcons.microphone,
          _dictate,
          active: _listening),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AtomicSpace.x4, AtomicSpace.x2, AtomicSpace.x4, AtomicSpace.x4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: AtomicRadius.pill,
          boxShadow: [
            BoxShadow(
                color: c.floatingShadow,
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AtomicSpace.x2, vertical: AtomicSpace.x1),
            child: Row(children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (var i = 0; i < tools.length; i++) ...[
                      if (i > 0) const SizedBox(width: AtomicSpace.x2),
                      tools[i],
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: AtomicSpace.x2),
              _doneButton(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tool(String tooltip, IconData icon, VoidCallback action,
          {bool active = false}) =>
      _NamedButton(AtomicIconButton(
        icon: icon,
        tooltip: tooltip,
        onCard: true,
        toggled: active ? true : null,
        onPressed:
            _document.isReadOnly || _picking || _starting ? null : action,
      ));

  /// Done: an accent pill with a check and its visible label, which is what
  /// a screen reader announces; the tooltip says what it does. While the
  /// save is pending it reads "Saving…" and takes no input.
  Widget _doneButton() {
    final c = context.colors;
    final busy = _saving;
    return Tooltip(
      message: 'Save note',
      excludeFromSemantics: true,
      child: FilledButton(
        onPressed: _document.isReadOnly || _picking || _starting || _saving
            ? null
            : () => _finish(true),
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          disabledBackgroundColor: busy ? c.accent : c.surfaceInset,
          disabledForegroundColor: busy ? c.onAccent : c.textDisabled,
          minimumSize: const Size(56, 56),
          padding: const EdgeInsets.symmetric(horizontal: AtomicSpace.x5),
          shape: const StadiumBorder(),
          textStyle: AtomicType.labelLarge,
          elevation: 0,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(busy ? AtomicIcons.clock : AtomicIcons.check, size: 20),
          const SizedBox(width: AtomicSpace.x2),
          Flexible(child: Text(busy ? 'Saving…' : 'Done')),
        ]),
      ),
    );
  }

  Widget _lineRow(int index) {
    final c = context.colors;
    final line = _document.lines[index];
    if (line.isImage) {
      final data = line.imageBase64!;
      final bytes = _images.putIfAbsent(data, () => base64Decode(data));
      final thumbnail = _thumbnailFor(data, bytes);
      return Padding(
        key: ObjectKey(_lines[index]),
        padding: const EdgeInsets.symmetric(vertical: AtomicSpace.x2),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Stack(children: [
            Semantics(
              button: true,
              label: 'View note image',
              // One stop named once: the Semantics label above, without the
              // tooltip or the image repeating it inside the button.
              child: Tooltip(
                message: 'View note image',
                excludeFromSemantics: true,
                child: InkWell(
                  onTap: () => _viewImage(bytes),
                  borderRadius: AtomicRadius.mediumAll,
                  child: ClipRRect(
                    borderRadius: AtomicRadius.mediumAll,
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minWidth: 120, minHeight: 48),
                      child: Image(
                          image: thumbnail,
                          height: _thumbnailHeight,
                          fit: BoxFit.contain,
                          // Kept for finders; the button above is the only
                          // name.
                          semanticLabel: 'Note image',
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => Text(
                              'Image could not be displayed',
                              style: AtomicType.bodyMedium
                                  .copyWith(color: c.textSecondary))),
                    ),
                  ),
                ),
              ),
            ),
            // The remove circle sits on the thumbnail's top-right corner and
            // keeps the confirmation.
            PositionedDirectional(
              top: 0,
              end: 0,
              child: _NamedButton(Tooltip(
                message: 'Remove image',
                excludeFromSemantics: true,
                child: AtomicPressable(
                  onTap: () => _confirmRemoveImage(index),
                  semanticsLabel: 'Remove image',
                  excludeSemantics: true,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: c.inverseSurface, shape: BoxShape.circle),
                    child: Icon(AtomicIcons.x, size: 20, color: c.onInverse),
                  ),
                ),
              )),
            ),
          ]),
        ),
      );
    }
    if (!line.isChecklist) {
      return _FieldName(
          key: ObjectKey(_lines[index]),
          name: 'Note text',
          controller: _lines[index],
          child: NoteFieldLocator(
            name: index == 0 ? 'note-body' : 'note-text-$index',
            child: TextField(
              readOnly: _document.isReadOnly || _locked,
              contextMenuBuilder: (context, state) =>
                  _selectionMenu(state, index),
              controller: _lines[index],
              focusNode: _focus[index],
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              minLines: _document.lines.length == 1 ? 5 : null,
              style: AtomicType.bodyLarge.copyWith(color: c.textPrimary),
              cursorColor: c.textPrimary,
              decoration: _decoration('Start writing…', AtomicType.bodyLarge),
            ),
          ));
    }
    // The checklist pill: round checkbox, the item's field, a remove button.
    return Padding(
      key: ObjectKey(_lines[index]),
      padding: const EdgeInsets.symmetric(vertical: AtomicSpace.x1),
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: c.surfaceInset, borderRadius: AtomicRadius.largeAll),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: AtomicSpace.x1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AtomicCheckbox(
                checked: line.done,
                semanticsLabel: 'Complete item ${index + 1}',
                onChanged: _locked
                    ? null
                    : (value) =>
                        setState(() => _document.setDone(index, value)),
              ),
              const SizedBox(width: AtomicSpace.x1),
              Expanded(
                child: _FieldName(
                    name: 'List item',
                    controller: _lines[index],
                    child: NoteFieldLocator(
                      name: 'note-item-$index',
                      child: TextField(
                        readOnly: _document.isReadOnly || _locked,
                        contextMenuBuilder: (context, state) =>
                            _selectionMenu(state, index),
                        controller: _lines[index],
                        focusNode: _focus[index],
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.next,
                        maxLines: null,
                        onSubmitted: (_) =>
                            _insertLine(checklist: true, after: index),
                        style: AtomicType.bodyLarge.copyWith(
                          color: line.done ? c.textSecondary : c.textPrimary,
                          decoration:
                              line.done ? TextDecoration.lineThrough : null,
                          decorationColor: c.textSecondary,
                        ),
                        cursorColor: c.textPrimary,
                        decoration:
                            _decoration('List item', AtomicType.bodyLarge),
                      ),
                    )),
              ),
              _NamedButton(Tooltip(
                message: 'Remove item ${index + 1}',
                excludeFromSemantics: true,
                child: AtomicPressable(
                  onTap: () => _removeLine(index),
                  semanticsLabel: 'Remove item ${index + 1}',
                  excludeSemantics: true,
                  child: Icon(AtomicIcons.x, size: 20, color: c.textSecondary),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  static const double _thumbnailHeight = 220;

  /// The thumbnail decodes no larger than its box: the screen width by 220,
  /// in physical pixels. A size change replaces (and releases) the provider.
  ResizeImage _thumbnailFor(String data, Uint8List bytes) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final wanted = NoteImageDecode.thumbnail(bytes,
        logicalWidth: width,
        logicalHeight: _thumbnailHeight,
        devicePixelRatio: ratio);
    // _images keeps one byte buffer per data string, so only the size can
    // change between builds.
    final current = _thumbnails[data];
    if (current != null &&
        current.width == wanted.width &&
        current.height == wanted.height) {
      return current;
    }
    if (current != null) NoteImageDecode.release(current);
    return _thumbnails[data] = wanted;
  }

  Future<void> _viewImage(Uint8List bytes) async {
    _cancelSpeech();
    // Unfocus the text node itself: unfocusing its route scope only clears
    // the parent scope, leaving a remembered text focus to reopen the keyboard.
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
      context: context,
      // The viewer sits on black in both themes.
      barrierColor: _viewerBackdrop,
      builder: (_) => NoteImageViewer(bytes: bytes),
    );
  }

  static const Color _viewerBackdrop = Color(0xE6010101); // black at 90%

  Widget _selectionMenu(EditableTextState state, int index) =>
      _document.isReadOnly
          ? AdaptiveTextSelectionToolbar.editableText(editableTextState: state)
          : RichSelectionToolbar(editable: state, controller: _lines[index]);

  void _message(String text) {
    if (mounted) {
      AtomicSnackBar(text: text, millis: 3000, error: true).show(context);
    }
  }

  /// Tag chips, then "Add tag" until the note has three tags.
  Widget _tags() => _document.isReadOnly
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: AtomicSpace.x2),
          child: Wrap(
            spacing: AtomicSpace.chipGap,
            runSpacing: AtomicSpace.x2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in _document.tags)
                TagChip(
                    tag: tag,
                    onRemove: () => setState(() => _document.setTags(
                        _document.tags.where((v) => v != tag).toList()))),
              if (_document.tags.length < NoteDocument.maxTagsPerNote)
                _NamedButton(Tooltip(
                    message: 'Add tag',
                    excludeFromSemantics: true,
                    child: AddTagChip(onPressed: _addTag))),
            ],
          ),
        );

  Future<void> _addTag() async {
    if (_locked) return;
    final controller = TextEditingController();
    // Add, or the keyboard's submit action, takes the field's text; Cancel,
    // Back and the scrim add nothing.
    final added = await showAtomicDialog<bool>(
      context: context,
      title: 'Add tag',
      content: Builder(builder: (dialog) {
        final c = dialog.colors;
        return TextField(
            key: const ValueKey('note-tag-input'),
            controller: controller,
            autofocus: true,
            maxLength: NoteDocument.maxTagCharacters,
            // Show the count, but never cut pasted text: an over-long
            // tag is refused on Add with a message instead.
            maxLengthEnforcement: MaxLengthEnforcement.none,
            maxLines: 1,
            style: AtomicType.bodyLarge.copyWith(color: c.textPrimary),
            cursorColor: c.textPrimary,
            decoration: AtomicInputDecoration.of(dialog,
                    hintText: 'For example, morning')
                .copyWith(
                    helperText: '15 characters maximum',
                    helperStyle:
                        AtomicType.bodySmall.copyWith(color: c.textSecondary),
                    helperMaxLines: 3,
                    counterStyle:
                        AtomicType.bodySmall.copyWith(color: c.textSecondary)),
            onSubmitted: (_) => Navigator.of(dialog).pop(true));
      }),
      actions: const [
        AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: 'Add',
          result: true,
          variant: AtomicButtonVariant.primary,
        ),
      ],
    );
    final tag = added == true ? controller.text : null;
    // Let the outgoing dialog release its field before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (!mounted || tag == null || _locked) return;
    try {
      setState(() => _document.setTags(
          [..._document.tags, tag.trim().replaceFirst(RegExp(r'^#+'), '')]));
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _pickImage() async {
    if (_picking || _document.isReadOnly || _locked) return;
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
            'The image must fit within 60 KB and the remaining note image space. Your draft is still here.');
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
      if (_locked) return;
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
    if (_document.isReadOnly || _starting || _locked) return;
    if (_listening) {
      await _speechInput.stop();
      return;
    }
    if (!_speechExplained) {
      // Consent copy from the copy proposal (ADR-013); never auto-started.
      final accepted = await showAtomicDialog<bool>(
        context: context,
        title: 'Dictate into your note',
        body: "Dictation uses your device's speech-recognition service. "
            'It may send speech to its provider for processing. '
            'Start dictation?',
        icon: AtomicIcons.microphone,
        actions: const [
          AtomicDialogAction(label: 'Not now', result: false),
          AtomicDialogAction(
            label: 'Start dictation',
            result: true,
            variant: AtomicButtonVariant.primary,
          ),
        ],
      );
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
              _locked ||
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
    if (_locked) return;
    _cancelSpeech();
    final saved = widget.onDelete != null;
    final accepted = await showAtomicDialog<bool>(
      context: context,
      title: saved ? 'Move note to Recycle Bin?' : 'Discard this note?',
      body: saved
          ? 'The saved note can be restored from the Recycle Bin. Unsaved changes will be discarded.'
          : 'This unsaved draft will be discarded.',
      icon: AtomicIcons.trash,
      destructive: true,
      actions: [
        const AtomicDialogAction(label: 'Cancel', result: false),
        AtomicDialogAction(
          label: saved ? 'Move to Recycle Bin' : 'Discard',
          result: true,
          variant: AtomicButtonVariant.danger,
        ),
      ],
    );
    if (!mounted || accepted != true) return;
    widget.onDelete?.call();
    _finish(false);
  }

  int get _wordCount =>
      NoteWordLimit.count(title: _title.text, lines: _document.lines);

  /// Over the ceiling the count reads in the danger text colour; Done
  /// explains the limit.
  Widget _wordCountLabel(int words) => _caption(
      words == 1 ? '1 word' : '$words words',
      color: words > _wordLimit.ceiling ? context.colors.dangerText : null);

  /// "12 words · 1 min read · 0/1 done", plus "Listening…" while dictating.
  Widget _statistics() {
    final words = _wordCount;
    return _Dotted([
      _wordCountLabel(words),
      _caption('${(words / 200).ceil().clamp(1, 9999)} min read'),
      if (_document.hasChecklist ||
          (_draft.kind == NoteKind.todo &&
              (!_document.hasChanges ||
                  (_draft.body.isEmpty &&
                      _document.lines.isEmpty &&
                      _document.tags.isEmpty))))
        _caption('${_document.lines.where((line) => line.isChecklist && line.text.trim().isNotEmpty && line.done).length}'
            '/${_document.lines.where((line) => line.isChecklist && line.text.trim().isNotEmpty).length} done'),
      if (_listening || _starting)
        Semantics(
            liveRegion: true,
            child: _caption('Listening…', color: context.colors.accentText)),
    ]);
  }

  /// A borderless field (the title and the lines): no fill, no outline, the
  /// hint in the field's own style.
  InputDecoration _decoration(String hint, TextStyle style) => InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        hintText: hint,
        hintStyle: style.copyWith(color: context.colors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(vertical: AtomicSpace.x2),
      );

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "9 Nov, 19:37"; another year adds it: "9 Nov 2025, 19:37".
  static String _stamp(DateTime value) {
    final local = value.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    final year =
        local.year == DateTime.now().year ? '' : ' ${local.year}';
    return '${local.day} ${_months[local.month - 1]}$year, '
        '${pad(local.hour)}:${pad(local.minute)}';
  }
}

enum _EditorAction { copy, delete }

/// One control, one semantics node, found by its tooltip too: the shared
/// buttons keep their tooltip outside the pressable's node, so this merges
/// the two. The node's name, role, state and actions are unchanged.
class _NamedButton extends StatelessWidget {
  const _NamedButton(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(child: child);
}

/// Short captions in a row, separated by a middle dot that screen readers
/// skip. Wraps at large text or on narrow screens.
class _Dotted extends StatelessWidget {
  const _Dotted(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dot = ExcludeSemantics(
      child: Text('·',
          style: AtomicType.bodySmall
              .copyWith(color: context.colors.textSecondary)),
    );
    return Wrap(
      spacing: AtomicSpace.x2,
      runSpacing: AtomicSpace.x1,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) dot,
          children[i],
        ],
      ],
    );
  }
}

/// Names a text field for screen readers once it has text.
///
/// A field's only name is its hint, which Flutter stops reporting when the
/// field is filled: a filled title was read as its text alone. An empty
/// field keeps the hint as its single name, so it is not announced twice.
/// Only this Semantics rebuilds on typing; the field itself is [child].
class _FieldName extends StatelessWidget {
  const _FieldName(
      {required this.name,
      required this.controller,
      required this.child,
      super.key});

  final String name;
  final TextEditingController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        child: child,
        builder: (context, value, child) =>
            Semantics(label: value.text.isEmpty ? null : name, child: child),
      );
}

/// Names a line's text field by its current position: `note-body`,
/// `note-text-N` or `note-item-N`.
///
/// Tests and tooling find a field by this name. It is plain metadata: it is
/// not a key, so it plays no part in matching widgets to elements. A line's
/// widget is keyed by its controller ([ObjectKey]), so inserting or removing a
/// line keeps every other line's editing state, and the name always describes
/// the field's position now.
class NoteFieldLocator extends StatelessWidget {
  const NoteFieldLocator({required this.name, required this.child, super.key});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// What a retired editor shows while its close waits (review R14): the page
/// colour and nothing else, so no title, line, tag or image of the draft is
/// on screen or in the semantics tree for whoever is signed in now.
class _RetiredDraft extends StatelessWidget {
  const _RetiredDraft();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ColoredBox(
            color: context.colors.canvas, child: const SizedBox.expand()),
      );
}

/// While a save is pending: no pointer input and no focus, so neither taps
/// nor keyboard traversal or text input can reach a field (review R10).
class _PendingSaveLock extends StatelessWidget {
  const _PendingSaveLock({required this.locked, required this.child});

  final bool locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: locked,
        child: ExcludeFocus(excluding: locked, child: child),
      );
}
