# Local mascot preferences

The version 1 `mascot_preferences/config` Hive record contains only a stable character ID and animation boolean. It is device-wide, independent of sign-in, notes and Energy. Missing/malformed records use Cubie defaults; future schemas remain read-only and are preserved at both the Cubit and storage boundary.

Selection and motion have independent startup intent. Explicit choices made while a storage read is pending override only the touched field; untouched fields retain their saved values. Writes serialize and coalesce toward the latest desired state. Failure leaves the visible choice marked unsaved and supports retry; failed reads cannot silently overwrite unknown storage.

Validation: 20 focused preference/store/Cubit tests passed, including five regression cases added after independent review (explicit defaults, field merging and future-schema protection). Targeted analyzer passed with fatal infos. Device restart acceptance and UI integration remain separate work.
