<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_deeplink/master/.github/logo.png" width="120" alt="Magic Deeplink logo" />
</p>

<h1 align="center">Magic Deeplink</h1>

<p align="center">
  <strong>Open the right Magic route from a Universal Link, an App Link or a tapped push.</strong><br/>
  <code>DeeplinkServiceProvider</code> wires <code>app_links</code> into a first-match handler chain, <code>RouteDeeplinkHandler</code> maps a link's path onto a route of your app, and the <code>deeplink:*</code> commands write the <code>apple-app-site-association</code> and <code>assetlinks.json</code> files and check the install.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_deeplink"><img src="https://img.shields.io/pub/v/magic_deeplink.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_deeplink/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_deeplink/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_deeplink"><img src="https://codecov.io/gh/anilcancakir/magic_deeplink/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_deeplink/score"><img src="https://img.shields.io/pub/points/magic_deeplink" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/deeplink">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_deeplink">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_deeplink/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_deeplink`](https://pub.dev/packages/magic_deeplink) |
| Install | `flutter pub add magic_deeplink`, then `dart run magic:dowel plugin:install magic_deeplink` |
| Import | `package:magic_deeplink/magic_deeplink.dart` |
| Entry points | `DeeplinkServiceProvider` (wiring), `DeeplinkManager()` (the singleton), `RouteDeeplinkHandler`, `TenantSwitchGate`, `DeeplinkHandler` (the contract), `DeeplinkDriver`, `AppLinksDriver`; `deeplink:install`, `deeplink:generate`, `deeplink:doctor` (CLI) |
| Platforms | Links are delivered on Android, iOS and macOS. tvOS, web, Windows and Linux wire no driver; on web a tapped push still routes. The CLI covers iOS and Android only. |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0 |
| Dependencies | `magic`, `app_links`, `dowel`, `args` |
| License | MIT |

## Install

```bash
flutter pub add magic_deeplink
dart run magic:dowel plugin:install magic_deeplink
dart run magic:dowel deeplink:doctor
```

The installer publishes `lib/config/deeplink.dart`, adds `DeeplinkServiceProvider` to the `providers` list of `lib/config/app.dart`, adds the `deeplinkConfig` factory to `lib/main.dart` and sets `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist`. It registers no handler and does not touch the Android manifest, so until you finish the native setup a link opens the browser, with no error and no log line:

- iOS: the Associated Domains capability with `applinks:<your-domain>`, and an `apple-app-site-association` file served from `https://<your-domain>/.well-known/`.
- Android: an `autoVerify` intent filter with a `<data>` element for both `http` and `https`, the `flutter_deeplinking_enabled` meta-data set to `false` inside `<activity>` (not `<application>`), and an `assetlinks.json` file served from `https://<your-domain>/.well-known/`.

`deeplink:doctor` reads your project files and says which of those is missing. The steps are in the [installation guide](https://anilcancakir.com/magic/docs/deeplink/getting-started/installation).

## Configuration

`lib/config/deeplink.dart` returns one `deeplink` map:

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',
    'domain': 'example.com',
    'ios': {
      'team_id': 'YOUR_TEAM_ID',
      'bundle_id': 'com.example.app',
    },
    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT',
      ],
    },
    'paths': [
      '/*',
    ],
  },
};
```

| Key | Read by |
|-----|---------|
| `enabled` | The provider. An absent key means on; only an explicit `false` wires nothing, the push bridge included. |
| `driver` | The provider. `'app_links'` is the only value that creates a driver. |
| `domain` | `deeplink:doctor`, and your own handler's `hosts` if you pass it. |
| `ios.team_id`, `ios.bundle_id`, `android.package_name`, `android.sha256_fingerprints` | `deeplink:generate` and `deeplink:doctor`. |
| `paths` | `deeplink:generate`, for the `components` of the `apple-app-site-association` file. The doctor parses it and checks nothing against it; it filters nothing at runtime. |

An install from an earlier release also wrote `'scheme': 'https'`. Nothing reads it; delete it.

## Route a link to a screen

`RouteDeeplinkHandler` matches a link's path against patterns and calls `MagicRoute.to(uri.path, query: uri.queryParameters)`. The provider registers no handler, because it cannot know which paths your app serves: register one in a provider of your own.

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    DeeplinkManager().registerHandler(
      RouteDeeplinkHandler(
        paths: ['/monitors/:id', '/invitations/:token/accept'],
        hosts: [Config.getOrFail<String>('deeplink.domain')],
      ),
    );
  }
}
```

