import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:reaprime/src/skin_feature/skin_camera_controls.dart';
import 'package:reaprime/src/skin_feature/skin_camera_permission.dart';

class SkinCameraWebViewAccess with WidgetsBindingObserver {
  late final SkinCameraPermission _permission;
  bool _disposed = false;

  SkinCameraWebViewAccess({
    required BuildContext? Function() context,
    required SkinCameraTarget? Function() currentTarget,
    SkinCameraConsentStore store = const SkinCameraConsentStore(),
    Future<bool> Function()? requestAndroidCamera,
  }) {
    _permission = SkinCameraPermission(
      store: store,
      currentTarget: currentTarget,
      isActive: () => !_disposed && _isActive(context()),
      prompt: (name) async {
        final current = context();
        if (current == null || !current.mounted) return null;
        return promptForSkinCamera(current, name);
      },
      requestAndroidCamera:
          requestAndroidCamera ??
          () async => (await permissions.Permission.camera.request()).isGranted,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  static bool _isActive(BuildContext? context) {
    final state = WidgetsBinding.instance.lifecycleState;
    return context != null &&
        context.mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
  }

  void invalidate() => _permission.invalidate();

  void dispose() {
    _disposed = true;
    invalidate();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      invalidate();
    }
  }

  Future<PermissionResponse> onPermissionRequest(
    InAppWebViewController controller,
    PermissionRequest request,
  ) => _permission.handle(request, readTopLevel: controller.getUrl);

  void onPermissionRequestCanceled(
    InAppWebViewController controller,
    PermissionRequest request,
  ) => invalidate();

  Future<ShowFileChooserResponse?> onShowFileChooser(
    InAppWebViewController controller,
    ShowFileChooserRequest request,
  ) async {
    if (!request.isCaptureEnabled) return null;
    final imageOnly =
        request.acceptTypes.isNotEmpty &&
        request.acceptTypes.every(
          (type) => type.toLowerCase().startsWith('image/'),
        );
    if (imageOnly &&
        await _permission.capture(readTopLevel: controller.getUrl)) {
      return null;
    }
    return ShowFileChooserResponse(handledByClient: true);
  }
}
