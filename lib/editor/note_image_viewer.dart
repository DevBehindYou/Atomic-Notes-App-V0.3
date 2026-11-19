import 'dart:math' as math;
import 'dart:typed_data';

import 'package:atomic_notes/theme/atomic_colors.dart';
import 'package:atomic_notes/theme/atomic_icons.dart';
import 'package:atomic_notes/theme/atomic_tokens.dart';
import 'package:atomic_notes/theme/atomic_type.dart';
import 'package:flutter/material.dart';

/// A read-only view of the editor's existing bytes. It never touches the note,
/// image picker, compressor or persistence path.
///
/// The viewer is black in both themes (components spec, Image thumbnail and
/// viewer), with 44 dp round controls in 48 dp targets.
class NoteImageViewer extends StatefulWidget {
  const NoteImageViewer({required this.bytes, super.key});

  final Uint8List bytes;

  @override
  State<NoteImageViewer> createState() => _NoteImageViewerState();
}

class _NoteImageViewerState extends State<NoteImageViewer> {
  final _transform = TransformationController();
  late MemoryImage _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;
  Size? _viewport;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _provider = MemoryImage(widget.bytes);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imageSize == null && !_failed && _stream == null) _resolveImage();
  }

  @override
  void didUpdateWidget(NoteImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _detachListener();
      _release();
      _provider = MemoryImage(widget.bytes);
      _imageSize = null;
      _failed = false;
      _resetZoom();
      _resolveImage();
    }
  }

  void _resolveImage() {
    // Resolve through Flutter's asynchronous decoder and shared image cache.
    // Decoder dimensions also account for orientation metadata. This listener
    // retains dimensions only; each delivered ImageInfo must be disposed.
    _stream = _provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      final size =
          Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      _detachListener();
      if (mounted) setState(() => _imageSize = size);
    }, onError: (Object error, StackTrace? stack) {
      _detachListener();
      if (mounted) setState(() => _failed = true);
    });
    _stream!.addListener(_listener!);
  }

  void _detachListener() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  /// The viewer's full-size decode is its own: drop it from the cache once
  /// nothing shows it, so it is not kept after the popup closes.
  void _release() =>
      PaintingBinding.instance.imageCache.evict(_provider, includeLive: false);

  @override
  void dispose() {
    _detachListener();
    _release();
    _transform.dispose();
    super.dispose();
  }

  void _resetZoom() => _transform.value = Matrix4.identity();

  void _zoom(double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final current = _transform.value;
    final oldScale = current.getMaxScaleOnAxis();
    final scale = (oldScale * factor).clamp(1.0, 5.0);
    final ratio = scale / oldScale;
    final translation = current.getTranslation();
    // Keep the same image point under the centre when using buttons. Clamp
    // panning back inside the image when zooming out after dragging.
    final x = (viewport.width / 2 * (1 - ratio) + translation.x * ratio)
        .clamp(viewport.width * (1 - scale), 0.0);
    final y = (viewport.height / 2 * (1 - ratio) + translation.y * ratio)
        .clamp(viewport.height * (1 - scale), 0.0);
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(x, y, 0);
  }

  /// The viewer's own colours: the same in both themes.
  static const Color _backdrop = AtomicPalette.black;
  static const Color _content = AtomicPalette.gray50;
  static const Color _fill = AtomicPalette.gray850;
  static const Color _disabled = AtomicPalette.gray450;

  /// A 44 dp round control centred in a 48 dp target. The tooltip (and its
  /// semantics label) covers the whole target, so the target is what a tap,
  /// a long press and a screen reader find.
  Widget _control(String label, IconData icon, VoidCallback? action) =>
      MergeSemantics(
        child: Tooltip(
          message: label,
          child: SizedBox.square(
            dimension: AtomicSpace.minTarget,
            child: Center(
              child: IconButton(
                onPressed: action,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  fixedSize: const Size(44, 44),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.padded,
                  foregroundColor: _content,
                  backgroundColor: _fill,
                  disabledForegroundColor: _disabled,
                  disabledBackgroundColor: _fill,
                  shape: const CircleBorder(),
                ),
                icon: Icon(icon, size: 24),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: _backdrop,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AtomicSpace.x4),
        constraints: const BoxConstraints(minWidth: 0),
        shape: const RoundedRectangleBorder(
          borderRadius: AtomicRadius.largeAll,
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, bounds) {
          // Fixed-size icon controls remain usable at large text scales. When
          // the keyboard leaves exceptionally little room, the whole surface
          // scrolls and Close remains first, rather than overflowing the route.
          const chromeHeight =
              48.0 + 48.0 + AtomicSpace.x2 * 2 + AtomicSpace.x4 * 2;
          final maxWidth = math.max(1.0, bounds.maxWidth - AtomicSpace.x4 * 2);
          final maxHeight = math.max(48.0, bounds.maxHeight - chromeHeight);
          final size = _imageSize;
          final fitted = size == null
              ? Size(math.min(maxWidth, 240), math.min(maxHeight, 120))
              : applyBoxFit(BoxFit.contain, size, Size(maxWidth, maxHeight))
                  .destination;
          if (_viewport != fitted) {
            final previous = _viewport;
            _viewport = fitted;
            if (previous != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _resetZoom();
              });
            }
          }
          final width = math.min(bounds.maxWidth,
              math.max(fitted.width + AtomicSpace.x4 * 2, 176.0));
          return SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(AtomicSpace.x4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                      child: Semantics(
                        namesRoute: true,
                        header: true,
                        child: Text('Image',
                            style: AtomicType.titleMedium
                                .copyWith(color: _content),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    _control('Close image', AtomicIcons.x,
                        () => Navigator.of(context).pop()),
                  ]),
                  const SizedBox(height: AtomicSpace.x2),
                  if (_failed)
                    Semantics(
                      liveRegion: true,
                      child: Text('Image could not be displayed.',
                          style:
                              AtomicType.bodyMedium.copyWith(color: _content)),
                    )
                  else if (size == null)
                    SizedBox(
                      height: fitted.height,
                      child: const Center(
                        child: CircularProgressIndicator(
                            semanticsLabel: 'Loading image',
                            color: AtomicPalette.orange500),
                      ),
                    )
                  else
                    SizedBox.fromSize(
                      size: fitted,
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 5,
                        child: Image(
                          image: _provider,
                          width: fitted.width,
                          height: fitted.height,
                          fit: BoxFit.contain,
                          semanticLabel: 'Full size note image',
                          errorBuilder: (_, __, ___) => Text(
                              'Image could not be displayed.',
                              style: AtomicType.bodyMedium
                                  .copyWith(color: _content)),
                        ),
                      ),
                    ),
                  const SizedBox(height: AtomicSpace.x2),
                  ValueListenableBuilder<Matrix4>(
                    valueListenable: _transform,
                    builder: (context, transform, _) {
                      final scale = transform.getMaxScaleOnAxis();
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _control(
                              'Zoom out',
                              Icons.remove,
                              size != null && scale > 1
                                  ? () => _zoom(1 / 1.5)
                                  : null),
                          _control(
                              'Zoom in',
                              Icons.add,
                              size != null && scale < 5
                                  ? () => _zoom(1.5)
                                  : null),
                          _control('Reset zoom', Icons.fit_screen,
                              size != null ? _resetZoom : null),
                        ],
                      );
                    },
                  ),
                ]),
              ),
            ),
          );
        }),
      );
}