| Parameter | Meaning |
|-----------|---------|
| `paths` | Required. `:name` matches one segment, `*` matches anything, slashes included. A trailing slash on the link is dropped before matching. |
| `hosts` | `null` (the default) claims a matching path on any host. When set, a relative URI always passes; an absolute one is claimed only over `http` or `https`, with no explicit port and no userinfo, on a host equal to an entry, ignoring case. A blank entry is ignored, so `['']` refuses every absolute URI. |
| `caseSensitive` | `false` by default. go_router routes are case-sensitive, so set `true` when `/INCIDENTS/5` must not be claimed and then land on the not-found page. |
| `tenantGate` | `null` (the default) never switches tenant. See below. |

Failure modes:

| Situation | What happens |
|-----------|--------------|
| No handler is registered | `handleUri` answers `false` and the link is dropped, with no error. |
| Two handlers claim the same path | The one registered first wins; register specific handlers before wildcard ones. |
| The router is not built yet, or navigation throws | `RouteDeeplinkHandler.handle` logs through `Log` when a `log` binding exists and answers `false`. |
| A custom handler throws | The manager does not catch. The provider logs the error and the link is lost. |
| `deeplink.driver` is not `'app_links'` | No driver and no link subscription. The push bridge still runs. |
| The platform is tvOS, web, Windows or Linux | `AppLinksDriver.isSupported` is `false`, no driver is set on the manager and nothing is subscribed. |

## Write your own handler

Extend `DeeplinkHandler` when the path patterns are not enough.

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class InviteHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path.startsWith('/invite/');

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    final String code = uri.pathSegments.last;

    if (code.isEmpty) return false;

    try {
      MagicRoute.to('/invite/$code');
    } on StateError {
      return false; // The router is not built yet.
    }

    return true;
  }
}
```

`canHandle` is synchronous and free of side effects; `handle` answers whether it handled the link and never throws. `source` is required, because a handler cannot tell from the URI who asked:

| `DeeplinkSource` | Meaning | `payload` |
|------------------|---------|-----------|
| `osLink` | The operating system opened the app on a Universal Link or App Link. Anyone who can get the device to open a URI can craft one. | Always `null`. |
| `push` | The user tapped a push, and the payload is the server's own. | The whole payload the notification arrived with. |
| `manual` | Your code called `DeeplinkManager().handleUri(...)`. | What the caller passed, or `null`. |

Read `payload`, and act on more than the path, only when `source == DeeplinkSource.push`.

## Switch tenant from a push

A multi-tenant backend resolves a page against the session's current tenant and answers 404 for another tenant's row. Give `RouteDeeplinkHandler` a `TenantSwitchGate` and a push that names another tenant switches first.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  String? activeTeam = '1'; // The host's own session state.

  final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
    paths: ['/incidents/:id'],
    tenantGate: TenantSwitchGate(
      currentTenantId: () => activeTeam,
      switchTenant: (String teamId) async {
        activeTeam = teamId;

        return true;
      },
    ),
  );

  DeeplinkManager().registerHandler(handler);
}
```

The rules belong to the handler, and no gate setting loosens them: only `DeeplinkSource.push` may switch; the tenant is read from the payload under `payloadKey` (default `'team_id'`), never from the URI query; ids compare as trimmed strings; an absent tenant or an unresolved session navigates without switching; a switch that answers `false` or throws calls `onSwitchFailed` and does not navigate. An `onSwitched` that throws is logged and the link still opens.

## Open links from pushes

When `app.bound('notifications')` is true, the provider attaches `OneSignalDeeplinkHandler`, which subscribes to the notification manager's `onPushClicked` stream and passes each tapped push to `DeeplinkManager.handleUri` with `DeeplinkSource.push` and the whole payload. It is not a `DeeplinkHandler` and is not in the chain. No code is needed: `magic_notifications` is read structurally, so this package does not depend on it, and the provider order does not matter.

