import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:magic/magic.dart';

import 'deeplink_driver.dart';

/// `dart:io` arm of the platform trio: Android, iOS, macOS, and any other
/// target where `dart:io` resolves.
///
/// Delegates to the `app_links` package for both the initial link and the
/// live link stream; it is the only arm of the three that talks to a real
/// platform channel.
class AppLinksDriver extends DeeplinkDriver {
  /// Creates the driver.
  ///
  /// [isIOS], [isAndroid] and [isMacOS] exist for tests: a `flutter test` run
  /// is always on a desktop host, so without them the iOS and Android answers
  /// could never be reached from a Linux CI machine. Each defaults to the
  /// host's `Platform` value.
  AppLinksDriver({this._isIOS, this._isAndroid, this._isMacOS});

  final bool? _isIOS;
  final bool? _isAndroid;
  final bool? _isMacOS;

  /// The `app_links` package instance, created in [initialize].
  late final AppLinks _appLinks;

  @override
  String get name => 'app_links';

  /// False on tvOS, which reports itself as iOS but has no `app_links` half:
  /// its link stream throws. The tvOS check comes first for that reason.
  ///
  /// No try/catch: this file compiles only where `dart.library.io` resolves,
  /// so `Platform` is real here and these getters cannot throw. The guard this
  /// replaced existed to survive the web build, and the web arm now takes that
  /// case instead.
  @override
  bool get isSupported {
    if (MagicPlatform.isTvOS) {
      return false;
    }

    return (_isAndroid ?? Platform.isAndroid) ||
        (_isIOS ?? Platform.isIOS) ||
        (_isMacOS ?? Platform.isMacOS);
  }

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    _appLinks = AppLinks();
  }

  @override
  Future<Uri?> getInitialLink() async {
    try {
      return await _appLinks.getInitialLink();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Uri> get onLink => _appLinks.uriLinkStream;

  @override
  void dispose() {
    // AppLinks does not require explicit disposal of the instance itself.
  }
}
