import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';

/// Shared pieces of the sheet forms (new transaction, trade, update balance):
/// the big centered amount field and the inline-field panel row.

/// A borderless field that reads as text until focused; errors still show
/// under it in the destructive color.
InputDecoration formSheetInlineDecoration(
  SureTokenPalette palette, {
  String? hint,
  String? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: palette.textSubdued),
    isDense: true,
    filled: false,
    counterText: '',
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    errorStyle: TextStyle(color: palette.destructive),
    errorMaxLines: 2,
    suffixText: suffix,
    suffixStyle: TextStyle(fontSize: 15, color: palette.textSecondary),
  );
}

/// "0.00" in the locale's number format, as the amount placeholder.
String formSheetAmountHint(BuildContext context) {
  final locale = Localizations.localeOf(context).toString();
  return NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 2)
      .format(0);
}

/// The large centered mono amount field (32 pt), focused on open with the
/// decimal keyboard.
class FormSheetAmountField extends StatelessWidget {
  const FormSheetAmountField({
    super.key,
    required this.controller,
    required this.validator,
    this.suffix,
    this.signed = false,
    this.obscure = false,
    this.enabled = true,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  /// Shown after the number, e.g. the account currency.
  final String? suffix;

  /// Allow a minus sign (balances can be negative).
  final bool signed;
  final bool obscure;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: obscure,
      validator: validator,
      textAlign: TextAlign.center,
      keyboardType:
          TextInputType.numberWithOptions(decimal: true, signed: signed),
      textInputAction: TextInputAction.done,
      style: SureMoney.tabular(TextStyle(
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      )),
      decoration: formSheetInlineDecoration(
        palette,
        hint: formSheetAmountHint(context),
        suffix: suffix,
      ),
    );
  }
}

/// A panel row with [label] on the left and an inline text field filling the
/// rest, right-aligned. Validation messages show under the field.
class FormSheetFieldRow extends StatelessWidget {
  const FormSheetFieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.next,
    this.suffix,
    this.mono = false,
    this.maxLines = 1,
    this.enabled = true,
    this.focusNode,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final String? suffix;

  /// Numbers in Geist Mono with tabular figures.
  final bool mono;
  final int maxLines;
  final bool enabled;
  final FocusNode? focusNode;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final style = TextStyle(fontSize: 15, color: palette.textPrimary);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                ),
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
                textCapitalization: textCapitalization,
                textInputAction: textInputAction,
                onFieldSubmitted: onFieldSubmitted,
                textAlign: TextAlign.end,
                minLines: 1,
                maxLines: maxLines,
                style: mono ? SureMoney.tabular(style) : style,
                decoration: formSheetInlineDecoration(
                  palette,
                  hint: hint,
                  suffix: suffix,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
