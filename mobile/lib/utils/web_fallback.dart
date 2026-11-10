/// Pure helpers for the in-app web view that stands in for features the app
/// doesn't have natively yet. Kept free of Flutter and plugin types so they can
/// be unit tested.
library;

/// Builds the absolute URL of [path] (for example `/goals` or
/// `/settings/profile?tab=x`) on the Sure server at [baseUrl].
///
/// Keeps any sub-path in [baseUrl] (`https://host/sure` + `/goals` gives
/// `https://host/sure/goals`) and tolerates a trailing slash on the base or a
/// missing leading slash on the path.
Uri webFallbackUri(String baseUrl, String path) {
  final base = Uri.parse(baseUrl.trim());
  var basePath = base.path;
  while (basePath.endsWith('/')) {
    basePath = basePath.substring(0, basePath.length - 1);
  }
  final relative = Uri.parse(path.startsWith('/') ? path : '/$path');
  return Uri(
    scheme: base.scheme,
    userInfo: base.userInfo,
    host: base.host,
    port: base.hasPort ? base.port : null,
    path: '$basePath${relative.path}',
    query: relative.hasQuery ? relative.query : null,
    fragment: relative.hasFragment ? relative.fragment : null,
  );
}

/// Whether a main-frame navigation to [uri] stays inside the in-app web view.
///
/// Pages on the Sure server's own host stay in-app (so the web session cookie
/// is reused). Links to any other host, and non-web schemes like `mailto:` or
/// `tel:`, open outside the app. `about:`, `data:` and `blob:` pages are
/// in-page plumbing and stay in-app.
bool staysInAppWebView(Uri uri, String baseUrl) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'about' || scheme == 'data' || scheme == 'blob') return true;
  if (scheme != 'http' && scheme != 'https') return false;
  final baseHost = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';
  return baseHost.isNotEmpty && uri.host.toLowerCase() == baseHost;
}

/// Whether a web view load error is noise rather than a failed page: iOS
/// reports a cancelled load (-999, NSURLErrorCancelled) and a load interrupted
/// by a policy decision (102, e.g. after we send a link to Safari).
bool isIgnorableWebError(int errorCode) =>
    errorCode == -999 || errorCode == 102;
