# Drivers

A driver turns a platform's link mechanism into a uniform `Stream<Uri>` for `DeeplinkManager`, and `AppLinksDriver` is the one that ships with the package.

- [Quick Reference](#quick-reference)
- [The DeeplinkDriver Contract](#the-deeplink-driver-contract)
- [AppLinksDriver](#applinksdriver)
    - [Platform Support](#platform-support)
    - [Web, in detail](#web)
- [Custom Drivers](#custom-drivers)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Platform | `AppLinksDriver.isSupported` | Mechanism |
|:---------|:-----------------------------|:----------|
| Android | `true` | App Links (HTTPS intent filter) |
| iOS | `true` | Universal Links (`apple-app-site-association`) |
| macOS | `true` | Universal Links; the install and the doctor do not cover macOS |
| Web | `false` | None; see [Web, in detail](#web) |
| Windows, Linux | `false` | None |

`DeeplinkServiceProvider` creates `AppLinksDriver` when `deeplink.driver` is `'app_links'`, and wires it only when `isSupported` is `true`. You rarely touch the driver directly.

<a name="the-deeplink-driver-contract"></a>
## The DeeplinkDriver Contract

Every driver extends `DeeplinkDriver`:

```dart
abstract class DeeplinkDriver {
  String get name;
  bool get isSupported;
  Future<void> initialize(Map<String, dynamic> config);
  Future<Uri?> getInitialLink();
  Stream<Uri> get onLink;
  void dispose();
}
```

| Member | Contract |
|:-------|:---------|
| `name` | A stable identifier. `AppLinksDriver` answers `'app_links'`. |
| `isSupported` | Whether the driver can run on this platform. Synchronous. The provider skips `initialize`, the manager and the subscription for a driver of its own that answers `false`. |
| `initialize` | Called once by the provider with the whole `deeplink` config map, before `onLink` is read. |
| `getInitialLink` | The URI that cold-started the app, or `null`. Called by `DeeplinkManager.getInitialLink()`, which caches the answer; the provider does not call it. Return `null` on failure rather than throwing. |
| `onLink` | A stream of every URI received while the app runs. Return `Stream.empty()` where the platform has none. |
| `dispose` | Releases what the driver holds. `DeeplinkServiceProvider.dispose()` calls it for a driver the provider created. |

<a name="applinksdriver"></a>
## AppLinksDriver

The exported `AppLinksDriver` is a conditional-export barrel over platform arms chosen at compile time:

```dart
export 'app_links_driver_stub.dart'
    if (dart.library.js_interop) 'app_links_driver_web.dart'
    if (dart.library.io) 'app_links_driver_io.dart';
```

The `dart:io` arm wraps the [`app_links`](https://pub.dev/packages/app_links) package and is the only arm that talks to a platform channel. It answers `isSupported` from `Platform.isAndroid || Platform.isIOS || Platform.isMacOS`, creates its `AppLinks` instance in `initialize`, and takes `getInitialLink()` and `onLink` from `app_links`. The cold-start link is also the first emission of `onLink`.

The web arm and the stub arm, which no shipped build target resolves to, are inert: `isSupported` is `false`, `getInitialLink()` returns `null`, `onLink` is `Stream<Uri>.empty()`, and `initialize` and `dispose` do nothing.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

final AppLinksDriver driver = AppLinksDriver();
await driver.initialize({});

final Uri? initial = await driver.getInitialLink();
driver.onLink.listen((Uri uri) {
  // Links received while the app runs.
});
```

<a name="platform-support"></a>
### Platform Support

On Android, iOS and macOS the barrel resolves to the `dart:io` arm. On Windows and Linux it resolves to the same arm, whose `Platform` check answers `false`, so the provider wires nothing there either. Native setup per platform is in [Installation](../getting-started/installation.md#platform-setup).

<a name="web"></a>
### Web, in detail

"No driver" is not "no deep links". The web has routes into a screen that this package owns no driver for, so both are easy to leave half configured.

**A tapped push, with the tab open, reaches the handler chain.** The push bridge is wired outside the `isSupported` gate in `DeeplinkServiceProvider.boot()`, so it exists on the web as on mobile: `OneSignalWebDriver` publishes the click, the notification manager republishes it, and `OneSignalDeeplinkHandler` routes it with `DeeplinkSource.push`. Put the link in the notification's `additionalData` under `url`, `deep_link`, `link` or `uri`, the keys mobile reads. A launch URL set on the OneSignal side alone is not read.

**An address-bar link is GoRouter's job.** The driver is inert rather than wired to `app_links_web`, because that package reads `location.href` once at boot and never reacts to later navigation, so routing the same URI through both would duplicate it. GoRouter only receives a clean path when both of these outside this package hold, and neither fails loudly:

1. `routing.url_strategy` is `'path'` in the app's routing config. Without it Flutter uses the hash strategy and `https://app.example.com/incidents/5` is not a route. See [Routing in Magic](https://anilcancakir.com/magic/docs/basics/routing).
2. The web host rewrites unknown paths to `index.html`. Without it the same URL is a plain 404 from the host and Flutter never boots.

A push clicked with no tab open runs no Dart code, so nothing in this package reads `additionalData`; whatever page the browser then opens is an ordinary page load and depends on the two points above.

<a name="custom-drivers"></a>
## Custom Drivers

A custom driver extends `DeeplinkDriver` and implements every member. The provider wires only the built-in driver, so a custom one does not feed the manager on its own: `manager.setDriver()` makes it the manager's driver (what `manager.driver` and `getInitialLink()` use), and you call `initialize`, subscribe to `onLink` and pass each URI to `handleUri` yourself.

```dart
import 'dart:async';

import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class QrDriver extends DeeplinkDriver {
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();

  @override
  String get name => 'qr';

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<Uri?> getInitialLink() async => null;

  @override
  Stream<Uri> get onLink => _controller.stream;

  /// Call this from the scanner callback.
  void emit(Uri uri) => _controller.add(uri);

  @override
  void dispose() => unawaited(_controller.close());
}

class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    final DeeplinkManager manager = DeeplinkManager();
    final QrDriver driver = QrDriver();

    await driver.initialize(<String, dynamic>{});
    manager.setDriver(driver);

    driver.onLink.listen((Uri uri) {
      unawaited(manager.handleUri(uri, source: DeeplinkSource.manual));
    });
  }
}
```

`setDriver()` replaces the previous driver without disposing it. `MagicRoute.to` throws until the router exists, which happens while the first frame is built, so a driver whose links can arrive that early should wait the way the provider does: capture `WidgetsFlutterBinding.ensureInitialized().endOfFrame` once and await it before `handleUri`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Expecting address-bar links on the web to reach the handlers. | They never do; GoRouter owns them. Set `routing.url_strategy` to `'path'` and make the host rewrite unknown paths to `index.html`. |
| Calling `setDriver()` with a custom driver and waiting for links. | The provider wires only `AppLinksDriver`. Subscribe to the custom driver's `onLink` and call `handleUri` yourself. |
| Setting `deeplink.driver` to any value other than `'app_links'`. | The provider creates no driver and no subscription, though the push bridge still runs. Keep `'app_links'`. |
| Routing the result of `getInitialLink()` as well as listening to `onLink`. | The cold-start link is already the first emission of `onLink`, so the handler chain runs twice for one tap. Use one path. |
| Expecting links on Windows or Linux. | `isSupported` is `false` there and nothing is wired. |
| Assuming the install and the doctor set up macOS. | They cover iOS and Android only. Add the macOS entitlement by hand and verify on a device. |

<a name="related-documentation"></a>
## Related Documentation

- [Handlers](./handlers.md): what runs after a driver emits a link.
- [Configuration](../getting-started/configuration.md): the `driver` and `enabled` keys.
- [Service Provider](../architecture/service-provider.md): boot order, driver initialisation and stream wiring.
- [DeeplinkManager](../architecture/deeplink-manager.md): `setDriver()`, `handleUri()` and the cached initial link.
