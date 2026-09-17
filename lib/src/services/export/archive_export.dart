import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:reaprime/src/util/temp_archive_files.dart';
import 'package:share_plus/share_plus.dart';

Uint8List zipFiles(Map<String, Uint8List> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<bool> saveArchiveBytes({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
}) async {
  final path = await FilePicker.saveFile(
    fileName: fileName,
    dialogTitle: dialogTitle,
    bytes: bytes,
  );
  return path != null;
}

enum DeliveryOutcome { saved, cancelled }

class ArchiveDeliveryException implements Exception {
  final String message;
  const ArchiveDeliveryException(this.message);

  @override
  String toString() => 'ArchiveDeliveryException: $message';
}

typedef ArchiveTarget = ({String outputPath, String finalPath});

const String _stagingPrefix = '.decent-export-';

Future<void> writeArchiveToDestination({
  required String destinationPath,
  required Future<void> Function(ArchiveTarget target) writeArchive,
}) async {
  final destination = File(destinationPath);
  final staging = await Directory(
    p.dirname(p.absolute(destinationPath)),
  ).createTemp(_stagingPrefix);
  final partial = File('${staging.path}${Platform.pathSeparator}archive');
  try {
    await writeArchive((outputPath: partial.path, finalPath: destinationPath));

    if (!Platform.isWindows || !await destination.exists()) {
      await partial.rename(destinationPath);
      return;
    }

    final backupPath = await _freeSiblingPath(destinationPath);
    await destination.rename(backupPath);
    try {
      await partial.rename(destinationPath);
    } catch (_) {
      try {
        await File(backupPath).rename(destinationPath);
      } catch (_) {
        throw ArchiveDeliveryException(
          'the previous file could not be replaced; it is kept at $backupPath',
        );
      }
      rethrow;
    }
    try {
      await File(backupPath).delete();
    } catch (_) {
      throw ArchiveDeliveryException(
        'the archive was saved, but the previous file remains at $backupPath',
      );
    }
  } finally {
    await _quietDeleteDirectory(staging);
  }
}

Future<void> _quietDeleteDirectory(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {}
}

Future<String> _freeSiblingPath(String base) async {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  var candidate = '$base.$stamp.bak';
  var counter = 0;
  while (await File(candidate).exists()) {
    counter++;
    candidate = '$base.$stamp.$counter.bak';
  }
  return candidate;
}

Future<DeliveryOutcome> deliverArchive({
  required String fileName,
  required Future<void> Function(ArchiveTarget target) writeArchive,
  String? dialogTitle,
}) async {
  if (Platform.isIOS || Platform.isAndroid) {
    final tempDir = await TempArchiveDir.create('reaprime-native-export-');
    final file = File(tempDir.filePath(fileName));
    try {
      await writeArchive((outputPath: file.path, finalPath: file.path));
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: 'Decent backup',
        ),
      );
      if (result.status == ShareResultStatus.dismissed) {
        await tempDir.dispose();
        return DeliveryOutcome.cancelled;
      }
      Timer(const Duration(minutes: 5), tempDir.dispose);
      return DeliveryOutcome.saved;
    } catch (_) {
      await tempDir.dispose();
      rethrow;
    }
  }

  final path = await FilePicker.saveFile(
    fileName: fileName,
    dialogTitle: dialogTitle,
  );
  if (path == null) return DeliveryOutcome.cancelled;
  await writeArchiveToDestination(
    destinationPath: path,
    writeArchive: writeArchive,
  );
  return DeliveryOutcome.saved;
}
