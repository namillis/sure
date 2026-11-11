import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account_holding.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/security_prices_service.dart';
import '../utils/amount_parser.dart';
import '../utils/money_masker.dart';
import 'form_error_text.dart';
import 'sure_button.dart';
import 'sure_text_field.dart';

/// Opens [SetPriceSheet] for [holding]. Resolves to true once the server
/// stored the price. Holdings without a security id cannot be priced and
/// resolve to false without opening anything.
Future<bool> showSetPriceSheet(
  BuildContext context, {
  required AccountHolding holding,
  SecurityPricesService? service,
}) async {
  if (holding.securityId == null) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => SetPriceSheet(holding: holding, service: service),
  );
  return saved == true;
}

/// Records a manual closing price for a holding's security, in the holding's
/// currency, on a date (today by default). Pops `true` on success.
class SetPriceSheet extends StatefulWidget {
  const SetPriceSheet({super.key, required this.holding, this.service});

  final AccountHolding holding;
  final SecurityPricesService? service;

  @override
  State<SetPriceSheet> createState() => _SetPriceSheetState();
}

class _SetPriceSheetState extends State<SetPriceSheet> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _dateController = TextEditingController();
  late final SecurityPricesService _service =
      widget.service ?? SecurityPricesService();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _submitting = false;
  String? _error;

  String get _locale => Localizations.localeOf(context).toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dateController.text = DateFormat.yMMMd(_locale).format(_date);
  }

  @override
  void dispose() {
    _priceController.dispose();
    _dateController.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  String? _validatePrice(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l.p3apPriceRequired;
    try {
      if (AmountParser.parse(value, locale: _locale).value <= 0) {
        return l.p3apPriceInvalid;
      }
    } on FormatException {
      return l.p3apPriceInvalid;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateController.text = DateFormat.yMMMd(_locale).format(picked);
    });
  }

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

    final result = await _service.createPrice(
      accessToken: token,
      securityId: widget.holding.securityId!,
      price: AmountParser.canonicalize(_priceController.text, locale: _locale),
      date: DateFormat('yyyy-MM-dd').format(_date),
      currency: widget.holding.currency,
    );
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.p3apPriceSaved)));
      navigator.pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = switch (result['code']) {
        SecurityPricesService.selfHostedOnly => l.p3apPriceSelfHostedOnly,
        SecurityPricesService.notFound => l.p3apPriceNotAllowed,
        _ => result['error']?.toString(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final holding = widget.holding;
    final title = [holding.ticker, holding.securityName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' · ');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(l.p3apSetPriceTitle, style: theme.textTheme.titleLarge),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(title, style: theme.textTheme.titleSmall),
            ],
            const SizedBox(height: 4),
            Text(
              l.p3apCurrentPrice(
                  MoneyMasker.mask(holding.price, hidden: hidden)),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.p3apSetPriceIntro,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SureTextField(
              key: const ValueKey('setPriceAmount'),
              controller: _priceController,
              label: l.p3apPriceLabel,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(holding.currency),
              ),
              validator: _validatePrice,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            SureTextField(
              key: const ValueKey('setPriceDate'),
              controller: _dateController,
              label: l.accountActionsDate,
              readOnly: true,
              prefixIcon: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              FormErrorText(_error!),
            ],
            const SizedBox(height: 24),
            SureButton(
              key: const ValueKey('setPriceSave'),
              label: l.accountActionsSave,
              onPressed: _submitting ? null : _submit,
              loading: _submitting,
              fullWidth: true,
              size: SureButtonSize.lg,
            ),
          ],
        ),
      ),
    );
  }
}
