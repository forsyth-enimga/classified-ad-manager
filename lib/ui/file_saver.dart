import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Prompts for a save location and writes [bytes] there.
///
/// Returns the saved path (or a short description on Android), or null if the
/// user cancelled. On Android the picker writes the bytes itself (Storage
/// Access Framework, no storage permission needed); on desktop it only returns
/// the chosen path, so the file is written here.
Future<String?> saveBytes({
  required String fileName,
  required Uint8List bytes,
  required String extension,
  String dialogTitle = 'Choose where to save',
}) async {
  final isMobile = Platform.isAndroid || Platform.isIOS;
  final chosen = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: <String>[extension],
    bytes: isMobile ? bytes : null,
  );
  if (chosen == null) return null;
  if (isMobile) return chosen;

  var path = chosen;
  if (!path.toLowerCase().endsWith('.$extension')) path = '$path.$extension';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
