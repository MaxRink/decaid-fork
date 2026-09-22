import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/skin_feature/skin_camera_controls.dart';
import 'package:reaprime/src/skin_feature/skin_camera_permission.dart';
import 'package:reaprime/src/skin_feature/skin_camera_webview_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraTestController implements InAppWebViewController {
  @override
  Future<WebUri?> getUrl() async => WebUri('http://localhost:25001/camera');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const store = SkinCameraConsentStore();
  const target = SkinCameraTarget(id: 'first', name: 'First', port: 25001);
  final controller = CameraTestController();
  final request = PermissionRequest(
    origin: WebUri('http://localhost:25001'),
    resources: [PermissionResourceType.CAMERA],
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('native consent precedes Android permission', (tester) async {
    late BuildContext context;
    var osRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    final access = SkinCameraWebViewAccess(
      context: () => context,
      currentTarget: () => target,
      requestAndroidCamera: () async {
        osRequests++;
        return true;
      },
    );
    addTearDown(access.dispose);
    final result = access.onPermissionRequest(controller, request);
    await tester.pumpAndSettle();
    expect(
      find.text('Allow "First" to receive images from your camera?'),
      findsOneWidget,
    );
    expect(osRequests, 0);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect((await result).action, PermissionResponseAction.GRANT);
    expect(osRequests, 1);
  });

  testWidgets('timed-out consent denies without persisting', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = promptForSkinCamera(context, target.name);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(await store.read(target.id), isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final cancel in ['background', 'dispose', 'cancel']) {
    testWidgets('$cancel invalidates a pending Android grant', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold();
            },
          ),
        ),
      );
      await store.write(target.id, true);
      final osResult = Completer<bool>();
      final access = SkinCameraWebViewAccess(
        context: () => context,
        currentTarget: () => target,
        requestAndroidCamera: () => osResult.future,
      );
      final result = access.onPermissionRequest(controller, request);
      await tester.pumpAndSettle();
      switch (cancel) {
        case 'background':
          access.didChangeAppLifecycleState(AppLifecycleState.paused);
        case 'dispose':
          access.dispose();
        case 'cancel':
          access.onPermissionRequestCanceled(controller, request);
      }
      osResult.complete(true);
      await tester.pumpAndSettle();
      expect((await result).action, PermissionResponseAction.DENY);
      access.dispose();
    });
  }

  testWidgets('explicit image capture confirms and gallery delegates', (
    tester,
  ) async {
    late BuildContext context;
    var osRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    await store.write(target.id, true);
    final access = SkinCameraWebViewAccess(
      context: () => context,
      currentTarget: () => target,
      requestAndroidCamera: () async {
        osRequests++;
        return true;
      },
    );
    addTearDown(access.dispose);
    ShowFileChooserRequest chooser(bool capture, List<String> types) =>
        ShowFileChooserRequest(
          acceptTypes: types,
          isCaptureEnabled: capture,
          mode: ShowFileChooserRequestMode.OPEN,
        );
    expect(
      await access.onShowFileChooser(controller, chooser(false, ['image/*'])),
      isNull,
    );
    expect(osRequests, 0);
    expect(
      (await access.onShowFileChooser(
        controller,
        chooser(true, ['video/*']),
      ))?.handledByClient,
      isTrue,
    );
    final denied = access.onShowFileChooser(
      controller,
      chooser(true, ['image/*']),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    expect((await denied)?.handledByClient, isTrue);
    expect(osRequests, 0);
    final allowed = access.onShowFileChooser(
      controller,
      chooser(true, ['image/jpeg']),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(await allowed, isNull);
    expect(osRequests, 1);
  });

  testWidgets('native setting can revoke and reset per skin', (tester) async {
    await store.write(target.id, true);
    await store.write('other', true);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkinCameraConsentSetting(skinId: 'first')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deny').last);
    await tester.pumpAndSettle();
    expect(await store.read(target.id), isFalse);
    expect(await store.read('other'), isTrue);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask').last);
    await tester.pumpAndSettle();
    expect(await store.read(target.id), isNull);
  });

  testWidgets('corrupt consent displays an error and disables changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'skinCameraConsent.first': 'invalid',
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SkinCameraConsentSetting(skinId: 'first')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Camera permission could not be loaded.'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .onChanged,
      isNull,
    );
  });
}
