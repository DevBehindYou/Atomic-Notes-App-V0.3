import 'dart:async';
import 'dart:convert';

import 'package:atomic_notes/database/note_rich_content.dart';
import 'package:atomic_notes/theme/app_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

class ImageOptimizationRequest {
  const ImageOptimizationRequest(
      {required this.sourceBase64,
      required this.quality,
      required this.maxDimension});
  final String sourceBase64;
  final int quality;
  final int maxDimension;
}

class ImageOptimizationResult {
  const ImageOptimizationResult(
      {required this.bytes,
      required this.width,
      required this.height,
      required this.sourceWidth,
      required this.sourceHeight});
  final Uint8List bytes;
  final int width, height, sourceWidth, sourceHeight;
}

/// Runs in a compute isolate in the product. Quality is exactly the user's
/// selected value: an oversized result stays oversized until they change it.
ImageOptimizationResult optimizeNoteImage(ImageOptimizationRequest request) {
  if (request.quality < 40 ||
      request.quality > 85 ||
      ![512, 768, 1024].contains(request.maxDimension)) {
    throw ArgumentError('Invalid image optimization settings');
  }
  final source = NoteImageContent.decode(request.sourceBase64);
  final decoded =
      image.decodeJpg(source, maxPixels: NoteImageContent.maxPixels);
  if (decoded == null) {
    throw const FormatException('The image could not be read.');
  }
  var oriented = image.bakeOrientation(decoded);
  final sourceWidth = oriented.width, sourceHeight = oriented.height;
  if (oriented.width > request.maxDimension ||
      oriented.height > request.maxDimension) {
    oriented = image.copyResize(oriented,
        width: oriented.width >= oriented.height ? request.maxDimension : null,
        height: oriented.height > oriented.width ? request.maxDimension : null);
  }
  final clean = image.Image(width: oriented.width, height: oriented.height);
  image.fill(clean, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(clean, oriented);
  return ImageOptimizationResult(
      bytes:
          Uint8List.fromList(image.encodeJpg(clean, quality: request.quality)),
      width: clean.width,
      height: clean.height,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight);
}

/// A draft-only preview. Closing or Cancel never attaches an image; Insert
/// returns a bare JPEG base64 value for the editor's normal note save path.
class NoteImageOptimizer extends StatefulWidget {
  const NoteImageOptimizer(
      {required this.sourceBase64,
      required this.maxBytes,
      this.validate,
      this.optimizer,
      super.key});
  final String sourceBase64;
  final int maxBytes;
  final String? Function(String)? validate;

  /// Injection for deterministic asynchronous tests; production uses compute.
  final Future<ImageOptimizationResult> Function(ImageOptimizationRequest)?
      optimizer;
  @override
  State<NoteImageOptimizer> createState() => _NoteImageOptimizerState();
}

class _NoteImageOptimizerState extends State<NoteImageOptimizer> {
  int _quality = 70, _dimension = 1024, _generation = 0;
  int _sourceBytes = 0;
  bool _busy = false, _invalidSource = false;
  bool _inFlight = false, _closing = false;
  String? _error, _encoded;
  ImageOptimizationResult? _result;
  ImageOptimizationRequest? _pendingRequest;
  int? _pendingGeneration;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    try {
      _sourceBytes = NoteImageContent.decode(widget.sourceBase64).length;
      _schedule(immediate: true);
    } on FormatException {
      _invalidSource = true;
      _error =
          'This image is invalid or too large. Please select another image.';
    }
  }

  @override
  void dispose() {
    _discardPending();
    super.dispose();
  }

  void _discardPending() {
    _closing = true;
    _generation++;
    _debounce?.cancel();
    _debounce = null;
    _pendingRequest = null;
    _pendingGeneration = null;
  }

  void _cancel() {
    _discardPending();
    Navigator.of(context).pop();
  }

  void _schedule({bool immediate = false}) {
    if (_closing) return;
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    _pendingRequest = ImageOptimizationRequest(
        sourceBase64: widget.sourceBase64,
        quality: _quality,
        maxDimension: _dimension);
    _pendingGeneration = generation;
    _debounce = Timer(
        immediate ? Duration.zero : const Duration(milliseconds: 150), () {
      _debounce = null;
      _startPending();
    });
  }

  void _startPending() {
    if (!mounted || _closing || _inFlight || _pendingRequest == null) return;
    final request = _pendingRequest!;
    final generation = _pendingGeneration!;
    _pendingRequest = null;
    _pendingGeneration = null;
    _inFlight = true;
    unawaited(_optimize(request, generation));
  }

  Future<void> _optimize(
      ImageOptimizationRequest request, int generation) async {
    try {
      final result = await (widget.optimizer?.call(request) ??
          compute(optimizeNoteImage, request));
      if (!mounted || _closing || generation != _generation) return;
      final encoded = base64Encode(result.bytes);
      String? error;
      if (result.bytes.length > widget.maxBytes ||
          result.bytes.length > NoteImageContent.maxBytes ||
          widget.maxBytes <= 0) {
        error =
            'This result exceeds the image budget. Lower quality or choose a smaller maximum size.';
      } else {
        NoteImageContent.decode(encoded);
        error = widget.validate?.call(encoded);
      }
      setState(() {
        _result = result;
        _encoded = encoded;
        _error = error;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || _closing || generation != _generation) return;
      setState(() {
        _result = null;
        _encoded = null;
        _busy = false;
        _error =
            'This image could not be optimized. Please select another image.';
      });
    } finally {
      _inFlight = false;
      // Coalesce all changes made during this job into the newest request.
      // Respect a still-running debounce, and never launch after sheet close.
      if (mounted && !_closing && _debounce == null) _startPending();
    }
  }

  void _insert() {
    if (_closing || _busy || _error != null || _encoded == null) return;
    // Recheck the complete note at the final action, in case the owner supplied
    // a live budget validator whose result changed while this sheet was open.
    try {
      final error = widget.validate?.call(_encoded!);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      _discardPending();
      Navigator.of(context).pop(_encoded);
    } catch (_) {
      setState(() =>
          _error = 'The image cannot fit in this note. Try a smaller size.');
    }
  }

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardPending();
      },
      child: SafeArea(
        child: FractionallySizedBox(
          heightFactor: .92,
          child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Optimize image',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                        'Adjust this prepared image before attaching it. The picker has already compressed it and capped its dimensions at 1024 px. Higher quality cannot restore lost detail.'),
                    const SizedBox(height: 16),
                    if (result != null)
                      Image.memory(result.bytes,
                          height: 180,
                          fit: BoxFit.contain,
                          semanticLabel: 'Optimized image preview',
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const SizedBox(
                              height: 180,
                              child:
                                  Center(child: Text('Preview unavailable')))),
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator(
                              semanticsLabel: 'Optimizing image')),
                    Text(
                        'Prepared image: ${_kb(_sourceBytes)}${result == null ? '' : ' · ${result.sourceWidth} × ${result.sourceHeight} px'}'),
                    if (result != null)
                      Text(
                          'Output: ${result.width} × ${result.height} px · ${_kb(result.bytes.length)}'),
                    Text(
                        'Available image budget: ${_kb(widget.maxBytes.clamp(0, NoteImageContent.maxBytes))}'),
                    const SizedBox(height: 16),
                    Text('JPEG quality: $_quality%'),
                    Slider(
                        value: _quality.toDouble(),
                        min: 40,
                        max: 85,
                        divisions: 45,
                        label: '$_quality%',
                        semanticFormatterCallback: (value) =>
                            '${value.round()} percent JPEG quality',
                        onChanged: _invalidSource
                            ? null
                            : (value) {
                                _quality = value.round();
                                _schedule();
                              }),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: DropdownButtonFormField<int>(
                            key: const ValueKey('image-max-dimension'),
                            initialValue: _dimension,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Maximum dimension',
                                helperText:
                                    'Keeps proportions and never enlarges the image.',
                                helperMaxLines: 3,
                                border: OutlineInputBorder()),
                            items: [512, 768, 1024]
                                .map((size) => DropdownMenuItem<int>(
                                    value: size, child: Text('$size px')))
                                .toList(),
                            onChanged: _invalidSource
                                ? null
                                : (size) {
                                    if (size == null) return;
                                    _dimension = size;
                                    _schedule();
                                  })),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: AppColors.error)))),
                    const SizedBox(height: 20),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          OutlinedButton(
                              onPressed: _cancel,
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(80, 48)),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed:
                                  _busy || _error != null || _encoded == null
                                      ? null
                                      : _insert,
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size(112, 48),
                                  backgroundColor: AppColors.signal,
                                  foregroundColor: AppColors.paper),
                              child: const Text('Insert image')),
                        ]),
                  ])),
        ),
      ),
    );
  }
}
