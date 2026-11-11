import 'package:hive_ce/hive_ce.dart';

/// The person's theme choice. Kept on this device only: it is cosmetic, never
/// synced, and signing out does not clear it (redesign ADR-004).
enum AppearanceMode { system, light, dark }

/// Where the choice is kept. Absent, unreadable or unknown values read as
/// [AppearanceMode.system].
abstract interface class AppearanceStore {
  AppearanceMode read();
  Future<void> write(AppearanceMode mode);
}

/// The device's store: its own Hive box, one key holding the mode's name. No
/// note, account or vault box is touched.
class HiveAppearanceStore implements AppearanceStore {
  HiveAppearanceStore(this._box);

  static const String boxName = 'appearanceBox';
  static const String key = 'themeMode';

  /// Opens the box. main() runs this once, before the first frame, and only
  /// once theme switching is enabled.
  static Future<HiveAppearanceStore> open() async =>
      HiveAppearanceStore(await Hive.openBox<dynamic>(boxName));

  final Box<dynamic> _box;

  @override
  AppearanceMode read() => decode(_box.get(key));

  @override
  Future<void> write(AppearanceMode mode) => _box.put(key, mode.name);

  /// The mode stored as [raw]; anything but a known name is System.
  static AppearanceMode decode(Object? raw) {
    for (final mode in AppearanceMode.values) {
      if (mode.name == raw) return mode;
    }
    return AppearanceMode.system;
  }
}

/// Holds the choice in memory: the app's store until startup opens the
/// device's one, and the store for tests and previews.
class MemoryAppearanceStore implements AppearanceStore {
  MemoryAppearanceStore([this.value = AppearanceMode.system]);

  AppearanceMode value;
  int writes = 0;

  /// When true, [write] fails, like a full or locked disk.
  bool failWrites = false;

  @override
  AppearanceMode read() => value;

  @override
  Future<void> write(AppearanceMode mode) async {
    writes++;
    if (failWrites) throw StateError('Appearance store unavailable');
    value = mode;
  }
}
