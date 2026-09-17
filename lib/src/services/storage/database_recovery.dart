import 'dart:io';

import 'package:reaprime/src/services/storage/app_directories.dart';

class ResetReport {
  final List<String> moved;
  final List<String> renameFailures;
  final List<String> leftovers;

  const ResetReport({
    this.moved = const [],
    this.renameFailures = const [],
    this.leftovers = const [],
  });

  bool get isClean => renameFailures.isEmpty && leftovers.isEmpty;
}

class DatabaseReset {
  DatabaseReset({required String driftFile, required String? hiveDir})
    : _driftFile = driftFile,
      _hiveDir = hiveDir;

  final String _driftFile;
  final String? _hiveDir;

  static Future<DatabaseReset> fromAppDirectories() async {
    return DatabaseReset(
      driftFile: await AppDirectories.driftFile,
      hiveDir: await AppDirectories.hive,
    );
  }

  Future<ResetReport> run() async {
    final targets = <String>[_driftFile, '$_driftFile-wal', '$_driftFile-shm'];
    final hiveDir = _hiveDir;
    if (hiveDir != null) targets.add(hiveDir);
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final moved = <String>[];
    final renameFailures = <String>[];
    final renamed = <({String original, String reset})>[];

    for (final target in targets) {
      final entity = FileSystemEntity.typeSync(target, followLinks: false);
      if (entity == FileSystemEntityType.notFound) continue;
      final resetPath = '$target.reset-$timestamp';
      try {
        if (entity == FileSystemEntityType.directory) {
          await Directory(target).rename(resetPath);
        } else {
          await File(target).rename(resetPath);
        }
        renamed.add((original: target, reset: resetPath));
      } catch (_) {
        renameFailures.add(target);
      }
    }

    final leftovers = <String>[];
    for (final item in renamed) {
      try {
        if (FileSystemEntity.typeSync(item.reset, followLinks: false) ==
            FileSystemEntityType.directory) {
          await Directory(item.reset).delete(recursive: true);
        } else {
          await File(item.reset).delete();
        }
        moved.add(item.original);
      } catch (_) {
        leftovers.add(item.reset);
      }
    }

    return ResetReport(
      moved: List.unmodifiable(moved),
      renameFailures: List.unmodifiable(renameFailures),
      leftovers: List.unmodifiable(leftovers),
    );
  }
}
