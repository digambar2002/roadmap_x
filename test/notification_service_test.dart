import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap_x/core/services/notification_service.dart';

void main() {
  test('windows disables local notifications', () {
    expect(NotificationService.supportsNotificationsFor(TargetPlatform.windows),
        isFalse);
    expect(NotificationService.supportsNotificationsFor(TargetPlatform.android),
        isTrue);
  });
}
