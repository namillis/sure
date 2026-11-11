import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../sure_icon.dart';

/// Inset-filled rounded search field with a Lucide search icon and a clear
/// button that shows while there is text.
///
/// Pass a [controller] to read or set the text; one is created otherwise.
/// [onChanged] fires on every edit and with '' when cleared.
class SureSearchField extends StatefulWidget {
  const SureSearchField({
    super.key,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.clearSemanticLabel,
  });

  /// Placeholder, e.g. "Search transactions".
  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Screen reader label of the clear button. Defaults to the Material
  /// localized "Clear" (via the delete-button tooltip).
  final String? clearSemanticLabel;

  @override
  State<SureSearchField> createState() => _SureSearchFieldState();
}

class _SureSearchFieldState extends State<SureSearchField> {
  TextEditingController? _owned;

  TextEditingController get _controller =>
      widget.controller ?? (_owned ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(SureSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _owned)?.removeListener(_onText);
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _owned?.dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final hasText = _controller.text.isNotEmpty;
    final clearLabel = widget.clearSemanticLabel ??
        MaterialLocalizations.of(context).deleteButtonTooltip;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          SureIcon(SureIcons.search, size: 16, color: palette.textSubdued),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              maxLines: 1,
              style: TextStyle(fontSize: 15, color: palette.textPrimary),
              cursorColor: palette.link,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hintText,
                hintMaxLines: 1,
                hintStyle: TextStyle(fontSize: 15, color: palette.textSubdued),
              ),
            ),
          ),
          if (hasText)
            Semantics(
              button: true,
              label: clearLabel,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clear,
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Center(
                    child: SureIcon(
                      SureIcons.circleX,
                      size: 16,
                      color: palette.textSubdued,
                    ),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }
}
