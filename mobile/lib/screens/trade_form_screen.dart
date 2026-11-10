import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_trade.dart';
import '../models/trade_security.dart';
import '../providers/auth_provider.dart';
import '../services/trades_service.dart';
import '../utils/amount_parser.dart';
import '../utils/investment_math.dart';
import '../widgets/form_error_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_segmented_control.dart';
import '../widgets/sure_text_field.dart';

enum TradeSide { buy, sell }

/// Cash total of a trade the way the server books it: a buy costs
/// qty × price + fee; a sell brings in qty × price − fee.
double tradeTotal({
  required double qty,
  required double price,
  double fee = 0,
  required TradeSide side,
}) {
  final gross = qty * price;
  return side == TradeSide.buy ? gross + fee : gross - fee;
}

/// Opens the editor for [trade]. Buys and sells get the full form; other
/// activity (dividends, interest...) can only be deleted, since the update
/// API would rewrite it as a buy or sell. Resolves `true` when the trade
/// changed.
Future<bool> openTradeEditor(
  BuildContext context, {
  required Account account,
  required AccountTrade trade,
  TradesService? tradesService,
}) async {
  if (TradeFormScreen.canEdit(trade)) {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TradeFormScreen(
          account: account,
          trade: trade,
          tradesService: tradesService,
        ),
      ),
    );
    return changed == true;
  }
  final service = tradesService ?? TradesService();
  try {
    return await _confirmAndDelete(context, service, trade);
  } finally {
    if (tradesService == null) service.close();
  }
}

Future<bool> _confirmAndDelete(
  BuildContext context,
  TradesService service,
  AccountTrade trade,
) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final authProvider = context.read<AuthProvider>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.accountActionsDeleteTrade),
      content: Text(l.accountActionsDeleteTradeConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.commonDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final token = await authProvider.getValidAccessToken();
  if (token == null) {
    await authProvider.logout();
    return false;
  }
  final result =
      await service.deleteTrade(accessToken: token, tradeId: trade.id);
  if (result['error'] == 'unauthorized') {
    await authProvider.logout();
    return false;
  }
  final ok = result['success'] == true;
  messenger.showSnackBar(SnackBar(
    content: Text(
        ok ? l.accountActionsTradeDeleted : result['error']?.toString() ?? ''),
  ));
  return ok;
}

/// Adds a buy or sell to [account], or edits [trade] when given. Pops `true`
/// when the server saved (or deleted) the trade.
class TradeFormScreen extends StatefulWidget {
  const TradeFormScreen({
    super.key,
    required this.account,
    this.trade,
    this.tradesService,
  });

  final Account account;
  final AccountTrade? trade;
  final TradesService? tradesService;

  /// Buys and sells only; see [openTradeEditor].
  static bool canEdit(AccountTrade trade) {
    final label = trade.activityLabel?.trim().toLowerCase();
    final qty = InvestmentMath.parse(trade.quantity) ?? 0;
    return qty != 0 && (label == null || label == 'buy' || label == 'sell');
  }

  @override
  State<TradeFormScreen> createState() => _TradeFormScreenState();
}

