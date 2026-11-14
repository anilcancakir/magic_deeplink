# Installation

Add `magic_deeplink` to a Magic application, run its manifest installer, register a handler and finish the native setup an operating system needs before it hands your app a link.

- [Quick Start](#quick-start)
- [Requirements](#requirements)
- [Running the Install Command](#running-the-install-command)
- [Registering a Route Handler](#registering-a-route-handler)
- [Platform Setup](#platform-setup)
  - [iOS: Associated Domains and Info.plist](#ios-associated-domains-and-infoplist)
  - [Android: Intent Filter and Manifest](#android-intent-filter-and-manifest)
  - [macOS](#macos)
- [Verify](#verify)
- [Related Documentation](#related-documentation)

<a name="quick-start"></a>
## Quick Start

```bash
flutter pub add magic_deeplink
dart run magic:dowel plugin:install magic_deeplink
dart run magic:dowel deeplink:doctor
```

`magic_deeplink` delegates link delivery to [`app_links`](https://pub.dev/packages/app_links) and ships no native plugin code of its own. That does not remove the platform setup an operating system requires: an iOS entitlement, an Android intent filter, and a switch on each platform that keeps Flutter's own deep link handler out of the way. See [Platform Setup](#platform-setup).

<a name="requirements"></a>
## Requirements

| Requirement | Constraint |
|:------------|:-----------|
| Dart SDK | `>=3.13.0` |
| Flutter | `>=3.47.0` |
| `magic` | `^1.0.0`, installed and bootstrapped: `lib/config/app.dart` declares a `'providers'` list and `lib/main.dart` calls `Magic.init` with `configFactories` |

<a name="running-the-install-command"></a>
## Running the Install Command

`plugin:install` runs the manifest in the package's `install.yaml` and registers `MagicDeeplinkDowelProvider` in `.dowel/plugins.json`, which is what makes the `deeplink:*` commands available in your project. The package must already be in `pubspec.yaml` and resolved by `flutter pub get`.

```bash
dart run magic:dowel plugin:install magic_deeplink
```

The manifest:

1. Publishes `lib/config/deeplink.dart` from the bundled stub. See [Configuration](./configuration.md) for its keys.
2. Adds `(app) => DeeplinkServiceProvider(app)` and its import to the `'providers'` list in `lib/config/app.dart`. The install fails with an error naming the file when `app.dart` has no such list.
3. Adds `() => deeplinkConfig` and `import 'config/deeplink.dart';` to the `configFactories` list in `lib/main.dart`.
4. Sets `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist`.

`dart run magic:dowel deeplink:install` runs the same manifest again, for a project that has already registered the provider. An existing `lib/config/deeplink.dart` that the installer did not write, or that changed since, is a conflict: the command exits with `1` until you pass `--force`.

| Flag | Effect |
|:-----|:-------|
| `--force` | Bypass the conflict check and overwrite. |
| `--dry-run` | Print the staged operations without writing. |
| `--non-interactive` | Skip prompts and use defaults. |

After the install, `DeeplinkServiceProvider` is in your providers list:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

// RouteServiceProvider and AppServiceProvider are the host's own providers.
final appConfig = {
  'app': {
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AppServiceProvider(app),
      (app) => DeeplinkServiceProvider(app), // added by the install
    ],
  },
};
```

and `lib/main.dart` passes the config factory to `Magic.init`:

```dart
import 'package:magic/magic.dart';

// appConfig and deeplinkConfig are the host's own, from lib/config/.
Future<void> main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => deeplinkConfig, // added by the install
    ],
  );
}
```

The provider binds `DeeplinkManager` as a singleton under the `'deeplinks'` key, so `app.make<DeeplinkManager>('deeplinks')` resolves it anywhere.

<a name="registering-a-route-handler"></a>
## Registering a Route Handler

The install wires the driver and the provider but registers no handler: `DeeplinkServiceProvider` cannot know which paths your app serves, and a link that reaches the manager with no handler registered is dropped without an error. Register one in your own provider's `boot()`:

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

See [Handlers](../basics/handlers.md) for the contract, the path patterns and writing a custom handler.

<a name="platform-setup"></a>
## Platform Setup

An operating system will not hand your app a link until you declare that the app owns the domain, and Flutter's own deep link handler races the `app_links` driver unless you switch it off. Only the iOS plist key is automated; the rest is a one-time edit to the native project.

<a name="ios-associated-domains-and-infoplist"></a>
### iOS: Associated Domains and Info.plist

1. **Add the Associated Domains capability.** In Xcode, open the `Runner` target's Signing & Capabilities tab, add "Associated Domains" and an entry of the form `applinks:<your-domain>`. This writes the `com.apple.developer.associated-domains` entitlement to `ios/Runner/Runner.entitlements`:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
       <string>applinks:example.com</string>
   </array>
   ```

2. **Turn off Flutter's own deep link handler.** Flutter has handled deep links itself by default since 3.27, and when it does the handler chain never sees the link. The `FlutterDeepLinkingEnabled` key in `ios/Runner/Info.plist` must be `false`:

   ```xml
   <key>FlutterDeepLinkingEnabled</key>
   <false/>
   ```

   The install applies this key (`native.ios.info_plist` in `install.yaml`). Re-check it when something else in your project overwrites `Info.plist`.

3. **Host the `apple-app-site-association` file.** Generate it with [`deeplink:generate`](../basics/cli.md#generate) and serve it from `https://<your-domain>/.well-known/apple-app-site-association` over HTTPS with no redirect.

<a name="android-intent-filter-and-manifest"></a>
### Android: Intent Filter and Manifest

1. **Add the intent filter.** Inside the `<activity>` element of `android/app/src/main/AndroidManifest.xml`, add an autoVerify filter with a `<data>` element for both `http` and `https`:

   ```xml
   <activity
       android:name=".MainActivity"
       android:exported="true"
       ...>
       <intent-filter android:autoVerify="true">
           <action android:name="android.intent.action.VIEW" />
           <category android:name="android.intent.category.DEFAULT" />
           <category android:name="android.intent.category.BROWSABLE" />

           <data android:scheme="http" android:host="example.com" />
           <data android:scheme="https" android:host="example.com" />
       </intent-filter>
   </activity>
   ```

2. **Turn off Flutter's own deep link handler, inside `<activity>`.** Add this element to the same `<activity>`, not to `<application>`:

   ```xml
   <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
   ```

   The install does not apply this one. The `meta_data` key of `install.yaml` inserts into `<application>`, Flutter reads this entry from `<activity>`, and an automated entry in the wrong element would look applied while doing nothing. Add it by hand; [`deeplink:doctor`](../basics/cli.md#doctor) fails when it sits in the wrong element.

3. **Host the `assetlinks.json` file.** Generate it with `deeplink:generate` and serve it from `https://<your-domain>/.well-known/assetlinks.json`. Android verifies it at install time, not at link-click time.

<a name="macos"></a>
### macOS

`AppLinksDriver` reports itself supported on macOS, so the provider wires it there. Nothing else in this package covers macOS: the install does not touch the macOS project, `deeplink:doctor` inspects only `ios/` and `android/`, and `deeplink:generate` writes a single `appIDs` entry built from one `team_id` and `bundle_id`, so a macOS app with a different bundle identifier needs its own entry. Follow the macOS setup in the [`app_links`](https://pub.dev/packages/app_links) package for the entitlement.

<a name="verify"></a>
## Verify

```bash
dart run magic:dowel deeplink:doctor
```

Every way of getting this install wrong is silent: a `<meta-data>` on the wrong element, a missing `<data>` scheme, an association file that names another bundle, a provider that never reached `lib/config/app.dart`. None throws or logs; the only symptom is a link that opens the browser. The doctor reads the project's own files and reports which prerequisite is missing. Add `--remote` to also fetch both association files from the live domain.

It cannot prove that a real device matches a link to this app: `swcutil verify` needs root and Android verifies at install time, so the last mile is always a real device. See [CLI](../basics/cli.md#doctor) for every check.

<a name="related-documentation"></a>
## Related Documentation

- [Configuration](./configuration.md): the keys of `lib/config/deeplink.dart`.
- [Handlers](../basics/handlers.md): `RouteDeeplinkHandler`, tenant switching and custom handlers.
- [CLI](../basics/cli.md): `deeplink:install`, `deeplink:generate` and `deeplink:doctor`.
- [Drivers](../basics/drivers.md): platform support of `AppLinksDriver`.
- [Service Provider](../architecture/service-provider.md): what `boot()` wires.
- [Routing in Magic](https://anilcancakir.com/magic/docs/basics/routing): `MagicRoute` and the `url_strategy` setting.
