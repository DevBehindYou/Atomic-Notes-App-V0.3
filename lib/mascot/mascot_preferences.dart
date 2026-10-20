import 'mascot_catalog.dart';

class MascotPreferences {
  final int schemaVersion;
  final String selectedId;
  final bool animationsEnabled;
  MascotPreferences(
      {this.schemaVersion = 1,
      required this.selectedId,
      this.animationsEnabled = true}) {
    if (schemaVersion != 1 || MascotCatalog.findById(selectedId) == null) {
      throw ArgumentError('Invalid mascot preferences');
    }
  }
  factory MascotPreferences.defaults() =>
      MascotPreferences(selectedId: MascotCatalog.defaultId);
  MascotPreferences copyWith({String? selectedId, bool? animationsEnabled}) =>
      MascotPreferences(
          selectedId: selectedId ?? this.selectedId,
          animationsEnabled: animationsEnabled ?? this.animationsEnabled);
  Map<String, Object> toMap() => {
        'schemaVersion': schemaVersion,
        'selectedId': selectedId,
        'animationsEnabled': animationsEnabled
      };
  @override
  bool operator ==(Object other) =>
      other is MascotPreferences &&
      other.schemaVersion == schemaVersion &&
      other.selectedId == selectedId &&
      other.animationsEnabled == animationsEnabled;
  @override
  int get hashCode => Object.hash(schemaVersion, selectedId, animationsEnabled);
}

enum MascotPreferenceReadKind { missing, valid, malformed, futureVersion }

class MascotPreferenceRead {
  final MascotPreferenceReadKind kind;
  final MascotPreferences? value;
  final String? diagnosticCode;
  const MascotPreferenceRead._(this.kind, this.value, this.diagnosticCode);
  const MascotPreferenceRead.missing()
      : this._(MascotPreferenceReadKind.missing, null, null);
  const MascotPreferenceRead.valid(MascotPreferences value)
      : this._(MascotPreferenceReadKind.valid, value, null);
  const MascotPreferenceRead.malformed()
      : this._(
            MascotPreferenceReadKind.malformed, null, 'malformed_preferences');
  const MascotPreferenceRead.futureVersion()
      : this._(MascotPreferenceReadKind.futureVersion, null, 'future_schema');
}

abstract interface class MascotPreferencesStore {
  Future<MascotPreferenceRead> read();
  Future<void> write(MascotPreferences value);
}

class MascotPreferencesCodec {
  static MascotPreferenceRead decode(Object? raw) {
    if (raw == null) return const MascotPreferenceRead.missing();
    if (raw is! Map) return const MascotPreferenceRead.malformed();
    final version = raw['schemaVersion'];
    if (version is int && version > 1) {
      return const MascotPreferenceRead.futureVersion();
    }
    final id = raw['selectedId'];
    final motion = raw['animationsEnabled'];
    if (version is! int ||
        version != 1 ||
        id is! String ||
        MascotCatalog.findById(id) == null ||
        motion is! bool) {
      return const MascotPreferenceRead.malformed();
    }
    return MascotPreferenceRead.valid(
        MascotPreferences(selectedId: id, animationsEnabled: motion));
  }
}
