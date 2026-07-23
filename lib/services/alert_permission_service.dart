import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlertPermissionService {
  AlertPermissionService._();

  static final AlertPermissionService instance =
  AlertPermissionService._();

  static const String _cameraPermissionAskedKey =
      'camera_permission_asked_for_alert_flashlight';

  /// Call once during onboarding or after the first successful login.
  ///
  /// Android displays the Camera permission dialog only if permission has
  /// not already been granted or permanently denied.
  Future<bool> requestCameraForAlertFlashlight() async {
    final currentStatus = await Permission.camera.status;

    if (currentStatus.isGranted) {
      return true;
    }

    final preferences = await SharedPreferences.getInstance();
    final hasAskedBefore =
        preferences.getBool(_cameraPermissionAskedKey) ?? false;

    /*
     * Do not repeatedly show permission prompts after the user declined.
     * They can enable it later from Settings.
     */
    if (hasAskedBefore) {
      return false;
    }

    await preferences.setBool(_cameraPermissionAskedKey, true);

    final requestedStatus = await Permission.camera.request();

    if (kDebugMode) {
      debugPrint(
        '📷 Camera permission for medication-alert flashlight: '
            '${requestedStatus.name}',
      );
    }

    return requestedStatus.isGranted;
  }


  /// This does not show a popup. It only checks whether the user granted
  /// Camera permission previously.
  Future<bool> canUseAlertFlashlight() async {
    return Permission.camera.isGranted;
  }

  /// Opens Android Settings if the user wants to enable the permission later.
  Future<bool> openAppSettings() {
    return openAppSettings();
  }
}