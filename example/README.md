# magic_deeplink example

A Magic app that registers `DeeplinkServiceProvider`, a `RouteDeeplinkHandler` for `/monitors/:id` on `example.com`, and a text field. `Open link` hands the typed URI to `DeeplinkManager().handleUri` as a `DeeplinkSource.manual` link: a match opens the `Monitor` page through `MagicRoute.to`, and `https://other.com/monitors/42` is refused by the handler's `hosts`. The screen also lists every URI the manager saw on `onLink`, and says which driver the provider wired.

```bash
cd example
flutter create --platforms=web .
flutter run -d chrome
```

`flutter create` adds the platform folder once; it leaves `lib/` and `pubspec.yaml` as they are.

What this does not show, because it needs a device and a domain: a link the operating system hands to the app. On web the provider wires no driver (the screen says so), and a real Universal Link or App Link needs the associated-domains entitlement, an `autoVerify` intent filter, an `apple-app-site-association` and an `assetlinks.json` served from your domain; `deeplink:install`, `deeplink:generate` and `deeplink:doctor` are the way in, see the package documentation. The example registers no auth provider, so Magic prints a one-time notice at boot that the router will not re-run redirects on auth changes; nothing here uses them.
