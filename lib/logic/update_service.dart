import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update_flutter/in_app_update_flutter.dart';

enum AppUpdateOutcome {
  unsupported,
  upToDate,
  downloaded,
  started,
  notCompleted,
  unavailable,
}

/// Thin wrapper around Google Play In-App Updates so Settings views do not
/// directly depend on the plugin package.
class UpdateService {
  const UpdateService();

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<AppUpdateOutcome> checkAndApply() async {
    if (!supported) return AppUpdateOutcome.unsupported;
    try {
      final updater = InAppUpdateFlutter();
      final info = await updater.checkUpdateAndroid();
      if (info.installStatus == InstallStatusAndroid.downloaded) {
        await updater.completeUpdateAndroid();
        return AppUpdateOutcome.downloaded;
      }
      if (info.updateAvailability ==
              UpdateAvailabilityAndroid.updateAvailable &&
          info.isImmediateUpdateAllowed) {
        final result = await updater.startImmediateUpdateAndroid();
        return result == UpdateResultAndroid.success
            ? AppUpdateOutcome.started
            : AppUpdateOutcome.notCompleted;
      }
      return AppUpdateOutcome.upToDate;
    } on PlatformException {
      return AppUpdateOutcome.unavailable;
    } on MissingPluginException {
      return AppUpdateOutcome.unavailable;
    } catch (_) {
      return AppUpdateOutcome.unavailable;
    }
  }
}
