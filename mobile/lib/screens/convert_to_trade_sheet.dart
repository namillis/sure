import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import '../services/trade_conversion_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/amount_parser.dart';
import '../utils/split_math.dart';
import '../widgets/ds/ds.dart';
import 'form_sheet_fields.dart';

/// "Convert to trade" (Sure+ `transactions.convert_to_trade`): replaces an
/// investment account's transaction with a trade, as the web's modal does.
/// Pops with `true` once the trade exists; the original transaction is then
/// excluded.
class ConvertToTradeSheet extends StatefulWidget {
  const ConvertToTradeSheet({
    super.key,
    required this.transaction,
    this.service,
  });

  final Transaction transaction;

  /// Override for tests.
  final TradeConversionService? service;

  @override
  State<ConvertToTradeSheet> createState() => _ConvertToTradeSheetState();
}

/// The "Other ticker…" choice in the security list.
const String _otherTicker = '__other__';

class _ConvertToTradeSheetState extends State<ConvertToTradeSheet> {
  late final TradeConversionService _service =
      widget.service ?? TradeConversionService();
  final _tickerController = TextEditingController();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();

  TradeConversionForm? _form;
  bool _loading = true;
  String? _loadError;
  String _label = 'Buy';
  String? _security;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    _tickerController.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String get _locale => Localizations.localeOf(context).toString();

  /// Money out of the account buys; money in sells. The server's own
  /// default agrees; the web form's is reversed.
  String _defaultLabel(TradeConversionForm form) {
    final units = SplitMath.toUnits(widget.transaction.amountDecimal);
    if (units != null && units != 0) return units > 0 ? 'Buy' : 'Sell';
    return form.defaultLabel ?? (widget.transaction.isIncome ? 'Sell' : 'Buy');
  }

