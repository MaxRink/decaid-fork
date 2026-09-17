import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/services/export/archive_export.dart';
import 'package:reaprime/src/services/export/support_package.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('archive-delivery-');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('stages outside the destination and renames on success', () async {
    final destination = File('${tempDir.path}/archive.zip');
    ArchiveTarget? seen;

    await writeArchiveToDestination(
      destinationPath: destination.path,
      writeArchive: (target) async {
        seen = target;
        await File(target.outputPath).writeAsString('archive');
      },
    );

    expect(seen!.finalPath, destination.path);
    expect(seen!.outputPath, isNot(destination.path));
    expect(await destination.readAsString(), 'archive');
    expect(await File(seen!.outputPath).exists(), isFalse);
    expect(tempDir.listSync().map((entry) => entry.path), [destination.path]);
  });

  test('replaces a pre-existing destination', () async {
    final destination = File('${tempDir.path}/archive.zip');
    await destination.writeAsString('old');

    await writeArchiveToDestination(
      destinationPath: destination.path,
      writeArchive: (target) => File(target.outputPath).writeAsString('new'),
    );

    expect(await destination.readAsString(), 'new');
    expect(tempDir.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
    expect(tempDir.listSync().where((e) => e.path.endsWith('.bak')), isEmpty);
  });

  test('preserves the destination and removes partial on failure', () async {
    final destination = File('${tempDir.path}/archive.zip');
    await destination.writeAsString('old');

    await expectLater(
      writeArchiveToDestination(
        destinationPath: destination.path,
        writeArchive: (target) async {
          await File(target.outputPath).writeAsString('partial');
          throw StateError('failed');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(await destination.readAsString(), 'old');
    expect(await File('${destination.path}.part').exists(), isFalse);
    expect(tempDir.listSync().where((e) => e.path.endsWith('.bak')), isEmpty);
  });

  test('a pre-existing partial symlink cannot truncate a source', () async {
    final source = File('${tempDir.path}/streamline_bridge.sqlite')
      ..writeAsStringSync('SOURCE');
    final destination = File('${tempDir.path}/archive.zip');
    await Link('${destination.path}.part').create(source.path);

    await writeArchiveToDestination(
      destinationPath: destination.path,
      writeArchive: (target) =>
          File(target.outputPath).writeAsString('archive'),
    );

    expect(await source.readAsString(), 'SOURCE');
    expect(await destination.readAsString(), 'archive');
  });

  test('a source file chosen as destination is not destroyed', () async {
    final drift = File('${tempDir.path}/streamline_bridge.sqlite')
      ..writeAsBytesSync([1, 2, 3]);

    await expectLater(
      writeArchiveToDestination(
        destinationPath: drift.path,
        writeArchive: (target) => buildSupportPackage(
          outputPath: target.outputPath,
          finalDestinationPath: target.finalPath,
          sources: SupportPackageSources(
            driftFile: drift.path,
            hiveDir: '${tempDir.path}/store',
            logDir: tempDir.path,
            appVersion: '1.2.3',
          ),
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(await drift.readAsBytes(), [1, 2, 3]);
  });
}
