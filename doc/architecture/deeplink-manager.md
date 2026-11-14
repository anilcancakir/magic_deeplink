# DeeplinkManager

`DeeplinkManager` is the singleton that owns one platform driver, an ordered list of handlers and a broadcast stream of every incoming deep link.

- [Quick Reference](#quick-reference)
- [Singleton Pattern](#singleton-pattern)
- [Driver Orchestration](#driver-orchestration)
    - [Setting a Driver](#setting-a-driver)
    - [Removing a Driver](#removing-a-driver)
- [Handler Chain](#handler-chain)
    - [Registering Handlers](#registering-handlers)
    - [Removing Handlers](#removing-handlers)
- [URI Stream](#uri-stream)
- [handleUri Flow](#handleuri-flow)
- [Initial Link Caching](#initial-link-caching)
- [Data Flow](#data-flow)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

`DeeplinkServiceProvider` creates and wires the manager during boot, so consuming code rarely needs more than the singleton:

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  final DeeplinkManager manager = DeeplinkManager();

  manager.onLink.listen((Uri uri) {
    // Your own code goes here, for instance a call to your analytics.
  });
}
```

| Member | Purpose |
|:-------|:--------|
| `driver` | The current `DeeplinkDriver`; throws `DeeplinkException` with code `NO_DRIVER` when none is set. |
| `setDriver(driver)`, `forgetDriver()` | Assign or drop the driver. |
| `registerHandler(handler)`, `hasHandler(handler)`, `forgetHandlers()` | Manage the ordered handler list. |
| `onLink` | Broadcast stream of every URI passed to `handleUri`. |
| `handleUri(uri, {source, payload})` | Emit on `onLink`, then offer the URI to the handlers. |
| `getInitialLink()` | Ask the driver for the cold-start link, once, and cache it. |
| `reset()` | `@visibleForTesting`: return the singleton to its constructed state. |

<a name="singleton-pattern"></a>
## Singleton Pattern

The manager is a process-wide singleton. Every `DeeplinkManager()` call returns the same instance, and the provider also binds it in the container under `'deeplinks'`. Nothing creates a second one, so handlers and a driver set through one reference are visible through every other.

**Testing reset.** The singleton persists across tests. `forgetHandlers()` and `forgetDriver()` alone leave the cached initial link behind, so a second `getInitialLink()` answers the previous test's URI without reaching the driver, and they leave the broadcast controller behind `onLink` in place. `reset()` clears both, along with the handlers and the driver. Call it in `setUp` so a test starts clean, and in `tearDown` so nothing leaks into the next one:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  setUp(() {
    DeeplinkManager().reset();
  });

  tearDown(() {
    DeeplinkManager().reset();
  });
}
```

<a name="driver-orchestration"></a>
## Driver Orchestration

The manager delegates platform I/O to a single `DeeplinkDriver`. It has none at construction: `DeeplinkServiceProvider.boot()` sets it once the container is ready, and only when the driver reports `isSupported`.

<a name="setting-a-driver"></a>
### Setting a Driver

```dart
void setDriver(DeeplinkDriver driver)
```

Assigns the active driver, replacing any previous one without disposing it. `getInitialLink()` calls through whatever driver is set.

<a name="removing-a-driver"></a>
### Removing a Driver

```dart
void forgetDriver()
```

Sets the driver to `null`. The `driver` getter then throws until a new one is set:

```dart
throw DeeplinkException(
  'No deep link driver configured. Make sure to call setDriver() or register the service provider.',
  code: 'NO_DRIVER',
);
```

The driver contract is in [Drivers](../basics/drivers.md#the-deeplink-driver-contract).

<a name="handler-chain"></a>
## Handler Chain

The manager keeps an ordered `List<DeeplinkHandler>`. A URI is offered in registration order, and the first handler whose `canHandle()` returns `true` wins; later handlers are skipped.

<a name="registering-handlers"></a>
### Registering Handlers

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  final DeeplinkManager manager = DeeplinkManager();

  manager.registerHandler(RouteDeeplinkHandler(paths: ['/products/:id']));
}
```

A handler already in the list, by identity, is ignored. `hasHandler(handler)` answers whether that exact instance is registered. The handler contract is in [Handlers](../basics/handlers.md#the-deeplinkhandler-contract).

<a name="removing-handlers"></a>
### Removing Handlers

`forgetHandlers()` clears the list. It is for test teardown and provider re-boot; there is no way to remove a single handler.

<a name="uri-stream"></a>
## URI Stream

```dart
Stream<Uri> get onLink;
```

`onLink` is a broadcast stream, so analytics, routing and tests can subscribe independently. It is never closed during normal operation and lives as long as the singleton; only `reset()` closes it and replaces it, after which `onLink` hands out the new stream.

<a name="handleuri-flow"></a>
## handleUri Flow

```dart
Future<bool> handleUri(
  Uri uri, {
  required DeeplinkSource source,
  Map<String, dynamic>? payload,
});
```

1. **Emit.** The URI goes onto `onLink` before any handler runs, so every subscriber sees every URI, handled or not.
2. **Dispatch.** The first handler whose `canHandle(uri)` is `true` receives `source` and `payload` and its answer is returned. When none matches, the result is `false`.

`source` is required at the call site and `payload` is optional, because neither can be recovered from the URI. The provider's driver subscription passes `DeeplinkSource.osLink` and no payload; `OneSignalDeeplinkHandler` passes `DeeplinkSource.push` and the whole notification payload. See [DeeplinkSource](../basics/handlers.md#deeplinksource).

<a name="initial-link-caching"></a>
## Initial Link Caching

`getInitialLink()` asks the driver for the link that launched the app and caches the answer, including `null`, so later calls skip the driver:

```dart
Future<Uri?> getInitialLink();
```

| State | Behaviour |
|:------|:----------|
| First call | Delegates to `driver.getInitialLink()` and remembers the answer, `null` included. |
| Later calls | Returns the cached value without touching the driver. |

The provider does not call this method: `app_links` serves the cold-start link as the first emission of `onLink`, and routing it from both places would run the handler chain twice for one tap. It stays on the manager for a consumer that wants to ask directly. `forgetDriver()` does not clear the cache; `reset()` does.

<a name="data-flow"></a>
## Data Flow

```
App launch
    │
    ▼
DeeplinkServiceProvider.boot()
    │
    ├─ return early if config.deeplink.enabled == false
    │
    ├─ manager.setDriver(driver)          (only when driver.isSupported)
    │
    ├─ driver.initialize(config)
    │
    └─ driver.onLink.listen(uri => deliver after endOfFrame)
            │
            ▼
        manager.handleUri(uri, source: DeeplinkSource.osLink)
                │
                ├─ emit the uri                  ──► onLink stream subscribers
                │
                └─ iterate the handlers in registration order
                        │
                        ├─ handler.canHandle(uri) == false  ──► next handler
                        │
                        └─ handler.canHandle(uri) == true
                                │
                                ▼
                            handler.handle(uri, source: source, payload: payload)
                                │
                                └─ return bool  ──► handleUri returns
```

<a name="related-documentation"></a>
## Related Documentation

- [Service Provider](./service-provider.md): how the manager is bound and wired during boot.
- [Drivers](../basics/drivers.md): the driver contract and `AppLinksDriver`.
- [Handlers](../basics/handlers.md): the handler contract and the built-in handlers.
