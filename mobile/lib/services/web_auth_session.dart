import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';

import 'log_service.dart';

/// How a web handoff ended: the `status` of
/// `sureplus://connections/done?status=ok|cancelled|error`, or [closed] when
/// the user closed the browser sheet before the web sent the app back.
enum WebHandoffStatus { ok, cancelled, error, closed }

/// Opens a web handoff URL in a browser sheet and waits for the server to
/// send the app back to `sureplus://`. Behind an interface so tests can fake
/// the callback.
abstract class WebAuthSession {
  const WebAuthSession();

  static const callbackScheme = 'sureplus';

  /// Opens [url] and returns how the flow ended.
  Future<WebHandoffStatus> open(Uri url);

  /// The status in a `sureplus://connections/done?status=` callback. Anything
  /// else counts as an error.
  static WebHandoffStatus parseCallback(Uri? callback) {
    if (callback == null) return WebHandoffStatus.closed;
    if (callback.scheme != callbackScheme ||
        callback.host != 'connections' ||
        callback.path != '/done') {
      return WebHandoffStatus.error;
    }
    return switch (callback.queryParameters['status']) {
      'ok' => WebHandoffStatus.ok,
      'cancelled' => WebHandoffStatus.cancelled,
      _ => WebHandoffStatus.error,
    };
  }
}

/// `ASWebAuthenticationSession` on iOS (through `flutter_web_auth_2`), with a
/// shared (not ephemeral) browser session: Plaid's OAuth banks open the
/// bank's own site and send the browser back, which needs a full browser.
///
/// ASWebAuthenticationSession catches the callback scheme itself, so
/// `sureplus` needs no `CFBundleURLTypes` entry. Elsewhere the URL opens in
/// the system browser and the result is [WebHandoffStatus.closed].
class AppWebAuthSession extends WebAuthSession {
  const AppWebAuthSession();

  @override
  Future<WebHandoffStatus> open(Uri url) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      // shortcut: no Android callback activity is registered, so the app
      // can't hear the return; the caller refreshes instead.
      await launchUrl(url, mode: LaunchMode.externalApplication);
      return WebHandoffStatus.closed;
    }
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: WebAuthSession.callbackScheme,
        options: const FlutterWebAuth2Options(preferEphemeral: false),
      );
      return WebAuthSession.parseCallback(Uri.tryParse(result));
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return WebHandoffStatus.closed;
      // Only the code: the message must never carry the URL.
      LogService.instance.error('WebAuthSession', 'failed: ${e.code}');
      return WebHandoffStatus.error;
    }
  }
}