The link comes from the first of the payload keys `url`, `deep_link`, `link` and `uri` that holds a non-empty string. A push with none of them is not a failure. A manager without `onPushClicked`, or an event without a readable `data` map, is reported at error level through `Log` when a `log` binding exists and routes nothing. A tap that arrives before the first frame waits for it.

## CLI

The package has no `bin/` of its own. After `plugin:install`, your app's dowel lists these:

| Command | Does |
|---------|------|
| `dart run magic:dowel deeplink:install` | Runs the manifest again; `--force` overwrites a `deeplink.dart` the installer did not write, `--dry-run` prints without writing. |
| `dart run magic:dowel deeplink:generate --output public/.well-known` | Writes `apple-app-site-association` and `assetlinks.json` from the config; `--team-id`, `--bundle-id`, `--package-name`, `--sha256-fingerprints` and `--paths` override it, except that an explicit `--paths '/*'` is indistinguishable from the default, so it does not override a config `paths` such as `['/invite/*']`. |
| `dart run magic:dowel deeplink:doctor` | Checks the config, the Dart wiring, the iOS and Android projects and the association files; `--remote` also fetches both from the live domain, `--verbose` adds detail. |

`generate` skips a file, with a warning and exit code `0`, when its platform's values are missing. `doctor` exits `1` when a check fails and `0` when only warnings were raised. It cannot prove that a real device matches a link to your app: test on one.

## What this does not do

- **Web address-bar links.** The web driver is inert; GoRouter owns the address bar. Set `routing.url_strategy` to `'path'` and have the host rewrite unknown paths to `index.html`.
- **macOS setup.** The provider wires the driver on macOS, but the install, `doctor` and `generate` cover iOS and Android only.
- **Named routes.** `RouteDeeplinkHandler` navigates to a path; it does not look a route up by name.
- **A facade.** There is no `Deeplink` facade: `DeeplinkManager()` is the entry point.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake that fails silently.

| Do | Because |
|----|---------|
| Import only `package:magic_deeplink/magic_deeplink.dart` | Everything under `src/` is private. |
| Register your own `RouteDeeplinkHandler` in a provider's `boot()` | The provider registers none, and a link with no handler is dropped without an error. |
| Set `hosts` on `RouteDeeplinkHandler` | `null` claims a matching path on any host. |
| Register specific handlers before wildcard ones | The first handler whose `canHandle` is `true` wins. |
| Return `false` from `handle`, never throw | The manager does not catch; the link is lost. |
| Read `payload` only when `source == DeeplinkSource.push` | An `osLink` is attacker-craftable and carries no payload. |
| Move the tenant with `TenantSwitchGate`, never from the URI query | The gate applies the push-only and payload-only rules; the query is part of the link. |
| Add `flutter_deeplinking_enabled` `false` to `<activity>` by hand | The installer cannot place it there, and in `<application>` it does nothing. |
| Run `deeplink:doctor` before reaching for a device | A wrong entitlement, intent filter or association file all end in a link that opens the browser. |
| Reach the manager as `DeeplinkManager()` | There is no `Deeplink` facade. |
| Do not route `getInitialLink()` as well as listening to `onLink` | `app_links` delivers the cold-start link on the stream, so the handler chain would run twice for one tap. |
| In a test, call `DeeplinkManager().reset()` in `setUp` and `tearDown` | The singleton keeps its handlers, driver and cached initial link across tests: `setUp` starts clean, `tearDown` leaves nothing for the next test. |

## Dependencies

`magic` for the container, config, router, events and `Log`; `app_links` for Universal Links and App Links on Android, iOS and macOS; `dowel` to run the `deeplink:*` commands through `dart run magic:dowel`. The command classes are also exported from `package:magic_deeplink/cli.dart`, which imports no UI toolkit so a dowel dispatcher stays a plain Dart process.

## Links

- [Documentation](https://anilcancakir.com/magic/docs/deeplink/getting-started/installation): installation and platform setup, configuration, handlers, drivers, the manager, the provider and the CLI
- [API reference](https://pub.dev/documentation/magic_deeplink/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-deeplink/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_deeplink`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_deeplink/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
