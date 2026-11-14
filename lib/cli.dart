/// Flutter-free dowel-CLI surface for magic_deeplink.
///
/// Exposes ONLY the dowel-CLI surface (MagicDeeplinkDowelProvider + the
/// CLI commands). Does NOT export magic_deeplink runtime (no Flutter dart:ui
/// imports), so this barrel is safe for consumption from pure-Dart dowel
/// dispatchers.
///
/// `plugin:install` registers the provider in the consumer's
/// `bin/dispatcher.dart`; wiring it by hand looks like:
///
/// ```dart
/// import 'package:dowel/dowel.dart';
/// import 'package:magic_deeplink/cli.dart' show MagicDeeplinkDowelProvider;
///
/// Future<void> main(List<String> args) async {
///   final registry = DowelRegistry()
///     ..registerProvider(MagicDeeplinkDowelProvider());
///   exit(await DowelApplication(registry: registry).dispatch(args));
/// }
/// ```
///
/// Runtime consumers (lib/main.dart of a Magic-based app) continue to
/// import `package:magic_deeplink/magic_deeplink.dart` for the full surface.
library;

export 'src/cli/commands/doctor_command.dart';
export 'src/cli/commands/generate_command.dart';
export 'src/cli/commands/install_command.dart';
export 'src/cli/deeplink_dowel_provider.dart';
