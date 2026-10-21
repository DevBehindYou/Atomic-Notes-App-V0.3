import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'flutter_gif_frame_source.dart';
import 'mascot_asset_resolver.dart';
import 'mascot_catalog.dart';
import 'mascot_frame_source.dart';
import 'mascot_playback_controller.dart';

/// A single isolated player. Callers supply route visibility explicitly.
class MascotView extends StatefulWidget {
  const MascotView(
      {super.key,
      required this.mascot,
      required this.resolver,
      this.animationsEnabled = true,
      this.routeVisible = true,
      this.interactive = true,
      this.size = 96,
      this.onAdvance,
      this.semanticActionLabel = 'change animation',
      this.frameSource});
  final MascotDefinition mascot;
  final MascotAssetResolver resolver;
  final bool animationsEnabled, routeVisible, interactive;
  final double size;
  final VoidCallback? onAdvance;
  final String semanticActionLabel;
  final MascotFrameSource? frameSource;
  @override
  State<MascotView> createState() => _MascotViewState();
}

class _MascotViewState extends State<MascotView> with WidgetsBindingObserver {
  late MascotPlaybackController _player;
  final Set<OwnedMascotFrame> _retired = {};
  bool _resumed = true, _focused = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumed = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _create();
  }

  void _create() {
    _player = MascotPlaybackController(
        mascot: widget.mascot,
        source: widget.frameSource ?? FlutterGifFrameSource(widget.resolver),
        targetPhysicalPixels: widget.size.round().clamp(1, 480),
        releaseFrame: _release);
  }

  void _release(OwnedMascotFrame frame) {
    _retired.add(frame);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_retired.remove(frame)) frame.dispose();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _gate() {
    final visible =
        widget.routeVisible && _resumed && TickerMode.valuesOf(context).enabled;
    _player.setPlaybackAllowed(
        widget.animationsEnabled &&
            !MediaQuery.disableAnimationsOf(context) &&
            visible,
        visible: visible);
    _player.setTargetPhysicalPixels(
        (widget.size * MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(1, 480));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gate();
  }

  @override
  void didUpdateWidget(covariant MascotView old) {
    super.didUpdateWidget(old);
    if (old.resolver != widget.resolver ||
        old.frameSource != widget.frameSource) {
      _player.dispose();
      _create();
    } else {
      _player.setMascot(widget.mascot);
    }
    _gate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _gate();
  }

  void _advance() {
    _player.advanceFromUser();
    widget.onAdvance?.call();
  }

  void _retry() {
    _player.retry();
    widget.onAdvance?.call();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    for (final frame in _retired) {
      frame.dispose();
    }
    _retired.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _player, builder: (context, _) => _buildPlayer(context));
  Widget _buildPlayer(BuildContext context) {
    if (_player.state == MascotPlaybackState.failed) {
      return SizedBox(
          width: widget.size < 48 ? 48 : widget.size,
          height: widget.size < 48 ? 48 : widget.size,
          child: TextButton(
              onPressed: _retry,
              child: Text('${widget.mascot.displayName} unavailable. Retry',
                  semanticsLabel: widget.onAdvance == null
                      ? null
                      : '${widget.mascot.displayName} unavailable. Retry and ${widget.semanticActionLabel}')));
    }
    final label = '${widget.mascot.displayName}, ${widget.semanticActionLabel}';
    final art = RepaintBoundary(
        child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
                animation: _player,
                builder: (context, _) {
                  if (_player.state == MascotPlaybackState.failed) {
                    return Center(
                        child: TextButton(
                            onPressed: _retry,
                            child: const Text('Mascot unavailable. Retry')));
                  }
                  return ColoredBox(
                      color: const Color(0xfff4f4f2),
                      child: _player.frame == null
                          ? const Center(child: Text('Loading mascot'))
                          : RawImage(
                              image: _player.frame!.image,
                              fit: BoxFit.contain));
                })));
    if (!widget.interactive) {
      return Semantics(
          label: widget.mascot.displayName,
          image: true,
          child: ExcludeSemantics(child: art));
    }
    return Semantics(
        label: label,
        button: true,
        onTap: _advance,
        child: FocusableActionDetector(
            onShowFocusHighlight: (value) => setState(() => _focused = value),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent()
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                _advance();
                return null;
              })
            },
            child: GestureDetector(
                onTap: _advance,
                behavior: HitTestBehavior.opaque,
                child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    decoration: BoxDecoration(
                        border: Border.all(
                            color: _focused
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2)),
                    child: ExcludeSemantics(child: art)))));
  }
}
