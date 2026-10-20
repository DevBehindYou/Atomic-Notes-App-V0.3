import 'package:hive_ce/hive.dart';
import 'mascot_preferences.dart';

/// Device cosmetic storage only. The opener may choose a separate native root.
class HiveMascotPreferencesStore implements MascotPreferencesStore {
  static const boxName = 'mascot_preferences';
  static const configKey = 'config';
  final Future<Box<dynamic>> Function()? _opener;
  final bool _ownsBox;
  Future<Box<dynamic>>? _box;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;
  HiveMascotPreferencesStore.box(Box<dynamic> box)
      : _opener = null,
        _ownsBox = false,
        _box = Future.value(box);
  HiveMascotPreferencesStore.openBox(Future<Box<dynamic>> Function() opener)
      : _opener = opener,
        _ownsBox = true;
  Future<Box<dynamic>> _getBox() {
    if (_closed) throw StateError('Mascot store closed');
    return _box ??= _open();
  }

  Future<Box<dynamic>> _open() async {
    try {
      return await _opener!();
    } catch (_) {
      _box = null;
      rethrow;
    }
  }

  @override
  Future<MascotPreferenceRead> read() async {
    if (_closing != null || _closed) throw StateError('Mascot store closed');
    return MascotPreferencesCodec.decode((await _getBox()).get(configKey));
  }

  @override
  Future<void> write(MascotPreferences value) {
    // Validate again at the storage boundary before touching the record.
    if (MascotPreferencesCodec.decode(value.toMap()).kind !=
        MascotPreferenceReadKind.valid) {
      throw ArgumentError('Invalid mascot preferences');
    }
    if (_closing != null || _closed) throw StateError('Mascot store closed');
    final result = _tail.then((_) async {
      final box = await _getBox();
      if (MascotPreferencesCodec.decode(box.get(configKey)).kind ==
          MascotPreferenceReadKind.futureVersion) {
        throw StateError('Future mascot preferences schema');
      }
      await box.put(configKey, value.toMap());
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _tail;
    _closed = true;
    if (_ownsBox && _box != null) await (await _box!).close();
  }
}
