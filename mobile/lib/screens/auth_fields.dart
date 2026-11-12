import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';
import 'form_sheet_fields.dart';

/// Shared pieces of the sign-in screens (login, API-key sheet, SSO
/// onboarding): inline field rows for a SurePanel.rows, the destructive error
/// panel and the neutral note panel.

/// Lucide icons the auth screens use that [SureIcons] has no constant for.
abstract final class AuthIcons {
  static const String logIn = 'log-in';
  static const String link = 'link';
  static const String userPlus = 'user-plus';
  static const String scanFace = 'scan-face';
  static const String fingerprint = 'fingerprint-pattern';
  static const String mail = 'mail';
  static const String shield = 'shield';
  static const String key = 'key';
}

/// A panel row: [label] on the left and a borderless field filling the rest,
/// the same chrome as [FormSheetFieldRow] (so sign-in matches the sheet
/// forms), plus what sign-in needs: obscured text, autofill hints and a
/// trailing widget such as the show-password toggle. Validation messages
/// show under the field.
class AuthFieldRow extends StatelessWidget {
  const AuthFieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.focusNode,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autocorrect = true,
    this.enabled = true,
    this.mono = false,
    this.autofillHints,
    this.inputFormatters,
    this.trailing,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? hint;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool autocorrect;
  final bool enabled;

  /// Geist Mono with tabular figures (codes).
  final bool mono;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;

  /// Shown at the end of the row, e.g. the show-password toggle.
  final Widget? trailing;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final style = TextStyle(fontSize: 15, color: palette.textPrimary);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: 14,
          end: trailing == null ? 14 : 4,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                // A fixed label column lines the fields up; it shrinks on
                // narrow screens so the field keeps most of the row.
                width: (MediaQuery.sizeOf(context).width * 0.3)
                    .clamp(72.0, 120.0),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    fontWeight: SureTokens.weightMedium,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: fieldKey,
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                validator: validator,
                keyboardType: keyboardType,
                textInputAction: textInputAction,
                textCapitalization: textCapitalization,
                obscureText: obscureText,
                autocorrect: autocorrect && !obscureText,
                enableSuggestions: !obscureText,
                autofillHints: autofillHints,
                inputFormatters: inputFormatters,
                onFieldSubmitted: onFieldSubmitted,
                maxLines: 1,
                style: mono ? SureMoney.tabular(style) : style,
                cursorColor: palette.textPrimary,
                decoration: formSheetInlineDecoration(palette, hint: hint),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// The show/hide password toggle for an [AuthFieldRow].
class AuthPasswordToggle extends StatelessWidget {
  const AuthPasswordToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
    required this.showLabel,
    required this.hideLabel,
  });

  final bool obscured;
  final VoidCallback onPressed;
  final String showLabel;
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return SizedBox(
      width: 40,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: obscured ? showLabel : hideLabel,
        onPressed: onPressed,
        icon: SureIcon(
          obscured ? SureIcons.eye : SureIcons.eyeOff,
          size: 18,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// A sign-in error: a rounded panel with a ~12% destructive fill, an alert
/// icon, the message and an optional dismiss button.
class AuthErrorPanel extends StatelessWidget {
  const AuthErrorPanel({
    super.key,
    required this.message,
    this.onDismiss,
    this.dismissLabel,
  });

  final String message;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final color = palette.destructive;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('auth-error-panel'),
        padding: EdgeInsetsDirectional.only(
          start: 12,
          end: onDismiss == null ? 12 : 4,
          top: 10,
          bottom: 10,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(SureTokens.radiusLg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: SureIcon(SureIcons.circleAlert, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: SureTokens.weightMedium,
                  color: palette.textPrimary,
                ),
              ),
            ),
            if (onDismiss != null)
              SizedBox(
                width: 32,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: dismissLabel,
                  onPressed: onDismiss,
                  icon: SureIcon(SureIcons.x,
                      size: 16, color: palette.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A neutral note above a form (MFA prompt, SSO link instructions): an inset
/// fill with a Lucide icon and wrapped text.
class AuthNotePanel extends StatelessWidget {
  const AuthNotePanel({super.key, required this.icon, required this.message});

  final String icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: SureIcon(icon, size: 18, color: palette.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A centered quiet text link in the `link` color (e.g. "Sign in with an API
/// key", "Log out").
class AuthQuietLink extends StatelessWidget {
  const AuthQuietLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: destructive ? palette.destructive : palette.link,
          disabledForegroundColor: palette.textSubdued,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
