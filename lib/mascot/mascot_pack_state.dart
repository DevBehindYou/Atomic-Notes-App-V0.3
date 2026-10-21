import 'package:flutter/foundation.dart';

import 'mascot_asset_resolver.dart';

enum MascotPackStatus {
  included,
  absent,
  previewed,
  downloading,
  verifying,
  installed,
  failed,
}

@immutable
class MascotPackState {
  const MascotPackState({
    required this.id,
    required this.status,
    this.received = 0,
    this.total = 0,
    this.errorCode,
    this.previewBytes,
  });

  final String id;
  final MascotPackStatus status;
  final int received, total;
  final String? errorCode;
  final Uint8List? previewBytes;

  bool get isReady =>
      status == MascotPackStatus.included ||
      status == MascotPackStatus.installed;
  double get progress => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

abstract class MascotPackSource extends ChangeNotifier
    implements MascotAssetResolver {
  MascotPackState stateFor(String id);
  Future<void> initialize();
  Future<void> preview(String id);
  Future<void> downloadAndInstall(String id);
  void cancel();
  Future<void> remove(String id, {required String selectedId});
  Future<void> close();
}
