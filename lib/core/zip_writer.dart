import 'dart:convert';
import 'dart:typed_data';

/// Minimal ZIP writer (stored / no compression). The exports are tiny text
/// files, so this avoids an extra package dependency.
class ZipEntry {
  ZipEntry(this.name, this.data);
  final String name;
  final Uint8List data;
}

final List<int> _crcTable = () {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}();

int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List buildZip(List<ZipEntry> entries, {DateTime? modified}) {
  final now = modified ?? DateTime.now();
  final dosTime = (now.hour << 11) | (now.minute << 5) | (now.second ~/ 2);
  final year = now.year < 1980 ? 1980 : now.year;
  final dosDate = ((year - 1980) << 9) | (now.month << 5) | now.day;

  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;

  void u16(BytesBuilder b, int v) =>
      b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(BytesBuilder b, int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());

  for (final e in entries) {
    final name = utf8.encode(e.name);
    final crc = crc32(e.data);

    // Local file header
    u32(out, 0x04034b50);
    u16(out, 20); // version needed
    u16(out, 0x0800); // flags: UTF-8 names
    u16(out, 0); // method: stored
    u16(out, dosTime);
    u16(out, dosDate);
    u32(out, crc);
    u32(out, e.data.length);
    u32(out, e.data.length);
    u16(out, name.length);
    u16(out, 0); // extra length
    out.add(name);
    out.add(e.data);

    // Central directory header
    u32(central, 0x02014b50);
    u16(central, 20); // version made by
    u16(central, 20); // version needed
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, dosTime);
    u16(central, dosDate);
    u32(central, crc);
    u32(central, e.data.length);
    u32(central, e.data.length);
    u16(central, name.length);
    u16(central, 0); // extra
    u16(central, 0); // comment
    u16(central, 0); // disk number
    u16(central, 0); // internal attrs
    u32(central, 0); // external attrs
    u32(central, offset);
    central.add(name);

    offset += 30 + name.length + e.data.length;
  }

  final centralBytes = central.toBytes();
  final centralOffset = offset;
  out.add(centralBytes);

  // End of central directory
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, entries.length);
  u16(out, entries.length);
  u32(out, centralBytes.length);
  u32(out, centralOffset);
  u16(out, 0);
  return out.toBytes();
}
