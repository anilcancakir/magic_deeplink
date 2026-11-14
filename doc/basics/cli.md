# CLI

The `deeplink:*` dowel commands install the plugin, generate the `apple-app-site-association` and `assetlinks.json` files, and check that an install is wired end to end.

- [Quick Reference](#quick-reference)
- [Commands](#commands)
  - [install](#install)
  - [generate](#generate)
  - [doctor](#doctor)
- [Config Merge Strategy](#config-merge-strategy)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

The package has no `bin/` of its own. `dart run magic:dowel plugin:install magic_deeplink` registers `MagicDeeplinkDowelProvider` in `.dowel/plugins.json`, and the host app's dowel dispatcher then lists these commands:

| Command | Purpose |
|:--------|:--------|
| `dart run magic:dowel deeplink:install` | Publish `lib/config/deeplink.dart` and wire the provider and config factory. |
| `dart run magic:dowel deeplink:generate` | Write `apple-app-site-association` and `assetlinks.json`. |
| `dart run magic:dowel deeplink:doctor` | Check the config, the Dart wiring, both platform trees and the association files. |

`dart run magic:dowel list` shows what is registered.

<a name="commands"></a>
## Commands

<a name="install"></a>
### install

Runs the manifest in the package's `install.yaml` through dowel's transactional installer.

```bash
dart run magic:dowel deeplink:install
dart run magic:dowel deeplink:install --force
dart run magic:dowel deeplink:install --dry-run
```

The manifest:

1. Publishes `lib/config/deeplink.dart` from the bundled stub.
2. Adds `DeeplinkServiceProvider` and its import to the `'providers'` list in `lib/config/app.dart`.
3. Adds `() => deeplinkConfig` and `import 'config/deeplink.dart';` to the `configFactories` list in `lib/main.dart`.
4. Sets `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist`.
5. Prints the post-install message.

| Flag | Default | Description |
|:-----|:--------|:------------|
| `--force` | `false` | Bypass conflict detection and overwrite files the installer did not write or that changed since. |
| `--dry-run` | `false` | Print the staged operations without writing. |
| `--non-interactive` | `false` | Skip prompts and use defaults. |

The command exits with `0` on success or a dry run, and `1` otherwise. It does not edit the Android manifest or register a handler; see [Installation](../getting-started/installation.md).

<a name="generate"></a>
### generate

Writes the server-side verification files: `apple-app-site-association` for iOS Universal Links and `assetlinks.json` for Android App Links.

```bash
dart run magic:dowel deeplink:generate \
  --team-id ABCDE12345 \
  --bundle-id com.example.app \
  --package-name com.example.app \
  --sha256-fingerprints "AA:BB:CC:DD:..." \
  --output public/.well-known
```

#### Options

| Option | Type | Default | Description |
|:-------|:-----|:--------|:------------|
| `--output` | string | `public` | Output directory, relative to the project root. |
| `--root` | string | `.` | Project root. `.` means the project found from the working directory. |
| `--team-id` | string | none | Apple Developer Team ID. Needed for `apple-app-site-association`. |
| `--bundle-id` | string | none | iOS bundle identifier. Needed for `apple-app-site-association`. |
| `--package-name` | string | none | Android package name. Needed for `assetlinks.json`. |
| `--sha256-fingerprints` | list | none | SHA-256 certificate fingerprints. Repeat the flag or comma-separate values. Needed for `assetlinks.json`. |
| `--paths` | list | `/*` | Path patterns written into the AASA `components`. Repeat the flag or comma-separate values. |

#### Output

| File | Platform | Needs |
|:-----|:---------|:------|
| `<output>/apple-app-site-association` | iOS | `--team-id` and `--bundle-id` |
| `<output>/assetlinks.json` | Android | `--package-name` and `--sha256-fingerprints` |

Each value falls back to `lib/config/deeplink.dart` (see [Config Merge Strategy](#config-merge-strategy)). When a platform's values are still missing, that file is skipped with a warning and the command still exits with `0`, so one platform's file can be generated on its own.

`apple-app-site-association`:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<team-id>.<bundle-id>"],
        "components": [
          { "/": "/*", "comment": "Matches any URL whose path matches /*" }
        ]
      }
    ]
  }
}
```

`assetlinks.json` has one entry per fingerprint:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.app",
      "sha256_cert_fingerprints": ["AA:BB:CC:DD:..."]
    }
  }
]
```

<a name="doctor"></a>
### doctor

Checks whether an install actually works, before a device is involved. The manifest installer can publish a file and inject a line, but it cannot place an `<intent-filter>` inside a specific `<activity>` or notice a `<meta-data>` on the wrong element, and every way of getting that half wrong is silent: the link opens the browser, with no exception and no log line.

```bash
dart run magic:dowel deeplink:doctor
dart run magic:dowel deeplink:doctor --verbose
dart run magic:dowel deeplink:doctor --remote
```

#### What it checks

Local checks, always run:

1. `lib/config/deeplink.dart` exists and parses with the parser `generate` uses, and none of `domain`, `team_id`, `bundle_id`, `package_name` and `sha256_fingerprints` is still a scaffold placeholder.
2. Dart wiring: `DeeplinkServiceProvider` appears in `lib/config/app.dart` and `deeplinkConfig` in `lib/main.dart`. A missing `registerHandler(` call under `lib/` is a warning, not a failure, because handlers may be registered somewhere the scan cannot see.
3. iOS, when `ios/` exists: `FlutterDeepLinkingEnabled` is `false` in `Info.plist`, and `Runner.entitlements` carries `com.apple.developer.associated-domains` with an `applinks:` host equal to `deeplink.domain`.
4. Android, when `android/` exists: an `<intent-filter android:autoVerify="true">` inside an activity carries `VIEW`, `DEFAULT`, `BROWSABLE`, `<data>` for both `http` and `https`, and a host equal to `deeplink.domain`; and `flutter_deeplinking_enabled` is `false` inside `<activity>`, not `<application>`. The manifest is read by element position rather than searched as text, because a `<meta-data>` in the wrong element searches identically to one in the right element and does nothing.
5. The association files exist under `web/.well-known/` or `public/.well-known/` and agree with the config: the AASA claims `<team_id>.<bundle_id>`, and `assetlinks.json` lists the package name and every fingerprint. An AASA that mixes the legacy `appID` plus `paths` shape with the `appIDs` plus `components` shape is a warning.

Remote check, only with `--remote`:

6. `GET https://<domain>/.well-known/apple-app-site-association` and `.../assetlinks.json` must answer `200` with no redirect and a body that parses as JSON. An AASA served with a content type other than `application/json` is a warning. The check never runs by default, so the doctor does not hang on DNS in CI or offline.

macOS is not inspected.

#### What it cannot prove

No check can prove that a device matches a link to this app: `swcutil verify` needs root and Android verifies at install time. The report says so rather than letting a green run imply it.

#### Options and exit codes

| Flag | Default | Description |
|:-----|:--------|:------------|
| `--verbose` | `false` | Show per-issue detail under each section. |
| `--remote` | `false` | Also fetch both association files from the live domain. |

| Code | Meaning |
|:-----|:--------|
| `0` | Every check passed, or only warnings were raised. |
| `1` | At least one check failed. |

<a name="config-merge-strategy"></a>
## Config Merge Strategy

`generate` and `doctor` read `lib/config/deeplink.dart` as text, and `generate` treats its values as defaults: a flag passed on the command line wins.

| Config key | Flag |
|:-----------|:-----|
| `team_id` | `--team-id` |
| `bundle_id` | `--bundle-id` |
| `package_name` | `--package-name` |
| `sha256_fingerprints` | `--sha256-fingerprints` |
| `paths` | `--paths` |

`--paths` defaults to `/*`, and the config's `paths` replaces it only while the flag is still exactly that default and the config lists at least one path. A `--paths '/*'` typed by hand is therefore indistinguishable from no flag, and the config wins. A project can commit every identifier in the config file and run `generate` with no flags in CI.

The reader matches single-quoted literals with a regular expression, takes the first match in the file, and tolerates a generic type annotation before a list (`<String>[...]`).

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| `deeplink:*` commands are not listed. | Run `dart run magic:dowel plugin:install magic_deeplink` once; it registers the provider in `.dowel/plugins.json`. |
| Re-running `deeplink:install` fails with a conflict over `lib/config/deeplink.dart`. | The file is not one the installer wrote, or it changed since. Pass `--force` only when you mean to overwrite it. |
| `generate --output public` and the doctor still reports the association files missing. | The doctor looks in `web/.well-known/` and `public/.well-known/`. Generate with `--output public/.well-known`. |
| The config uses double quotes, or builds a value from a variable. | `generate` and `doctor` read single-quoted literals only. Keep `team_id`, `bundle_id`, `package_name`, `sha256_fingerprints`, `paths` and `domain` as plain single-quoted strings. |
| `generate` printed a warning and a file is missing from the output. | A platform's values were incomplete, and the file was skipped with exit code `0`. Supply the flags or fill the config. |
| A green doctor, and the link still opens the browser. | The doctor reads files; it cannot match a device. Test on a real device, and on the live domain with `--remote`. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](../getting-started/installation.md): the install command and the native setup the doctor checks.
- [Configuration](../getting-started/configuration.md): every key of `lib/config/deeplink.dart`.
- [Handlers](./handlers.md): registering what the doctor looks for with `registerHandler(`.
- [Magic CLI](https://anilcancakir.com/magic/docs/packages/magic-cli): the `magic:dowel` executable that dispatches plugin commands.
