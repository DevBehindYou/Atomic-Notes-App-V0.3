import 'dart:convert';
import 'dart:typed_data';

import 'note.dart';
import 'note_document.dart';

/// Composable inline attributes. Offsets use Dart/Flutter UTF-16 positions.
abstract final class NoteTextStyle {
  static const bold = 1;
  static const italic = 2;
  static const underline = 4;
  static const strike = 8;
  static const heading = 16;
  static const all = 31;
}

class NoteStyleRun {
  const NoteStyleRun(this.start, this.end, this.flags);
  final int start;
  final int end;
  final int flags;

  List<int> toJson() => [start, end, flags];

  factory NoteStyleRun.fromJson(dynamic value) {
    if (value is! List || value.length != 3 || value.any((v) => v is! int)) {
      throw const FormatException('Invalid note formatting');
    }
    return NoteStyleRun(value[0] as int, value[1] as int, value[2] as int);
  }

  bool validFor(String text) =>
      start >= 0 &&
      end > start &&
      end <= text.length &&
      flags > 0 &&
      flags & ~NoteTextStyle.all == 0;

  @override
  bool operator ==(Object other) =>
      other is NoteStyleRun &&
      start == other.start &&
      end == other.end &&
      flags == other.flags;
  @override
  int get hashCode => Object.hash(start, end, flags);
}

/// JPEGs are embedded, never fetched by URL. Bounds also limit decode memory.
abstract final class NoteImageContent {
  // Keep the existing 60 KiB decoder allowance for saved legacy JPEGs.
  // New attachments use the picker's decimal 60,000-byte cap.
  static const maxBytes = 60 * 1024;
  static const maxDimension = 4096;
  static const maxPixels = 4 * 1024 * 1024;

  static Uint8List decode(String value) {
    if (value.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const FormatException('This image exceeds the supported size');
    }
    final bytes = base64Decode(value);
    if (base64Encode(bytes) != value ||
        bytes.length > maxBytes ||
        bytes.length < 12 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      throw const FormatException('Invalid JPEG image');
    }
    var offset = 2;
    while (offset < bytes.length - 2) {
      if (bytes[offset++] != 0xff) break;
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) break;
      final marker = bytes[offset++];
      if (marker == 0xda || marker == 0xd9) break;
      if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
      if (offset + 2 > bytes.length) break;
      final length = bytes[offset] * 256 + bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) break;
      if ([
        0xc0,
        0xc1,
        0xc2,
        0xc3,
        0xc5,
        0xc6,
        0xc7,
        0xc9,
        0xca,
        0xcb,
        0xcd,
        0xce,
        0xcf
      ].contains(marker)) {
        if (length < 8) break;
        final height = bytes[offset + 3] * 256 + bytes[offset + 4];
        final width = bytes[offset + 5] * 256 + bytes[offset + 6];
        if (width < 1 ||
            height < 1 ||
            width > maxDimension ||
            height > maxDimension ||
            width * height > maxPixels) {
          throw const FormatException('Image dimensions are too large');
        }
        return bytes;
      }
      offset += length;
    }
    throw const FormatException('Invalid JPEG dimensions');
  }
}

/// Preflight both cloud representations so enabling the vault remains possible.
/// No encryption or storage is performed here.
abstract final class NoteContentBudget {
  // Three new images at 60,000 bytes each. Match the Server note bounds;
  // request/batch limits remain separately enforced by the sync layer.
  static const maxImageBytes = 180000;
  static const maxBodyLength = 262144;
  static const maxPayloadLength = 393216;
  static const maxWireBytes = 400000;

  static String? errorFor(Note note) {
    if (note.title.length > 300) return 'Keep the title within 300 characters';
    if (note.body.length > maxBodyLength) {
      return 'This note exceeds the sync size limit';
    }
    final document = NoteDocument.fromNote(note);
    if (document.isReadOnly) return 'This note format cannot be edited';
    if (document.imageBytes > maxImageBytes) {
      return 'Images must total 180 KB or less';
    }
    final items =
        note.items.map((i) => {'text': i.text, 'done': i.done}).toList();
    final content = {
      'title': note.title,
      'body': note.body,
      'items': note.items.map((i) => i.toMap()).toList()
    };
    final clearBytes = utf8.encode(jsonEncode(content)).length;
    final payloadLength = 4 * ((clearBytes + 28 + 2) ~/ 3);
    if (payloadLength > maxPayloadLength) {
      return 'This note exceeds the encrypted sync size limit';
    }
    final row = {
      ...note.toRemote(''),
      'items': items,
      'enc_v': 0,
      'payload': null
    };
    // The Server refinement serializes the full parsed row plus encV.
    row.remove('user_id');
    final plainBytes = utf8.encode(jsonEncode({...row, 'encV': 0})).length;
    final sealed = {
      ...row,
      'title': '',
      'body': '',
      'items': <dynamic>[],
      'enc_v': 1,
      'payload': 'a' * payloadLength,
      'encV': 1
    };
    if (plainBytes > maxWireBytes ||
        utf8.encode(jsonEncode(sealed)).length > maxWireBytes) {
      return 'This note exceeds the sync size limit';
    }
    return null;
  }

  static void validate(Note note) {
    final error = errorFor(note);
    if (error != null) throw FormatException(error);
  }
}
