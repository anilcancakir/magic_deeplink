# Handlers

Handlers decide what an incoming link does: `DeeplinkManager` offers each URI to its registered handlers in order and the first one that claims it handles it.

- [Quick Reference](#quick-reference)
- [The DeeplinkHandler Contract](#the-deeplinkhandler-contract)
    - [canHandle](#canhandle)
    - [handle](#handle)
    - [DeeplinkSource](#deeplinksource)
- [Built-in Handlers](#built-in-handlers)
    - [RouteDeeplinkHandler](#routedeeplinkhandler)
    - [Switching Tenants from a Push](#switching-tenants-from-a-push)
    - [Breadcrumb Events](#breadcrumb-events)
    - [OneSignalDeeplinkHandler](#onesignaldeeplinkhandler)
- [Creating Custom Handlers](#creating-custom-handlers)
- [Registering Handlers](#registering-handlers)
- [Handler Execution Order](#handler-execution-order)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  DeeplinkManager().registerHandler(
    RouteDeeplinkHandler(
      paths: ['/products/:id', '/shop/*'],
      hosts: ['example.com'],
    ),
  );
}
```

| Class | Role |
|:------|:-----|
| `DeeplinkHandler` | The contract: `canHandle(Uri)` and `handle(Uri, {source, payload})`. |
| `RouteDeeplinkHandler` | Matches the path against patterns and navigates with `MagicRoute.to()`. |
| `TenantSwitchGate` | Optional: lets a tapped push switch tenant before `RouteDeeplinkHandler` navigates. |
| `OneSignalDeeplinkHandler` | Not a `DeeplinkHandler`: turns a tapped push into a `handleUri` call. |

<a name="the-deeplinkhandler-contract"></a>
## The DeeplinkHandler Contract

```dart
abstract class DeeplinkHandler {
  bool canHandle(Uri uri);
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  });
}
```

<a name="canhandle"></a>
### canHandle

A synchronous, side-effect-free predicate. Return `true` to claim the URI, `false` to pass it to the next handler. It runs on every incoming link, so keep it cheap.

<a name="handle"></a>
### handle

Called only after `canHandle` returned `true`. Return `true` when the URI was handled and `false` when it could not be, and never throw: the manager does not catch, so the exception reaches whoever called `handleUri`. For a link the provider delivers that means a logged error and a lost link, and no later handler gets a try. `source` and `payload` come from `DeeplinkManager.handleUri()` and say where the instruction came from; see [DeeplinkSource](#deeplinksource).

<a name="deeplinksource"></a>
### DeeplinkSource

```dart
enum DeeplinkSource { osLink, push, manual }
```

The sources are not equally trusted:

| Value | Meaning | `payload` |
|:------|:--------|:----------|
| `osLink` | The operating system opened the app on a Universal Link or App Link. Anyone who can get the device to open a URI can craft one, so treat it as untrusted input. | Always `null`. |
| `push` | The user tapped a push notification, and the payload is the server's own. | The full payload the notification arrived with. |
| `manual` | The application asked for the link itself, in code or in a test. | Whatever the caller passed, or `null`. |

`source` is required and has no default, so a handler cannot forget to ask. A handler that acts on more than the path it was given, such as switching the active team from a `team_id` key, may do so only when `source == DeeplinkSource.push`, because that is the one case where the payload was authored by the server rather than crafted into a URI. `RouteDeeplinkHandler` reads `source` and `payload` only when it was given a [`tenantGate`](#switching-tenants-from-a-push): navigating to a path you listed is safe whoever asked, moving the session's tenant is not.

<a name="built-in-handlers"></a>
## Built-in Handlers

<a name="routedeeplinkhandler"></a>
### RouteDeeplinkHandler

Matches the URI path against a list of patterns and navigates to the match with `MagicRoute.to()`.

```dart
RouteDeeplinkHandler({
  required List<String> paths,
  List<String>? hosts,
  bool caseSensitive = false,
  TenantSwitchGate? tenantGate,
})
```

**Pattern syntax.** Patterns are compiled to anchored regular expressions, and a trailing slash on the incoming path is dropped before matching:

| Pattern | Matches |
|:--------|:--------|
| `/products` | Exactly `/products` |
| `/products/:id` | One non-slash segment, as a named parameter |
| `/products/*` | Anything after `/products/`, slashes included |
| `/shop/*/detail` | `/shop/`, anything, then `/detail` |

Matching ignores letter case unless `caseSensitive` is `true`. go_router routes are case-sensitive, so a project that mounted `/incidents/:id` can set it to stop `/INCIDENTS/5` being claimed and then landing on go_router's not-found page.

**Hosts.** `hosts` defaults to `null`, which claims an absolute URI on any host whose path matches. Set it to gate `canHandle` on the address as well:

- A relative URI (no scheme and no authority, the shape of a push payload path) is always accepted, since there is no host to check.
- An absolute URI is accepted only over `http` or `https`, with no explicit port and no userinfo, and only when its host equals an entry of `hosts`, ignoring case. A different host, another scheme, a port or embedded credentials is refused before the path is matched.
- A blank entry is ignored rather than treated as a wildcard: `hosts: ['']` refuses every absolute URI.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
    paths: ['/monitors/:id'],
    hosts: ['example.com'],
  );

  handler.canHandle(Uri.parse('/monitors/5')); // true, relative
  handler.canHandle(Uri.parse('https://EXAMPLE.com/monitors/5')); // true
  handler.canHandle(Uri.parse('https://evil.com/monitors/5')); // false, wrong host
  handler.canHandle(Uri.parse('https://example.com:8443/monitors/5')); // false, port
}
```

**Navigation.** A matching link navigates with the parsed path, the same value `canHandle` matched, and forwards the query parameters:

```dart
import 'package:magic/magic.dart';

void open(Uri uri) {
  MagicRoute.to(uri.path, query: uri.queryParameters);
}
```

So `https://example.com/products/42?ref=email` opens `/products/42` with `Request.query('ref')` answering `email`.

`handle` never throws. It re-checks `canHandle` and answers `false` for a path it does not serve, and a navigation that fails, such as the `StateError` of a router that is not built yet, is logged through `Log` when a `log` binding exists and answered `false`.

<a name="switching-tenants-from-a-push"></a>
### Switching Tenants from a Push

A multi-tenant backend resolves a page against the session's current tenant and answers 404 for another tenant's row, so a push that pages a user about another team's incident would land on that 404. Give `RouteDeeplinkHandler` a `TenantSwitchGate` and it switches first:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';
import 'package:magic_starter/magic_starter.dart';

final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
  paths: ['/incidents/:id'],
  tenantGate: TenantSwitchGate(
    currentTenantId: MagicStarter.currentTeamId,
    switchTenant: MagicStarter.switchTeam,
    onSwitched: () => Magic.success('Switched team', 'Opened on the team it belongs to.'),
    onSwitchFailed: (String teamId) => Magic.error('Error', 'Could not switch team.'),
  ),
);
```

Any `String? Function()` and `Future<bool> Function(String)` will do; the sample uses `magic_starter`'s team switcher.

| Field | Meaning |
|:------|:--------|
| `payloadKey` | The push payload key naming the owning tenant. Defaults to `'team_id'`. |
| `currentTenantId` | The session's current tenant id, or `null` while it has not resolved. |
| `switchTenant` | Moves the session onto a tenant and answers whether it took. |
| `onSwitched` | Optional. Runs after a successful switch, before the navigation. One that throws is logged and the link still opens, because the session has already moved. |
| `onSwitchFailed` | Optional. Runs with the requested tenant id when `switchTenant` answered `false` or threw. |

The rules belong to the handler, and no gate configuration changes them:

- **Only `DeeplinkSource.push` switches.** An `osLink` or `manual` link navigates without switching, whatever its payload or query carries.
- **The tenant comes from the payload under `payloadKey`, never from the URI query.** The query is part of the link.
- **Ids compare as trimmed strings**, so a wire `5` and a local `'5'` are the same tenant.
- **No evidence, no switch.** An absent or blank payload tenant, or a `null` current tenant, navigates directly.
- **A failed switch does not navigate.** `switchTenant` answering `false` or throwing calls `onSwitchFailed`, logs an error and answers `false`, since opening the page anyway would meet the same 404.

<a name="breadcrumb-events"></a>
### Breadcrumb Events

`RouteDeeplinkHandler` dispatches these events through `Event.dispatch`, unawaited, so a failing listener never costs the navigation:

| Event | When | `breadcrumbCategory` | `breadcrumbData` |
|:------|:-----|:---------------------|:-----------------|
| `DeeplinkOpened` | After `canHandle` passed, before any switch or navigation | `deeplink.open` | `source`, `route`, `names_tenant` |
| `DeeplinkNavigating` | Immediately before `MagicRoute.to` | `deeplink.navigate` | `route` |

Both implement magic's `ReportsBreadcrumb`, so a crash reporter that listens to every event with `Event.listenAny`, as `magic_sentry` does, records them without this package depending on it. `DeeplinkNavigating` is the last breadcrumb before the router runs, which tells "the link never resolved" apart from "the page it named threw". `route` is the handler's own matched pattern (`/invitations/:token/accept`), not the concrete path, and the data never carries the query string or a payload value, since a link can carry an invite or reset token in any of them.

```dart
import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  Event.listenAny((MagicEvent event) {
    if (event is DeeplinkNavigating) {
      debugPrint('opening a link matching ${event.route}');
    }
  });
}
```

<a name="onesignaldeeplinkhandler"></a>
### OneSignalDeeplinkHandler

Bridges push-notification clicks into the pipeline. It does not implement `DeeplinkHandler`: it is a listener that reads a URI from the notification payload and passes it to `DeeplinkManager.handleUri()` with `DeeplinkSource.push` and the whole payload.

`DeeplinkServiceProvider.boot()` wires it for you when `app.bound('notifications')` is true, so an app with `magic_notifications` needs no code. The URI comes from the first of the payload keys `url`, `deep_link`, `link` and `uri` that holds a non-empty string. A push with no such key is not a failure: most notifications are meant to be read.

To wire it yourself, call `setup()` once with the manager and the notification manager, and `dispose()` when done:

```dart
void setup(DeeplinkManager manager, dynamic notifications)
void dispose()
```

`notifications` is read structurally, so this package declares no dependency on `magic_notifications`. The handler subscribes to the notification manager's `onPushClicked` stream, which exists from construction, so it works whether or not the notifications provider has booted. A manager that publishes no such stream, or an event with no readable `data` payload, is reported at error level through `Log` when a `log` binding exists, rather than thrown or silently dropped. A click that arrives before the first frame waits for it, so a cold start from a push still finds the router.

<a name="creating-custom-handlers"></a>
## Creating Custom Handlers

Extend `DeeplinkHandler` for any matching logic the path patterns cannot express:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class ProductDeeplinkHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) {
    final List<String> segments = uri.pathSegments;

    return segments.length == 2 &&
        segments[0] == 'products' &&
        int.tryParse(segments[1]) != null;
  }

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    try {
      MagicRoute.to('/products/${uri.pathSegments[1]}', query: uri.queryParameters);

      return true;
    } catch (error) {
      if (Magic.bound('log')) {
        Log.error('[ProductDeeplinkHandler] opening $uri failed: $error');
      }

      return false;
    }
  }
}
```

- `canHandle` is synchronous and free of side effects.
- `handle` never throws; wrap what can fail and return `false`.
- Read `payload` only when `source == DeeplinkSource.push`.

<a name="registering-handlers"></a>
## Registering Handlers

Register on the `DeeplinkManager` singleton. Registering the same instance twice has no effect, and `hasHandler()` and `forgetHandlers()` inspect and clear the list:

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

// ProductDeeplinkHandler is the host's own handler class.
void main() {
  final DeeplinkManager manager = DeeplinkManager();

  manager.registerHandler(ProductDeeplinkHandler());
  manager.registerHandler(RouteDeeplinkHandler(paths: ['/products/*', '/shop/*']));
}
```

Do it in your own provider's `boot()`; see [Installation](../getting-started/installation.md#registering-a-route-handler). `DeeplinkServiceProvider` registers no handler of its own.

<a name="handler-execution-order"></a>
## Handler Execution Order

Handlers run in registration order, and the manager stops at the first whose `canHandle` is `true`. `handleUri` also emits the URI on `manager.onLink` before the chain runs, so stream listeners see every link whether or not a handler claims it. It returns `false` when no handler does.

Register specific handlers before generic ones. A wildcard `RouteDeeplinkHandler` registered first claims URIs a more specific handler registered after it never sees.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| No handler is registered. | Links reach the manager and are dropped, with no error. Register one in your provider's `boot()`; `deeplink:doctor` warns when it finds no `registerHandler(` call. |
| A wildcard handler registered before a specific one. | Order is registration order and the first match wins. Register the specific handler first. |
| Leaving `hosts` as `null` on `RouteDeeplinkHandler`. | A link on any host whose path matches is claimed. Set `hosts` to your domain. |
| Reading `payload` or a query value to decide who the user acts as. | Only `source == DeeplinkSource.push` carries a server-authored payload, and a switch never reads the query. Leave tenant changes to `TenantSwitchGate`. |
| Throwing from `handle`. | Return `false`. The manager does not catch; the provider logs the error and the link is lost. |
| Reading `*` as one path segment. | `*` matches slashes too. Use `:name` for exactly one segment. |

<a name="related-documentation"></a>
## Related Documentation

- [DeeplinkManager](../architecture/deeplink-manager.md): the handler chain and `handleUri`.
- [Drivers](./drivers.md): where the links come from.
- [Installation](../getting-started/installation.md): registering a first handler.
- [Service Provider](../architecture/service-provider.md): how the push bridge is wired and torn down.
- [Channels in magic_notifications](https://anilcancakir.com/magic/docs/notifications/basics/channels): the push side of the bridge.
- [Teams in magic_starter](https://anilcancakir.com/magic/docs/starter/basics/teams): the team switcher the tenant sample uses.
