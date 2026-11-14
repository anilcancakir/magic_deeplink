---
paths:
  - "lib/src/cli/**/*.dart"
---

# CLI Domain

Commands extend `DowelCommand` from `dowel`:

- **Base class**: `DowelCommand` — implement `signature` DSL, `description`, `boot` property, `Future<int> handle(DowelContext ctx)`
- **Signature DSL**: `'name {argument} {--option}'` — define command name, arguments, flags, and options in one property
- **Install command**: extend `DowelInstallCommand` (abstract) — implement `pluginName(DowelContext)`, drive `install.yaml` manifest
- **Context**: `DowelContext` provides `output` (logging), `input` (parsed args), `buildContext` (host app data), `isDryRun`, `isForce` properties
- **Manifest-driven install**: `install.yaml` at package root defines what to publish, which providers to inject, config factories. See dowel schema docs (dowel/doc/plugins/install-yaml.md).
- **Transactional DSL**: `installer.writeFile(path, content)` (atomic, rollback-safe), `installer.injectImport(file, import)` (via ConfigEditor), `installer.publishConfig(stub, target)`, `installer.native(...)` (platform-specific). Stage these in `_applyFluentOverride()` before calling `installer.commit(dryRun: isDryRun, force: isForce)`.
- **Helper-backed mutations**: `ConfigEditor.addImportToFile()`, `HtmlEditor.addHeadTag()` etc. are synchronous + not rolled back — order them AFTER transactional writes to avoid partial-failure exposure.
- **Stub loading**: `StubLoader.load('install/deeplink_config', searchPaths: paths)` — searches `assets/stubs/` directory
- **File operations**: install-flow file writes go through `FileHelper` or the transactional installer; the generate command writes the platform association files (apple-app-site-association, assetlinks.json) directly via `dart:io`
- **Testability**: override `getProjectRoot()` and `getStubSearchPaths()` in test subclasses for temp dirs
- **Pure parsers/builders**: `parseDeeplinkConfig()`, `buildAppleAppSiteAssociation()`, `buildAssetLinks()` are public, stateless, testable independently
- **CLI flags override config file values**: read config first, let args take precedence
- **Exit codes**: return 0 on success, 1 on user error, other codes for internal failures. Use `ctx.output.error(message)` before returning non-zero.
- **NO MCP TOOLS**: deeplink ships only mutating commands (install, generate); `MagicDeeplinkDowelProvider` registers no MCP tools.
