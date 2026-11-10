import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/api_config.dart';
import '../services/log_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/web_fallback.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';

/// Shows a page of the Sure web app (at [ApiConfig.baseUrl] + [path]) inside
/// the app, for features that aren't native yet.
///
/// The web view uses the platform's default, persistent data store, so the
/// web session cookie survives restarts: the user signs in to the web once
/// (password and MFA typed by them; nothing is prefilled or stored by the app).
/// Links to other hosts open outside the app.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.title, required this.path});

  final String title;

  /// Server-relative path, e.g. `/goals`.
  final String path;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final Uri _initialUri = webFallbackUri(ApiConfig.baseUrl, widget.path);
  late final WebViewController _controller;
  int _progress = 0;
  bool _loading = true;
  bool _failed = false;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              _loading = true;
              _failed = false;
            });
          }
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _updateHistory();
        },
        onUrlChange: (_) => _updateHistory(),
        onWebResourceError: (error) {
          if (error.isForMainFrame == false ||
              isIgnorableWebError(error.errorCode)) {
            return;
          }
          LogService.instance.warning(
            'WebViewScreen',
            'Page load failed (${error.errorType ?? error.errorCode})',
          );
          if (mounted) {
            setState(() {
              _failed = true;
              _loading = false;
            });
          }
        },
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return NavigationDecision.navigate;
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          if (staysInAppWebView(uri, ApiConfig.baseUrl)) {
            return NavigationDecision.navigate;
          }
          _openExternally(uri);
          return NavigationDecision.prevent;
        },
      ));
    _load(_initialUri);
  }

  void _load(Uri uri) {
    // Custom proxy headers (e.g. an access gateway in front of the server)
    // ride on the first request; the gateway's own cookie covers the rest.
    _controller.loadRequest(uri, headers: ApiConfig.customProxyHeaderMap);
  }

  Future<void> _updateHistory() async {
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (mounted && (back != _canGoBack || forward != _canGoForward)) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  Future<void> _openExternally(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).shellWebOpenFailed)),
      );
    }
  }

  Future<void> _openCurrentExternally() async {
    final current = await _controller.currentUrl();
    final uri = (current == null ? null : Uri.tryParse(current)) ?? _initialUri;
    await _openExternally(uri);
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _loading = true;
      _progress = 0;
    });
    final current = await _controller.currentUrl();
    final uri = current == null || current.isEmpty || current == 'about:blank'
        ? _initialUri
        : (Uri.tryParse(current) ?? _initialUri);
    _load(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_canGoBack)
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l.shellWebBack,
              onPressed: () => _controller.goBack(),
            ),
          if (_canGoForward)
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l.shellWebForward,
              onPressed: () => _controller.goForward(),
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: isIos ? l.shellWebOpenInSafari : l.shellWebOpenInBrowser,
            onPressed: _openCurrentExternally,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading && !_failed
              ? LinearProgressIndicator(
                  value: _progress > 0 ? _progress / 100 : null,
                  minHeight: 2,
                )
              : const SizedBox(height: 2),
        ),
      ),
      body: _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(SureSpacing.xxxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SureIcon(
                      SureIcons.circleAlert,
                      size: 64,
                      color: palette.destructive,
                    ),
                    const SizedBox(height: SureSpacing.xl),
                    Text(
                      l.shellWebLoadFailed,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: SureSpacing.xxxl),
                    SureButton(
                      label: l.commonTryAgain,
                      onPressed: _retry,
                      leading: const SureIcon(SureIcons.refresh, size: 18),
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
