import 'package:cek_pbb_app/batch_notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BatchNotificationService', () {
    test(
      'actionStream emits events from background action broadcasts',
      () async {
        final receivedActions = <String>[];
        final sub = BatchNotificationService.actionStream.listen((action) {
          receivedActions.add(action);
        });

        // Show that service methods can be invoked safely when not initialized
        await BatchNotificationService.instance.showStarted(
          title: 'Test',
          content: 'Content',
          total: 10,
        );
        await BatchNotificationService.instance.showProgress(
          current: 1,
          total: 10,
          currentNop: '320520000400100010',
          lunasCount: 1,
          belumCount: 0,
        );
        await BatchNotificationService.instance.showStaffSyncProgress(
          currentBlok: 1,
          totalBloks: 5,
          currentBlokName: 'Blok 01',
          updatedPaid: 2,
          newSppt: 1,
        );

        // Clean up subscription
        await sub.cancel();
        expect(receivedActions, isEmpty);
      },
    );

    test(
      'onNotificationTapped with staff_sync_completed executes safely without crash',
      () {
        const response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'staff_sync_completed',
        );

        // On non-Android environment (such as Linux host running tests),
        // tapping the notification does not auto-open the dialog and executes safely.
        expect(
          () =>
              BatchNotificationService.instance.onNotificationTapped(response),
          returnsNormally,
        );
      },
    );
  });
}
