import 'dart:math' as math;
import 'dart:typed_data';

import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/material.dart';

/// A read-only view of the editor's existing bytes. It never touches the note,
/// image picker, compressor or persistence path.
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

  @override
  void dispose() {
    _detachListener();
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

  Widget _control(String label, IconData icon, VoidCallback? action,
          {bool primary = false}) =>
      IconButton(
        onPressed: action,
        tooltip: label,
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: primary ? AppColors.paper : AppColors.ink,
          backgroundColor: primary ? AppColors.signal : AppColors.paper,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.std),
          side:
              const BorderSide(color: AppColors.ink, width: AppStroke.hairline),
        ),
        icon: Icon(icon),
      );

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpace.md),
        constraints: const BoxConstraints(minWidth: 0),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.std,
          side: BorderSide(color: AppColors.ink, width: AppStroke.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, bounds) {
          // Fixed-size icon controls remain usable at large text scales. When
          // the keyboard leaves exceptionally little room, the whole surface
          // scrolls and Close remains first, rather than overflowing the route.
          const chromeHeight = 48.0 + 48.0 + AppSpace.sm * 2 + AppSpace.md * 2;
          final maxWidth = math.max(1.0, bounds.maxWidth - AppSpace.md * 2);
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
          final width = math.min(
              bounds.maxWidth, math.max(fitted.width + AppSpace.md * 2, 176.0));
          return SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                      child: Semantics(
                        namesRoute: true,
                        header: true,
                        child: const Text('Image',
                            style: AppType.headlineSm,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    _control('Close image', Icons.close,
                        () => Navigator.of(context).pop(),
                        primary: true),
                  ]),
                  const SizedBox(height: AppSpace.sm),
                  if (_failed)
                    Semantics(
                      liveRegion: true,
                      child: const Text('Image could not be displayed.',
                          style: AppType.bodyMd),
                    )
                  else if (size == null)
                    SizedBox(
                      height: fitted.height,
                      child: const Center(
                        child: CircularProgressIndicator(
                            semanticsLabel: 'Loading image',
                            color: AppColors.signal),
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
                          errorBuilder: (_, __, ___) => const Text(
                              'Image could not be displayed.',
                              style: AppType.bodyMd),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpace.sm),
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
