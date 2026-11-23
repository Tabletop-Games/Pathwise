import 'dart:io';
import 'dart:typed_data';

import '../model/expedition.dart';

/// A page holds 256 fixed-width records. Reads never traverse other pages.
final class TrailRecordStorage {
  TrailRecordStorage(this.directory);

  final Directory directory;
  static const _recordsPerPage = 256;
  static const _recordBytes = 10;

  ({File page, int offset}) _location(Trail trail) {
    final index = trail.number - 1;
    return (
      page: File('${directory.path}/${index ~/ _recordsPerPage}.bin'),
      offset: (index % _recordsPerPage) * _recordBytes,
    );
  }

  Future<ByteData> _read(File page) async {
    if (!await page.exists()) {
      return ByteData(_recordsPerPage * _recordBytes);
    }
    final bytes = await page.readAsBytes();
    if (bytes.length != _recordsPerPage * _recordBytes) {
      throw const FormatException('Invalid trail record page');
    }
    return ByteData.sublistView(bytes);
  }

  TrailRecord? _record(ByteData bytes, int offset) {
    final deepest = bytes.getUint8(offset);
    if (deepest == 0) return null;
    final fastest = bytes.getInt64(offset + 2);
    return TrailRecord(
      deepest: deepest,
      marks: bytes.getUint8(offset + 1),
      fastest: fastest == 0 ? null : fastest - 1,
    );
  }

  Future<TrailRecord?> read(Trail trail) async {
    final (:page, :offset) = _location(trail);
    return _record(await _read(page), offset);
  }

  /// Index files contain only bests. Merging maximum depth and marks and
  /// minimum time makes a write safe to replay after interruption.
  Future<TrailRecord> merge(Trail trail, TrailRecord candidate) async {
    final (:page, :offset) = _location(trail);
    final bytes = await _read(page);
    final record = _record(bytes, offset) ?? TrailRecord();
    record.merge(candidate);
    bytes.setUint8(offset, record.deepest);
    bytes.setUint8(offset + 1, record.marks);
    bytes.setInt64(
      offset + 2,
      record.fastest == null ? 0 : record.fastest! + 1,
    );
    await directory.create(recursive: true);
    final temporary = File('${page.path}.tmp');
    await temporary.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    await temporary.rename(page.path);
    return record;
  }
}