  Future<void> _load() async {
    final id = widget.transaction.id;
    if (id == null || !mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final auth = context.read<AuthProvider>();
    final token = await auth.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await auth.logout();
      return;
    }
    final result = await _service.load(accessToken: token, transactionId: id);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await auth.logout();
      return;
    }
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        final form = result['form'] as TradeConversionForm;
        _form = form;
        _label = _defaultLabel(form);
        if (form.securities.isEmpty) _security = _otherTicker;
      } else {
        _loadError = _message(AppLocalizations.of(context), result);
      }
    });
  }

  /// A plain message for each 422 `error` key, else the server's message.
  String _message(AppLocalizations l, Map<String, dynamic> result) {
    return switch (result['code']) {
      'not_investment_account' => l.s4rErrNotInvestment,
      'already_converted' => l.s4rErrAlreadyConverted,
      'select_security' => l.s4rErrSelectSecurity,
      'security_not_found' => l.s4rErrSecurityNotFound,
      'enter_ticker' => l.s4rErrEnterTicker,
      'enter_qty_or_price' => l.s4rErrEnterQtyOrPrice,
      'invalid_qty_or_price' => l.s4rErrInvalidQtyOrPrice,
      _ => result['error']?.toString() ?? l.s4rLoadFailed,
    };
  }

  /// The field's canonical decimal, '' when empty, null when unparseable
  /// or not positive.
  String? _positive(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return '';
    try {
      if (AmountParser.parse(text, locale: _locale).value <= 0) return null;
      return AmountParser.canonicalize(text, locale: _locale);
    } on FormatException {
      return null;
    }
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final id = widget.transaction.id;
    if (_form == null || id == null || _submitting) return;

    final security = _security;
    final ticker = _tickerController.text.trim().toUpperCase();
    final qty = _positive(_qtyController);
    final price = _positive(_priceController);
    String? error;
    if (security == null) {
      error = l.s4rErrSelectSecurity;
    } else if (security == _otherTicker && ticker.isEmpty) {
      error = l.s4rErrEnterTicker;
    } else if (qty == '' && price == '') {
      error = l.s4rErrEnterQtyOrPrice;
    } else if (qty == null || price == null) {
      error = l.s4rErrInvalidQtyOrPrice;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final token = await auth.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await auth.logout();
      return;
    }
    final result = await _service.convert(
      accessToken: token,
      transactionId: id,
      label: _label,
      securityId: security == _otherTicker ? null : security,
      customTicker: security == _otherTicker ? ticker : null,
      qty: qty!.isEmpty ? null : qty,
      price: price!.isEmpty ? null : price,
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await auth.logout();
      return;
    }
    if (result['success'] == true) {
      SureHaptics.success();
      navigator.pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = _message(l, result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final form = _form;

    final Widget body;
    if (form == null && _loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (form == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(
              _loadError ?? l.s4rLoadFailed,
              key: const ValueKey('convertLoadError'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: palette.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              style: TextButton.styleFrom(foregroundColor: palette.link),
              child: Text(l.commonTryAgain),
            ),
          ],
        ),
      );
    } else {
      body = _buildForm(l, palette, form);
    }

    return SureSheet(
      title: l.s4rConvertToTrade,
      actionLabel: l.s4rConvert,
      actionKey: const ValueKey('convertSubmit'),
      onAction: _submit,
      actionEnabled: form != null,
      busy: _submitting,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: body,
      ),
    );
  }

  String? _securitySubtitle(TradeConversionSecurity security) {
    final parts = [
      if (security.name != null) security.name!,
      if (security.currentPrice != null) security.currentPrice!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _buildForm(
    AppLocalizations l,
    SureTokenPalette palette,
    TradeConversionForm form,
  ) {
    const amountKeyboard = TextInputType.numberWithOptions(decimal: true);
    final check = SureIcon(SureIcons.check, size: 18, color: palette.link);
    final other = _security == _otherTicker;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(
              form.amount,
              trend: MoneyTrend.neutral,
              maxLines: 1,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.transaction.name,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: palette.textSecondary),
        ),
        const SizedBox(height: 16),
        SureSegmentedControl<String>(
          selected: _label,
          onChanged: (value) => setState(() => _label = value),
          segments: [
            SureSegment(
              value: 'Buy',
              label: l.accountActionsBuy,
              icon: const SureIcon(SureIcons.plus, size: 16),
            ),
            SureSegment(
              value: 'Sell',
              label: l.accountActionsSell,
              icon: const SureIcon(SureIcons.minus, size: 16),
            ),
          ],
        ),
        SureSectionHeader(
          label: l.s4rSecurity,
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        ),
        SurePanel.rows(
          children: [
            for (final security in form.securities)
              SureListRow(
                key: ValueKey('convertSecurity-${security.id}'),
                title: security.ticker,
                subtitle: _securitySubtitle(security),
                trailing: _security == security.id ? check : null,
                onTap: () => setState(() {
                  _security = security.id;
                  _error = null;
                }),
              ),
            SureListRow(
              key: const ValueKey('convertOtherTicker'),
              title: l.s4rOtherTicker,
              trailing: other ? check : null,
              onTap: () => setState(() {
                _security = _otherTicker;
                _error = null;
              }),
            ),
            if (other)
              FormSheetFieldRow(
                fieldKey: const ValueKey('convertTicker'),
                label: l.s4rTicker,
                controller: _tickerController,
                hint: form.tickerSearchAvailable
                    ? l.s4rTickerHint
                    : l.s4rExactTickerHint,
                textCapitalization: TextCapitalization.characters,
              ),
          ],
        ),
        const SizedBox(height: 16),
        SurePanel.rows(
          children: [
            FormSheetFieldRow(
              fieldKey: const ValueKey('convertShares'),
              label: l.s4rShares,
              controller: _qtyController,
              hint: l.ds3fOptional,
              keyboardType: amountKeyboard,
              mono: true,
            ),
            FormSheetFieldRow(
              fieldKey: const ValueKey('convertPrice'),
              label: l.ds3fPrice,
              controller: _priceController,
              hint: l.ds3fOptional,
              keyboardType: amountKeyboard,
              suffix: form.currency.isEmpty ? null : form.currency,
              mono: true,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l.s4rSharesOrPriceNote,
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('convertError'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: palette.destructive),
              ),
            ),
          ),
      ],
    );
  }
}

/// Whether the transaction screen offers "Convert to trade": the server has
/// the feature, the transaction sits in an investment account the user owns
/// or fully controls, and it isn't excluded (already converted or split).
bool canConvertToTrade({
  required bool feature,
  required Transaction? transaction,
  required String? accountType,
  required bool? accountCanEdit,
}) {
  if (!feature || transaction == null || transaction.id == null) return false;
  if (transaction.excluded == true) return false;
  final type = transaction.accountType ?? accountType;
  return type == 'investment' && accountCanEdit != false;
}

/// The "Convert to trade" action row. Opens [ConvertToTradeSheet] and calls
/// [onConverted] once the trade exists.
class ConvertToTradePanel extends StatelessWidget {
  const ConvertToTradePanel({
    super.key,
    required this.transaction,
    required this.enabled,
    required this.onConverted,
    this.service,
  });

  final Transaction transaction;
  final bool enabled;
  final VoidCallback onConverted;
  final TradeConversionService? service;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SurePanel.rows(children: [
      SureListRow(
        key: const ValueKey('transaction-convert-to-trade-row'),
        title: l.s4rConvertToTrade,
        titleColor: palette.link,
        enabled: enabled,
        onTap: enabled
            ? () async {
                final converted = await showSureSheet<bool>(
                  context: context,
                  builder: (_) => ConvertToTradeSheet(
                    transaction: transaction,
                    service: service,
                  ),
                );
                if (converted == true) onConverted();
              }
            : null,
      ),
    ]);
  }
}
