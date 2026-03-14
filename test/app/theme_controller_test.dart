import 'package:agripy/app/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'does not persist appearance when there is no authenticated user',
    () async {
      final controller = AppThemeController();

      await controller.syncForUser(null);
      await controller.setThemeMode(ThemeMode.dark);

      final restoredController = AppThemeController();
      await restoredController.syncForUser(null);
      expect(restoredController.themeMode, ThemeMode.light);
    },
  );

  test(
    'persists appearance per uid and isolates one user from another',
    () async {
      final controller = AppThemeController();

      await controller.syncForUser('user-a');
      await controller.setThemeMode(ThemeMode.dark);

      await controller.syncForUser('user-b');
      expect(controller.themeMode, ThemeMode.light);

      await controller.setThemeMode(ThemeMode.light);

      final restoredController = AppThemeController();

      await restoredController.syncForUser('user-a');
      expect(restoredController.themeMode, ThemeMode.dark);

      await restoredController.syncForUser('user-b');
      expect(restoredController.themeMode, ThemeMode.light);
    },
  );
}