class _TradeFormScreenState extends State<TradeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tickerController = TextEditingController();
  final _tickerFocus = FocusNode();
  final _qtyController = TextEditingController();
  final _priceController = TextEditingController();
  final _feeController = TextEditingController();
  final _dateController = TextEditingController();
  late final TradesService _service =
      widget.tradesService ?? TradesService();

  TradeSide _side = TradeSide.buy;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  List<TradeSecurity> _securities = const [];
  TradeSecurity? _selectedSecurity;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.trade != null;

  @override
  void initState() {
    super.initState();
    final trade = widget.trade;
    if (trade != null) {
      final qty = InvestmentMath.parse(trade.quantity) ?? 0;
      _side = trade.activityLabel?.toLowerCase() == 'sell' || qty < 0
          ? TradeSide.sell
          : TradeSide.buy;
      _qtyController.text = _plain(qty.abs());
      _priceController.text = _plain(InvestmentMath.parse(trade.price) ?? 0);
      _tickerController.text = trade.ticker ?? trade.securityName ?? trade.name;
      _date = DateUtils.dateOnly(trade.date);
    } else {
      _loadSecurities();
    }
    for (final c in [_qtyController, _priceController, _feeController]) {
      c.addListener(_onAmountChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dateController.text = DateFormat.yMMMd(_locale).format(_date);
  }

  @override
  void dispose() {
    for (final c in [
      _tickerController,
      _qtyController,
      _priceController,
      _feeController,
      _dateController,
    ]) {
      c.dispose();
    }
    _tickerFocus.dispose();
    if (widget.tradesService == null) _service.close();
    super.dispose();
  }

  void _onAmountChanged() => setState(() {});

  String get _locale => Localizations.localeOf(context).toString();

  static String _plain(double value) => value
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');

  Future<void> _loadSecurities() async {
    final token = await context.read<AuthProvider>().getValidAccessToken();
    if (token == null || !mounted) return;
    final result = await _service.getSecurities(accessToken: token);
    if (!mounted || result['success'] != true) return;
    setState(() => _securities = result['securities'] as List<TradeSecurity>);
  }

  /// Parses a field as a number, or null when empty or not a number.
  double? _number(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    try {
      return AmountParser.parse(text, locale: _locale).value;
    } on FormatException {
      return null;
    }
  }

  String? _validatePositive(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l.accountActionsRequired;
    try {
      final parsed = AmountParser.parse(value, locale: _locale);
      if (parsed.value <= 0) return l.accountActionsMustBePositive;
    } on FormatException {
      return l.accountActionsInvalidNumber;
    }
    return null;
  }

  String? _validateFee(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final l = AppLocalizations.of(context);
    try {
      if (AmountParser.parse(value, locale: _locale).value < 0) {
        return l.accountActionsFeeInvalid;
      }
    } on FormatException {
      return l.accountActionsInvalidNumber;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateController.text = DateFormat.yMMMd(_locale).format(picked);
    });
  }

  String _canonical(TextEditingController c) =>
      AmountParser.canonicalize(c.text, locale: _locale);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authProvider = context.read<AuthProvider>();

    setState(() {
      _submitting = true;
      _error = null;
    });

    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await authProvider.logout();
      return;
    }

    final type = _side.name;
    final date = DateFormat('yyyy-MM-dd').format(_date);
    final Map<String, dynamic> result;
    if (_isEdit) {
      result = await _service.updateTrade(
        accessToken: token,
        tradeId: widget.trade!.id,
        type: type,
        date: date,
        qty: _canonical(_qtyController),
        price: _canonical(_priceController),
      );
    } else {
      final ticker = _tickerController.text.trim().toUpperCase();
      final selected = _selectedSecurity;
      final useSelected =
          selected != null && selected.ticker.toUpperCase() == ticker;
      result = await _service.createTrade(
        accessToken: token,
        accountId: widget.account.id,
        type: type,
        date: date,
        qty: _canonical(_qtyController),
        price: _canonical(_priceController),
        fee: _feeController.text.trim().isEmpty
            ? null
            : _canonical(_feeController),
        securityId: useSelected ? selected.id : null,
        ticker: useSelected ? null : ticker,
        currency: widget.account.currency,
      );
    }
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            _isEdit ? l.accountActionsTradeUpdated : l.accountActionsTradeAdded),
      ));
      navigator.pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result['error']?.toString();
    });
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final deleted = await _confirmAndDelete(context, _service, widget.trade!);
    if (deleted && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final qty = _number(_qtyController);
    final price = _number(_priceController);
    final fee = _isEdit ? 0.0 : (_number(_feeController) ?? 0);
    final total = qty == null || price == null
        ? null
        : tradeTotal(qty: qty, price: price, fee: fee, side: _side);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isEdit ? l.accountActionsEditTrade : l.accountActionsAddTrade),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l.accountActionsDeleteTrade,
              onPressed: _submitting ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SureSegmentedControl<TradeSide>(
                selected: _side,
                onChanged: (side) => setState(() => _side = side),
                segments: [
                  SureSegment(
                    value: TradeSide.buy,
                    label: l.accountActionsBuy,
                    icon: const Icon(Icons.add),
                  ),
                  SureSegment(
                    value: TradeSide.sell,
                    label: l.accountActionsSell,
                    icon: const Icon(Icons.remove),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isEdit)
                SureTextField(
                  controller: _tickerController,
                  label: l.accountActionsSecurity,
                  readOnly: true,
                  enabled: false,
                  helperText: l.accountActionsEditTradeNote,
                )
              else
                _securityField(l),
              const SizedBox(height: 16),
              SureTextField(
                key: const ValueKey('tradeQuantity'),
                controller: _qtyController,
                label: l.accountActionsQuantity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _validatePositive,
              ),
              const SizedBox(height: 16),
              SureTextField(
                key: const ValueKey('tradePrice'),
                controller: _priceController,
                label: l.accountActionsPrice,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(widget.account.currency),
                ),
                validator: _validatePositive,
              ),
              const SizedBox(height: 16),
              if (!_isEdit) ...[
                SureTextField(
                  key: const ValueKey('tradeFee'),
                  controller: _feeController,
                  label: l.accountActionsFee,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(widget.account.currency),
                  ),
                  validator: _validateFee,
                ),
                const SizedBox(height: 16),
              ],
              SureTextField(
                controller: _dateController,
                label: l.accountActionsDate,
                readOnly: true,
                prefixIcon: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _side == TradeSide.buy
                            ? l.accountActionsTotalCost
                            : l.accountActionsTotalProceeds,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      total == null
                          ? '—'
                          : InvestmentMath.formatMoney(
                              total,
                              currency: widget.account.currency,
                              locale: _locale,
                            ),
                      key: const ValueKey('tradeTotal'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 24),
              SureButton(
                label: l.accountActionsSave,
                onPressed: _submitting ? null : _submit,
                loading: _submitting,
                fullWidth: true,
                size: SureButtonSize.lg,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityField(AppLocalizations l) {
    return RawAutocomplete<TradeSecurity>(
      textEditingController: _tickerController,
      focusNode: _tickerFocus,
      displayStringForOption: (s) => s.ticker,
      optionsBuilder: (value) => value.text.trim().isEmpty
          ? const Iterable<TradeSecurity>.empty()
          : _securities.where((s) => s.matches(value.text)).take(8),
      onSelected: (s) => setState(() => _selectedSecurity = s),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          SureTextField(
        key: const ValueKey('tradeTicker'),
        controller: controller,
        focusNode: focusNode,
        label: l.accountActionsSecurity,
        hint: l.accountActionsSecurityHint,
        textCapitalization: TextCapitalization.characters,
        validator: (v) => v == null || v.trim().isEmpty
            ? l.accountActionsSecurityRequired
            : null,
        onFieldSubmitted: (_) => onSubmitted(),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    title: Text(option.ticker),
                    subtitle: option.name == null ? null : Text(option.name!),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
