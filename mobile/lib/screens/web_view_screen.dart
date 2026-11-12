import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/app_localizations.dart';
import '../services/api_config.dart';
import '../services/log_service.dart';
import '../theme/sure_colors.dart';
import '../utils/web_fallback.dart';
import '../widgets/ds/ds.dart';

/// Shows a page of the Sure web app (at [ApiConfig.baseUrl] + [path]) inside
/// the app, for features that aren't native yet.
///
/// The web view uses the platform's default, persistent data store, so the
/// web session cookie survives restarts: the user signs in to the web once
/// (password and MFA typed by them; nothing is prefilled or stored by the app).
/// Links to other hosts open outside the app.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({
    super.key,
    required this.title,
    required this.path,
    this.backLabel,
  });

  final String title;

  /// Label of the back link, naming the screen that opened this one. Null
  /// shows only the chevron.
  final String? backLabel;

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

    return Scaffold(
      backgroundColor: palette.surface,
      body: Column(
        children: [
          WebViewTitleBar(
            title: widget.title,
            backLabel: widget.backLabel,
            progress: _loading && !_failed ? _progress / 100 : null,
            onWebBack: _canGoBack ? () => _controller.goBack() : null,
            onWebForward: _canGoForward ? () => _controller.goForward() : null,
            onOpenExternally: _openCurrentExternally,
          ),
          Expanded(
            child: _failed
                ? Center(
                    child: SingleChildScrollView(
                      child: SureEmptyState(
                        icon: SureIcons.cloudOff,
                        title: l.shellWebLoadFailed,
                        primaryLabel: l.commonTryAgain,
                        onPrimary: _retry,
                      ),
                    ),
                  )
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// The web view's chrome: a [SureNavBar] with a labeled back link, the
/// page title, in-page back/forward when there is history, and an "Open in
/// Safari" (or browser) action; under it a 2 px progress bar in the link
/// color while a page loads.
class WebViewTitleBar extends StatelessWidget {
  const WebViewTitleBar({
    super.key,
    required this.title,
    required this.onOpenExternally,
    this.backLabel,
    this.progress,
    this.onWebBack,
    this.onWebForward,
  });

  final String title;

  /// The back link's label, e.g. "Settings". Null shows only the chevron.
  final String? backLabel;

  /// Load progress 0–1; null hides the bar. 0 shows it indeterminate.
  final double? progress;

  /// Shown only when set (the page has history).
  final VoidCallback? onWebBack;
  final VoidCallback? onWebForward;
  final VoidCallback onOpenExternally;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final value = progress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SureNavBar(
          title: title,
          showTitle: true,
          leading: Navigator.of(context).canPop()
              ? SureBackButton(label: backLabel)
              : null,
          actions: [
            if (onWebBack != null)
              SureNavIconButton(
                icon: SureIcons.chevronLeft,
                semanticLabel: l.shellWebBack,
                onPressed: onWebBack,
              ),
            if (onWebForward != null)
              SureNavIconButton(
                icon: SureIcons.chevronRight,
                semanticLabel: l.shellWebForward,
                onPressed: onWebForward,
              ),
            SureNavIconButton(
              key: const ValueKey('webViewOpenExternally'),
              icon: isIos ? 'compass' : SureIcons.externalLink,
              semanticLabel:
                  isIos ? l.shellWebOpenInSafari : l.shellWebOpenInBrowser,
              color: palette.link,
              onPressed: onOpenExternally,
            ),
          ],
        ),
        SizedBox(
          height: 2,
          child: value == null
              ? null
              : LinearProgressIndicator(
                  key: const ValueKey('webViewProgress'),
                  value: value > 0 ? value : null,
                  minHeight: 2,
                  color: palette.link,
                  backgroundColor: Colors.transparent,
                ),
        ),
      ],
    );
  }
}
