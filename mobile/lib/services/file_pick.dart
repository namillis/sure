import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the user picked: its name and size, with the bytes read only when
/// needed so an oversized file is rejected without loading it.
class PickedFileData {
  const PickedFileData({required this.name, required this.size, required this.read});

  /// In-memory file, for tests.
  factory PickedFileData.bytes(String name, List<int> bytes) => PickedFileData(
        name: name,
        size: bytes.length,
        read: () async => Uint8List.fromList(bytes),
      );

  final String name;
  final int size;
  final Future<Uint8List> Function() read;
}

/// Shows a picker limited to [extensions] (lowercase, no dots). Null when
/// the user cancels.
typedef FilePickFn = Future<PickedFileData?> Function(List<String> extensions);

/// The system document picker via `file_picker`.
Future<PickedFileData?> pickFileWithExtensions(List<String> extensions) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  final file = result?.files.singleOrNull;
  if (file == null) return null;
  final path = file.path;
  return PickedFileData(
    name: file.name,
    size: file.size,
    read: () async {
      if (file.bytes != null) return file.bytes!;
      if (path == null) throw const FileSystemException('No path for picked file');
      return File(path).readAsBytes();
    },
  );
}
