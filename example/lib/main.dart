import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

const Color _ink = Color(0xFF111827);
const Color _accent = Color(0xFF4F46E5);
const TextStyle _text = TextStyle(color: _ink, fontSize: 16);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configs: [
      {
        'app': {
          'providers': [
            (app) => DeeplinkServiceProvider(app),
            (app) => ExampleServiceProvider(app),
          ],
        },
        'deeplink': {
          'enabled': true,
          'driver': 'app_links',
          // Only links on this host are claimed by the handler below.
          'domain': 'example.com',
        },
      },
    ],
  );

  runApp(const ExampleApp());
}

/// Registers the two pages and the handler that opens one of them.
///
/// `DeeplinkServiceProvider` registers no handler of its own, because it
/// cannot know which paths an app serves.
class ExampleServiceProvider extends ServiceProvider {
  ExampleServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    MagicRoute.page('/', () => const HomePage());
    MagicRoute.page(
      '/monitors/:id',
      (String id) => MonitorPage(id: id),
    ).stacked();

    DeeplinkManager().registerHandler(
      RouteDeeplinkHandler(
        paths: ['/monitors/:id'],
        hosts: [Config.getOrFail<String>('deeplink.domain')],
      ),
    );
  }
}

/// The app shell: Magic's router behind a plain `WidgetsApp`.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp.router(
      title: 'magic_deeplink example',
      color: _accent,
      textStyle: _text,
      routerConfig: MagicRouter.instance.routerConfig,
    );
  }
}

/// A text field holding a link, an Open button, and what the manager saw.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _input = TextEditingController(
    text: 'https://example.com/monitors/42',
  );
  final FocusNode _focus = FocusNode();
  final List<String> _seen = <String>[];

  late final StreamSubscription<Uri> _links;

  String _result = '';

  @override
  void initState() {
    super.initState();

    // Every URI handed to `handleUri`, claimed or not.
    _links = DeeplinkManager().onLink.listen((Uri uri) {
      setState(() => _seen.insert(0, '$uri'));
    });
  }

  @override
  void dispose() {
    unawaited(_links.cancel());
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Hands the typed link to the chain the way the provider hands it an OS
  /// link, with `manual` as the source because the app asked for it itself.
  Future<void> _open() async {
    final Uri? uri = Uri.tryParse(_input.text.trim());

    if (uri == null) {
      setState(() => _result = 'Not a URI.');
      return;
    }

    final bool handled = await DeeplinkManager().handleUri(
      uri,
      source: DeeplinkSource.manual,
    );

    if (!mounted) return;

    setState(
      () =>
          _result = handled ? 'Opened ${uri.path}.' : 'No handler claimed it.',
    );
  }

  /// What the provider wired on this platform.
  ///
  /// `driver` throws `DeeplinkException` when nothing was wired: web, Windows
  /// and Linux report `AppLinksDriver` as unsupported, so no link ever
  /// arrives there.
  String _driverStatus() {
    try {
      return 'driver: ${DeeplinkManager().driver.name}';
    } on DeeplinkException {
      return 'driver: none wired on this platform';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_driverStatus()),
            const SizedBox(height: 16),
            const Text('A link to open'),
            const SizedBox(height: 8),
            EditableText(
              controller: _input,
              focusNode: _focus,
              style: _text,
              cursorColor: _accent,
              backgroundCursorColor: _ink,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: _Button(label: 'Open link', onTap: _open),
            ),
            const SizedBox(height: 16),
            Text(_result),
            const SizedBox(height: 16),
            const Text('Seen by the manager'),
            for (final String uri in _seen) Text(uri),
          ],
        ),
      ),
    );
  }
}

/// The page the handler opens for `/monitors/:id`.
class MonitorPage extends StatelessWidget {
  const MonitorPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Monitor $id'),
            const SizedBox(height: 16),
            _Button(label: 'Back', onTap: MagicRoute.back),
          ],
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: _accent,
        child: Text(label, style: const TextStyle(color: Color(0xFFFFFFFF))),
      ),
    );
  }
}
