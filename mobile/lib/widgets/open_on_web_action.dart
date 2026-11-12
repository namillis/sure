import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/web_view_screen.dart';

/// AppBar action that opens [path] of the Sure web app in the in-app web view,
/// for screens whose full feature set only exists on the web.
///
/// ```dart
/// AppBar(actions: const [OpenOnWebAction(path: '/budgets')])
/// ```
class OpenOnWebAction extends StatelessWidget {
  const OpenOnWebAction({super.key, required this.path, this.title});

  /// Server-relative path, e.g. `/goals`.
  final String path;

  /// Web view title; defaults to the app name.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IconButton(
      icon: const Icon(Icons.language),
      tooltip: l.shellOpenOnWeb,
      onPressed: () => openWebFallback(context, title: title ?? l.appTitle, path: path),
    );
  }
}

/// Pushes a [WebViewScreen] for [path]. [backLabel] names the screen the
/// back link returns to; without it the link reads "Back".
Future<void> openWebFallback(
  BuildContext context, {
  required String title,
  required String path,
  String? backLabel,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          WebViewScreen(title: title, path: path, backLabel: backLabel),
    ),
  );
}
