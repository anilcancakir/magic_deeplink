# DeeplinkServiceProvider

`DeeplinkServiceProvider` is the bootstrap entry point of `magic_deeplink`: it binds the manager, creates the platform driver, routes incoming links through the handler chain and bridges tapped pushes.

- [Quick Reference](#quick-reference)
- [Two-Phase Bootstrap](#two-phase-bootstrap)
- [Register Phase](#register-phase)
- [Boot Phase](#boot-phase)
    - [Driver Initialisation](#driver-initialization)
    - [Stream Wiring](#stream-wiring)
    - [Initial Link Handling](#initial-link-handling)
    - [OneSignal Handler Setup](#onesignal-handler-setup)
- [Optional Dependency Handling](#optional-dependency-handling)
- [Provider Teardown](#provider-teardown)
- [Registering the Provider](#registering-the-provider)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

The provider extends `ServiceProvider` from `package:magic/magic.dart`. The install adds it to `lib/config/app.dart`; by hand:

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

Map<String, dynamic> get appConfig => {
  'app': {
    'providers': [
      // ... other providers
      (app) => DeeplinkServiceProvider(app),
    ],
  },
};
```

| Phase | What happens |
|:------|:-------------|
| `register()` | Binds `DeeplinkManager` under `'deeplinks'`. |
| `boot()` | Reads `deeplink.enabled` and `deeplink.driver`, wires the driver and the link stream, bridges pushes when `magic_notifications` is bound. |
| `dispose()` | Tears down what `boot()` wired. Nothing in the framework calls it. |

The constructor takes an optional `driverFactory`, which defaults to `AppLinksDriver.new`, so a test can substitute a fake: the real driver reads `isSupported` from the host platform.

<a name="two-phase-bootstrap"></a>
## Two-Phase Bootstrap

Magic calls providers in two ordered phases:

| Phase | Method | Constraint |
|:------|:-------|:-----------|
| 1 | `register()` | Synchronous. Only bind into the container; no other service is reachable yet. |
| 2 | `boot()` | Asynchronous. Every provider has registered, so every binding is resolvable. |

Application boot awaits each provider's `boot()` in a plain loop with no error handling, so an exception that escapes `boot()` aborts app boot and every provider registered after this one.

<a name="register-phase"></a>
## Register Phase

```dart
@override
void register() {
  app.singleton('deeplinks', () => DeeplinkManager());
}
```

`register()` binds the manager and nothing else: config is not read and no driver is created. `DeeplinkManager()` is itself a singleton factory, so the closure and the factory share one instance.

<a name="boot-phase"></a>
## Boot Phase

```dart
@override
Future<void> boot() async {
  final config = app.make<ConfigRepository>('config');
  final manager = app.make<DeeplinkManager>('deeplinks');

  if (config.get<bool>('deeplink.enabled') == false) {
    return;
  }

  final driverName = config.get<String>('deeplink.driver');
  final driver = driverName == 'app_links' ? _driverFactory() : null;

  // ... driver and handler wiring
}
```

An absent `deeplink.enabled` means enabled, so only an explicit `false` skips everything below, including the push bridge.

<a name="driver-initialization"></a>
### Driver Initialisation

`'app_links'` is the only value that creates a driver. The driver is wired further only when it also reports `isSupported`:

```dart
if (driver != null && driver.isSupported) {
  manager.setDriver(driver);
  await driver.initialize(config.get<Map<String, dynamic>>('deeplink') ?? {});

  // ...
}
```

A driver that answers `false` is never handed to the manager and never initialised, so `manager.driver` does not answer with something that can never deliver. The web arm of `AppLinksDriver` always answers `false`. The whole `deeplink` config map goes to `initialize()`, which is awaited before the stream is wired.

<a name="stream-wiring"></a>
### Stream Wiring

After initialisation the provider subscribes to `driver.onLink` and delivers each URI once the first frame has rendered:

```dart
final firstFrame = WidgetsFlutterBinding.ensureInitialized().endOfFrame;

driver.onLink.listen((uri) {
  unawaited(_deliver(manager, uri, firstFrame));
});
```

`_deliver` awaits `firstFrame`, then calls `manager.handleUri(uri, source: DeeplinkSource.osLink)` inside a `try` and `catch` that reports a failure through `Log` (guarded by `Magic.bound('log')`) instead of letting it escape as an unhandled async error. Universal Links on iOS and App Links on Android take this one path. `handleUri` emits the URI on `manager.onLink`, then walks the registered handlers in registration order and returns after the first one whose `canHandle` succeeds: later handlers never receive that URI, so register the most specific handler first.

<a name="initial-link-handling"></a>
### Initial Link Handling

A cold start from a link needs no separate read: `app_links` serves the launch link as the first emission of the same `onLink` stream the provider already subscribes to. The provider never calls `manager.getInitialLink()`, because a second delivery of the same link would run the handler chain twice for one tap. `DeeplinkManager.getInitialLink()` stays available for a consumer that wants to ask directly.

The delivery waits because the router does not exist yet at boot: `MagicRoute.to` throws a `StateError` until the app builds the router, which happens while the first frame is built. `endOfFrame` names that event instead of guessing a duration, and it schedules a frame when the scheduler is idle, so a link delivered to an application nobody is drawing is not left waiting. The future is captured once, before the first link can arrive, so awaiting deliveries resume in the order they arrived.

A cold-start link that arrives while a provider registered after this one is still booting can resume against a router that is not built; the `catch` in `_deliver` then logs the `StateError` rather than losing the link silently.

<a name="onesignal-handler-setup"></a>
### OneSignal Handler Setup

When `magic_notifications` is bound, the provider attaches a `OneSignalDeeplinkHandler` that converts tapped-push events into deep link calls:

```dart
if (app.bound('notifications')) {
  final handler = OneSignalDeeplinkHandler();

  try {
    handler.setup(manager, app.make('notifications'));
    _pushClicks = handler;
  } catch (error) {
    handler.dispose();

    if (Magic.bound('log')) {
      Log.error(
        '[deeplink] Resolving the bound `notifications` manager failed, so '
        'a tapped push notification cannot open a deep link: $error',
      );
    }
  }
}
```

The handler is held in `_pushClicks` so `dispose()` can reach it. `setup()` takes the notification manager and subscribes to its `onPushClicked` stream, which the manager owns from construction. Only the `'notifications'` binding has to exist at this point, never a resolved push driver, so provider order does not matter. The handler reads a URI from the payload keys `url`, `deep_link`, `link` and `uri`, and calls `manager.handleUri(uri, source: DeeplinkSource.push, payload: data)` with the whole payload. This block sits outside the `isSupported` gate, so it runs on the web too.

<a name="optional-dependency-handling"></a>
## Optional Dependency Handling

The `magic_notifications` integration is optional, and layered guards keep it from breaking boot:

1. **`app.bound('notifications')`** guards the whole block. Without the plugin the block is skipped.
2. **Structural access.** `app.make('notifications')` is handed over untyped and `OneSignalDeeplinkHandler` reads `onPushClicked` off it by name, so `magic_deeplink` imports nothing from `magic_notifications`. A manager that publishes no such stream, or publishes something that is not a `Stream`, is reported through `Log` instead of thrown, so a version mismatch degrades deep linking rather than breaking boot.
3. **A `try` and `catch` around the resolution**, reporting at error level through the same `Log` seam. `app.make('notifications')` runs the binding factory and `onPushClicked` is a getter, so either can throw, and the handler answers only `NoSuchMethodError` by name. Anything else, such as a `StateError` from an uninitialised manager, would otherwise abort app boot over an optional plugin.

The `catch` names what failed and then lets boot continue. Follow the same pattern wherever `magic_deeplink` integrates with another optional plugin.

<a name="provider-teardown"></a>
## Provider Teardown

`DeeplinkServiceProvider.dispose()` drops everything `boot()` wired: the push-click handler, the driver's link subscription, the driver itself, and the manager's reference to it through `DeeplinkManager.forgetDriver()`. `_deliver` checks a `_disposed` flag once its wait for the first frame ends, before it hands the link over, since a delivery waiting on `endOfFrame` has no handle a teardown could cancel.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

Future<void> tearDown(DeeplinkServiceProvider provider) async {
  await provider.dispose();
}
```

It is provider-level so that a consumer who tears down from the provider does not leave the driver running, and it is idempotent, because a consumer does not know which parts a given deployment wired. Nothing in the framework calls it; call it from whatever holds the provider instance.

<a name="registering-the-provider"></a>
## Registering the Provider

Add the provider to the `providers` list in `lib/config/app.dart`, as in the Quick Reference. The `deeplink` config map comes from `lib/config/deeplink.dart` through `Magic.init(configFactories: [...])`; see [Configuration](../getting-started/configuration.md).

The provider's position relative to the provider that registers `'notifications'` does not matter. `app.bound('notifications')` is checked during boot, after every provider has registered, and the handler subscribes to the notification manager's own stream rather than to a driver.

<a name="related-documentation"></a>
## Related Documentation

- [DeeplinkManager](./deeplink-manager.md): the singleton the provider wires.
- [Drivers](../basics/drivers.md): the driver the provider creates.
- [Handlers](../basics/handlers.md): `OneSignalDeeplinkHandler` and the handler chain.
- [Installation](../getting-started/installation.md): adding the provider with the install command.
- [Service Providers in Magic](https://anilcancakir.com/magic/docs/getting-started/service-providers): the two-phase lifecycle.
- [Channels in magic_notifications](https://anilcancakir.com/magic/docs/notifications/basics/channels): the notification manager the push bridge reads.
