# Configuration

`magic_deeplink` is configured by one Dart file, `lib/config/deeplink.dart`, whose `deeplink` map drives the runtime provider, the association files and the doctor.

- [Quick Reference](#quick-reference)
- [The Deeplink Config File](#deeplink-config-file)
- [Driver Selection](#driver-selection)
- [iOS Configuration](#ios-configuration)
- [Android Configuration](#android-configuration)
- [Paths](#paths)
- [Accessing Configuration Values](#accessing-configuration-values)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Key | Type | Read by |
|:----|:-----|:--------|
| `deeplink.enabled` | `bool` | `DeeplinkServiceProvider.boot()`. An absent key means enabled; only an explicit `false` wires nothing. |
| `deeplink.driver` | `String` | `DeeplinkServiceProvider.boot()`. `'app_links'` is the only built-in driver. |
| `deeplink.domain` | `String` | `deeplink:doctor` (entitlement host, intent filter host, `--remote` fetch). Your own handler's `hosts` can read it too. |
| `deeplink.ios.team_id`, `deeplink.ios.bundle_id` | `String` | `deeplink:generate` and `deeplink:doctor`. |
| `deeplink.android.package_name`, `deeplink.android.sha256_fingerprints` | `String`, `List<String>` | `deeplink:generate` and `deeplink:doctor`. |
| `deeplink.paths` | `List<String>` | `deeplink:generate`, for the `components` of the `apple-app-site-association` file. |

The install command scaffolds the file with placeholder values (`example.com`, `YOUR_TEAM_ID`, `com.example.app`, `YOUR_SHA256_FINGERPRINT`); the doctor reports any that are left.

<a name="deeplink-config-file"></a>
## The Deeplink Config File

`lib/config/deeplink.dart` exports one top-level getter that returns a nested `Map<String, dynamic>`:

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

The stub the installer publishes also writes a `'scheme': 'https'` entry. Nothing in the package reads it, so you can delete it.

`lib/main.dart` hands the getter to `Magic.init` as a factory:

```dart
await Magic.init(
  configFactories: [
    () => appConfig,
    () => deeplinkConfig,
  ],
);
```

> [!NOTE]
> The `deeplink:generate` and `deeplink:doctor` commands read this file as text, with single-quoted string literals. See [CLI](../basics/cli.md#config-merge-strategy).

<a name="driver-selection"></a>
## Driver Selection

The `'driver'` key names the platform abstraction that receives incoming links:

| Value | Package | Platforms |
|:------|:--------|:----------|
| `'app_links'` | `app_links` | Android, iOS and macOS. Web, Windows and Linux report the driver as unsupported. |

`DeeplinkServiceProvider.boot()` creates `AppLinksDriver` for `'app_links'` and nothing for any other value, so a different name wires no driver and no link subscription. The provider then checks `driver.isSupported` before wiring further: on web, Windows and Linux no driver is set on the manager and no subscription is created, and `'driver': 'app_links'` stays the correct value on every platform. See [Drivers](../basics/drivers.md).

> [!NOTE]
> `'enabled'` gates all of this. `boot()` returns immediately when `Config.get<bool>('deeplink.enabled') == false`, which skips the driver, the link subscription and the push bridge regardless of `'driver'`.

<a name="ios-configuration"></a>
## iOS Configuration

iOS Universal Links need an `apple-app-site-association` (AASA) file hosted at your domain. The `ios` block holds the values the generator needs:

| Key | Type | Description |
|:----|:-----|:------------|
| `team_id` | `String` | Your Apple Developer Team ID, from Membership in the Apple Developer portal. |
| `bundle_id` | `String` | The bundle identifier of your iOS app, for example `com.example.app`. |

The generator writes Apple's `appIDs` plus `components` shape, with the app identifier built as `TEAM_ID.BUNDLE_ID` and one `components` entry per path. It never writes the legacy `appID` plus `paths` entry or an `apps` key: mixing the two schemas may produce unexpected behaviour for universal links, and the doctor warns when a file does.

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.app"],
        "components": [
          { "/": "/*", "comment": "Matches any URL whose path matches /*" }
        ]
      }
    ]
  }
}
```

> [!NOTE]
> Serve the file over HTTPS at `https://<domain>/.well-known/apple-app-site-association` with `Content-Type: application/json` and no redirect. `deeplink:doctor --remote` checks the status, that the body parses as JSON and the content type.

<a name="android-configuration"></a>
## Android Configuration

Android App Links need an `assetlinks.json` file hosted at your domain. The `android` block holds the values the generator needs:

| Key | Type | Description |
|:----|:-----|:------------|
| `package_name` | `String` | The Android application ID, matching `applicationId` in `android/app/build.gradle`. |
| `sha256_fingerprints` | `List<String>` | One or more SHA-256 certificate fingerprints. Include every signing configuration you ship with, such as debug and release. |

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Each fingerprint produces its own entry in `assetlinks.json`:

```dart
'sha256_fingerprints': [
  'AA:BB:CC:...', // debug keystore
  'DD:EE:FF:...', // release keystore
],
```

> [!NOTE]
> Serve the file at `https://<domain>/.well-known/assetlinks.json` with `Content-Type: application/json`. Android verifies it at install time, not at link-click time.

<a name="paths"></a>
## Paths

`paths` is the list of URL path patterns written into the `components` of the iOS AASA file. It does not filter links at runtime: which paths your app routes is decided by the `paths` of the `RouteDeeplinkHandler` you register. See [Handlers](../basics/handlers.md#routedeeplinkhandler).

```dart
'paths': [
  '/app/*',
  '/invite/*',
  '/reset-password',
],
```

| Pattern | Matches |
|:--------|:--------|
| `'/*'` | All paths |
| `'/app/*'` | Any path starting with `/app/` |
| `'/reset-password'` | Exactly `/reset-password` |

> [!NOTE]
> `assetlinks.json` grants the app the whole domain and carries no paths. On Android the path filter is the intent filter in `AndroidManifest.xml`.

<a name="accessing-configuration-values"></a>
## Accessing Configuration Values

At runtime magic's `Config` facade reads every value with dot notation:

```dart
import 'package:magic/magic.dart';

final bool enabled = Config.get<bool>('deeplink.enabled', true) ?? true;
final String? domain = Config.get<String>('deeplink.domain');
final String? teamId = Config.get<String>('deeplink.ios.team_id');
```

`DeeplinkServiceProvider` passes the whole `deeplink` map to `driver.initialize()` during `boot()`. `AppLinksDriver` does not read it; a custom driver can.

<a name="related-documentation"></a>
## Related Documentation

- [CLI](../basics/cli.md): `deeplink:generate` reads these keys and `deeplink:doctor` validates them.
- [Installation](./installation.md): the install command and the native setup.
- [Drivers](../basics/drivers.md): what the `driver` key selects.
- [Service Provider](../architecture/service-provider.md): how `boot()` reads `enabled` and `driver`.
- [Configuration in Magic](https://anilcancakir.com/magic/docs/getting-started/configuration): config factories and dot notation.
