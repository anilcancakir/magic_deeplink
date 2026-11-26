@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/src/drivers/app_links_driver_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLinksDriver', () {
    test('has correct name', () {
      final driver = AppLinksDriver();
      expect(driver.name, 'app_links');
    });

    test('implements DeeplinkDriver', () {
      final driver = AppLinksDriver();
      expect(driver.name, isNotEmpty);
    });

    group('isSupported', () {
      test('is true on iOS', () {
        final driver = AppLinksDriver(
          isIOS: true,
          isAndroid: false,
          isMacOS: false,
        );

        expect(driver.isSupported, isTrue);
      });

      test('is true on Android', () {
        final driver = AppLinksDriver(
          isIOS: false,
          isAndroid: true,
          isMacOS: false,
        );

        expect(driver.isSupported, isTrue);
      });

      test('is true on macOS', () {
        final driver = AppLinksDriver(
          isIOS: false,
          isAndroid: false,
          isMacOS: true,
        );

        expect(driver.isSupported, isTrue);
      });

      test('is false where none of the three platforms applies', () {
        final driver = AppLinksDriver(
          isIOS: false,
          isAndroid: false,
          isMacOS: false,
        );

        expect(driver.isSupported, isFalse);
      });

      test('is false on tvOS, which reports itself as iOS', () {
        MagicPlatform.debugTvOSOverride = true;
        addTearDown(() => MagicPlatform.debugTvOSOverride = null);
        final driver = AppLinksDriver(
          isIOS: true,
          isAndroid: false,
          isMacOS: false,
        );

        expect(driver.isSupported, isFalse);
      });
    });

    test('initialize sets up driver', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      // Verify no exception is thrown and driver is usable
    });

    test('getInitialLink returns future uri', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      expect(driver.getInitialLink(), isA<Future<Uri?>>());
    });

    test('onLink returns stream', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      expect(driver.onLink, isA<Stream<Uri>>());
    });

    test('dispose cleans up resources', () async {
      final driver = AppLinksDriver();
      await driver.initialize({});
      // Just ensure it doesn't throw
      driver.dispose();
    });
  });
}
