import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/accounts_service.dart';
import '../theme/sure_colors.dart';
import '../utils/amount_parser.dart';
import '../widgets/account_card.dart';
import '../widgets/ds/ds.dart';
import '../widgets/form_error_text.dart';
import '../widgets/metadata_picker_sheet.dart';
import '../widgets/open_on_web_action.dart';
import 'connections_screen.dart';
import 'form_sheet_fields.dart';
import 'profile_options.dart';
import 'transactions_list_screen.dart';

/// The web's new account flow (choose a type, or connect a provider), kept
/// for servers without Sure+ `accounts.write`.
const String kNewAccountWebPath = '/accounts/new';

/// What [showAccountFormSheet] resolved with.
class AccountFormResult {
  const AccountFormResult.saved(Account this.account)
      : deleted = false,
        connectBank = false;
  const AccountFormResult.deleted()
      : account = null,
        deleted = true,
        connectBank = false;
  const AccountFormResult.connectBank()
      : account = null,
        deleted = false,
        connectBank = true;

  /// The created or updated account.
  final Account? account;

  /// The account was deleted (the server removes it in the background).
  final bool deleted;

  /// The user chose "Connect a bank" on the type step.
  final bool connectBank;
}

/// Opens the add/edit account sheet. With [account] it edits that account
/// (type fixed); otherwise it adds one, starting on the type step unless
/// [initialType] (an `account_type`, e.g. `credit_card`) is given.
Future<AccountFormResult?> showAccountFormSheet(
  BuildContext context, {
  Account? account,
  String? initialType,
  AccountsService? service,
  Future<String?> Function()? accessTokenLoader,
  Future<void> Function()? onUnauthorized,
}) {
  return showSureSheet<AccountFormResult>(
    context: context,
    builder: (_) => AccountFormSheet(
      account: account,
      initialType: initialType,
      service: service,
      accessTokenLoader: accessTokenLoader,
      onUnauthorized: onUnauthorized,
    ),
  );
}

/// The "+" on Home, the account group screen and the Invest empty state.
///
/// With Sure+ `accounts.write` it opens the native sheet, then reloads the
/// accounts and opens the new account's page. Without it, the web's
/// `/accounts/new` as before.
Future<void> openAddAccount(
  BuildContext context, {
  String? initialType,
  Future<void> Function()? onReload,
}) async {
  final l = AppLocalizations.of(context);
  bool hasFeature;
  try {
    hasFeature = context
        .read<ServerFeaturesProvider>()
        .has(ServerFeaturesProvider.accountsWrite);
  } on ProviderNotFoundException {
    hasFeature = false;
  }
  if (!hasFeature) {
    await openWebFallback(context,
        title: l.dshAddAccount, path: kNewAccountWebPath);
    return;
  }
  final result =
      await showAccountFormSheet(context, initialType: initialType);
  if (result == null || !context.mounted) return;
  if (result.connectBank) {
    await openWebFallback(context,
        title: l.shellConnections, path: ConnectionsScreen.webPath);
    return;
  }
  final created = result.account;
  if (created == null) return;
  await (onReload?.call() ?? reloadAccounts(context));
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TransactionsListScreen(account: created),
    ),
  );
  if (context.mounted) await (onReload?.call() ?? reloadAccounts(context));
}

/// Refetches the account list (Home, groups and Invest watch it). Does
/// nothing where the providers are absent (isolated widget tests).
Future<void> reloadAccounts(BuildContext context) async {
  final AuthProvider auth;
  final AccountsProvider accounts;
  try {
    auth = context.read<AuthProvider>();
    accounts = context.read<AccountsProvider>();
  } on ProviderNotFoundException {
    return;
  }
  final token = await auth.getValidAccessToken();
  if (token == null) return;
  await accounts.fetchAccounts(accessToken: token);
}

/// One account type of the add flow.
class AccountFormType {
  const AccountFormType(this.accountType, this.accountableType);

  /// The API's `account_type` (`credit_card`).
  final String accountType;

  /// The class name the create body takes (`CreditCard`).
  final String accountableType;

  bool get isLiability => const {'credit_card', 'loan', 'other_liability'}
      .contains(accountType);
}

/// The web's `/accounts/new` order (`app/views/accounts/new.html.erb`).
const List<AccountFormType> kAccountFormTypes = [
  AccountFormType('depository', 'Depository'),
  AccountFormType('investment', 'Investment'),
  AccountFormType('crypto', 'Crypto'),
  AccountFormType('property', 'Property'),
  AccountFormType('vehicle', 'Vehicle'),
  AccountFormType('credit_card', 'CreditCard'),
  AccountFormType('loan', 'Loan'),
  AccountFormType('other_asset', 'OtherAsset'),
  AccountFormType('other_liability', 'OtherLiability'),
];

AccountFormType? _typeFor(String accountType) {
  for (final t in kAccountFormTypes) {
    if (t.accountType == accountType) return t;
  }
  return null;
}

/// Singular type name, as the step-1 rows and the step-2 title.
String accountFormTypeLabel(AppLocalizations l, String accountType) {
  switch (accountType) {
    case 'depository':
      return l.spaTypeDepository;
    case 'investment':
      return l.spaTypeInvestment;
    case 'crypto':
      return l.spaTypeCrypto;
    case 'property':
      return l.spaTypeProperty;
    case 'vehicle':
      return l.spaTypeVehicle;
    case 'credit_card':
      return l.spaTypeCreditCard;
    case 'loan':
      return l.spaTypeLoan;
    case 'other_asset':
      return l.spaTypeOtherAsset;
    case 'other_liability':
      return l.spaTypeOtherLiability;
    default:
      return accountType;
  }
}

/// Subtype choices per type, from each accountable model's `SUBTYPES`.
List<PickerOption> accountSubtypeOptions(
  AppLocalizations l,
  String accountType, {
  String? currency,
}) {
  switch (accountType) {
    case 'depository':
      return [
        PickerOption(id: 'cash', label: l.spaSubCash),
        PickerOption(id: 'checking', label: l.spaSubChecking),
        PickerOption(id: 'savings', label: l.spaSubSavings),
        PickerOption(id: 'hsa', label: l.spaSubHsa),
        PickerOption(id: 'cd', label: l.spaSubCd),
        PickerOption(id: 'money_market', label: l.spaSubMoneyMarket),
      ];
    case 'loan':
      return [
        PickerOption(id: 'mortgage', label: l.spaSubMortgage),
        PickerOption(id: 'student', label: l.spaSubStudentLoan),
        PickerOption(id: 'auto', label: l.spaSubAutoLoan),
        PickerOption(id: 'home_equity', label: l.spaSubHomeEquity),
        PickerOption(id: 'line_of_credit', label: l.spaSubLineOfCredit),
        PickerOption(id: 'business', label: l.spaSubBusinessLoan),
        PickerOption(id: 'other', label: l.spaSubOtherLoan),
      ];
    case 'crypto':
      return [
        PickerOption(id: 'wallet', label: l.spaSubWallet),
        PickerOption(id: 'exchange', label: l.spaSubExchange),
      ];
    case 'property':
      return [
        PickerOption(id: 'single_family_home', label: l.spaSubSingleFamily),
        PickerOption(id: 'multi_family_home', label: l.spaSubMultiFamily),
        PickerOption(id: 'condominium', label: l.spaSubCondo),
        PickerOption(id: 'townhouse', label: l.spaSubTownhouse),
        PickerOption(id: 'investment_property', label: l.spaSubInvestmentProperty),
        PickerOption(id: 'second_home', label: l.spaSubSecondHome),
        PickerOption(id: 'apartment', label: l.spaSubApartment),
        PickerOption(id: 'plot', label: l.spaSubPlot),
        PickerOption(id: 'commercial', label: l.spaSubCommercial),
        PickerOption(id: 'agri_land', label: l.spaSubAgriLand),
      ];
    case 'investment':
      return investmentSubtypeOptions(currency: currency);
    default:
      return const [];
  }
}

/// `Investment::SUBTYPES` as (key, long label, region). The labels are the
/// server's: mostly product names (401(k), ISA, TFSA) that the web does not
/// translate either.
const List<(String, String, String?)> _investmentSubtypes = [
  ('brokerage', 'Brokerage', 'us'),
  ('cash_management', 'Cash Management Account', 'us'),
  ('401k', '401(k)', 'us'),
  ('roth_401k', 'Roth 401(k)', 'us'),
  ('403b', '403(b)', 'us'),
  ('457b', '457(b)', 'us'),
  ('tsp', 'Thrift Savings Plan', 'us'),
  ('ira', 'Traditional IRA', 'us'),
  ('roth_ira', 'Roth IRA', 'us'),
  ('sep_ira', 'SEP IRA', 'us'),
  ('simple_ira', 'SIMPLE IRA', 'us'),
  ('529_plan', '529 Education Savings Plan', 'us'),
  ('hsa', 'Health Savings Account', 'us'),
  ('ugma', 'UGMA Custodial Account', 'us'),
  ('utma', 'UTMA Custodial Account', 'us'),
  ('isa', 'Individual Savings Account', 'uk'),
  ('lisa', 'Lifetime ISA', 'uk'),
  ('sipp', 'Self-Invested Personal Pension', 'uk'),
  ('workplace_pension_uk', 'Workplace Pension', 'uk'),
  ('tfsa', 'Tax-Free Savings Account', 'ca'),
  ('rrsp', 'Registered Retirement Savings Plan', 'ca'),
  ('non-registered', 'Non-Registered Investment Account', 'ca'),
  ('fhsa', 'First Home Savings Account', 'ca'),
  ('rdsp', 'Registered Disability Savings Plan', 'ca'),
  ('resp', 'Registered Education Savings Plan', 'ca'),
  ('dpsp', 'Deferred Profit Sharing Plan', 'ca'),
  ('prpp', 'Pooled Registered Pension Plan', 'ca'),
  ('lira', 'Locked-In Retirement Account', 'ca'),
  ('rrif', 'Registered Retirement Income Fund', 'ca'),
  ('lif', 'Life Income Fund', 'ca'),
  ('lrif', 'Locked-In Retirement Income Fund', 'ca'),
  ('prif', 'Prescribed Registered Retirement Income Fund', 'ca'),
  ('rlif', 'Restricted Life Income Fund', 'ca'),
  ('super', 'Superannuation', 'au'),
  ('smsf', 'Self-Managed Super Fund', 'au'),
  ('assurance_vie', 'Assurance Vie', 'eu'),
  ('pea', "Plan d'Épargne en Actions", 'eu'),
  ('pillar_3a', 'Private Pension (Pillar 3a)', 'eu'),
  ('riester', 'Riester-Rente', 'eu'),
  ('nps', 'National Pension System', 'in'),
  ('apy', 'Atal Pension Yojana', 'in'),
  ('life_insurance', 'Life Insurance', 'in'),
  ('indian_stocks', 'Indian Stocks (Demat)', 'in'),
  ('indian_equity', 'Indian Equity', 'in'),
  ('indian_etf', 'Indian ETF', 'in'),
  ('epf', "Employees' Provident Fund", 'in'),
  ('ppf', 'Public Provident Fund', 'in'),
  ('ssy', 'Sukanya Samriddhi Yojana', 'in'),
  ('nsc', 'National Savings Certificate', 'in'),
  ('scss', "Senior Citizens' Savings Scheme", 'in'),
  ('fd', 'Fixed Deposit', 'in'),
  ('rd', 'Recurring Deposit', 'in'),
  ('pomis', 'Post Office Monthly Income Scheme', 'in'),
  ('kvp', 'Kisan Vikas Patra', 'in'),
  ('g_sec', 'Government Securities (G-Secs)', 'in'),
  ('sdl', 'State Development Loans (SDLs)', 'in'),
  ('corporate_bond', 'Corporate Bond', 'in'),
  ('infrastructure_bond', 'Infrastructure Bond', 'in'),
  ('tax_free_bond', 'Tax-Free Bond', 'in'),
  ('gold_etf', 'Gold ETF', 'in'),
  ('gold_mf', 'Gold Mutual Fund', 'in'),
  ('sgb', 'Sovereign Gold Bond', 'in'),
  ('pension', 'Pension', null),
  ('retirement', 'Retirement Account', null),
  ('mutual_fund', 'Mutual Fund', null),
  ('gold', 'Gold (physical or digital)', null),
  ('angel', 'Angel Investment', null),
  ('trust', 'Trust', null),
  ('other', 'Other Investment', null),
];

/// Investment subtypes in the web's order
/// (`Investment.subtypes_grouped_for_select`): the region of [currency]
/// first, then the generic ones, then the other regions.
List<PickerOption> investmentSubtypeOptions({String? currency}) {
  const currencyRegion = {
    'USD': 'us',
    'GBP': 'uk',
    'CAD': 'ca',
    'AUD': 'au',
    'EUR': 'eu',
    'CHF': 'eu',
    'INR': 'in',
  };
  final userRegion = currencyRegion[currency];
  final order = <String?>[
    if (userRegion != null) userRegion,
    null,
    ...['us', 'uk', 'ca', 'au', 'eu', 'in'].where((r) => r != userRegion),
  ];
  return [
    for (final region in order)
      for (final s in _investmentSubtypes)
        if (s.$3 == region) PickerOption(id: s.$1, label: s.$2),
  ];
}

/// Add or edit an account, as sheet content.
///
/// Adding starts on the type step ("Connect a bank" on the web, then the
/// nine manual types); picking one moves to the details step in the same
/// sheet. Editing opens the details step for the account's type, prefilled
/// with what the account JSON carries (name, balance, currency, subtype,
/// institution). The API does not return a type's own fields (APR, make...),
/// so those start empty in edit and are sent only when filled in.
class AccountFormSheet extends StatefulWidget {
  const AccountFormSheet({
    super.key,
    this.account,
    this.initialType,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.today,
  });

  final Account? account;
  final String? initialType;
  final AccountsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Test seam for the opening-balance default (two years ago).
  final DateTime? today;

  @override
  State<AccountFormSheet> createState() => _AccountFormSheetState();
}

class _AccountFormSheetState extends State<AccountFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final AccountsService _service = widget.service ?? AccountsService();

  late AccountFormType? _type = widget.account != null
      ? _typeFor(widget.account!.accountType)
      : (widget.initialType == null ? null : _typeFor(widget.initialType!));

  final _name = TextEditingController();
  final _balance = TextEditingController();
  final _institution = TextEditingController();
  final _notes = TextEditingController();

  /// Text fields of the type, by API key (`apr`, `make`, `line1`...).
  final Map<String, TextEditingController> _fields = {};

  /// Choice fields of the type, by API key (`rate_type`, `due_day`...).
  final Map<String, String?> _choices = {};

  String? _currency;
  String? _subtype;
  late DateTime _openingDate;
  DateTime? _startDate;
  DateTime? _purchaseDate;
  DateTime? _expirationDate;
  bool _excludeFromReports = false;
  bool _showMore = false;

  /// Set once the server refuses a balance/currency change or a delete as
  /// linked: how servers without Sure+ `accounts.permissions` tell us.
  bool _linkedRefused = false;

  /// `locked_fields` (Sure+ `accounts.permissions`): read-only rows.
  Set<String> _lockedFields = const {};

  /// `permissions.delete` (Sure+ `accounts.permissions`); null without it.
  bool? _canDelete;

  bool _featuresRead = false;
  bool _permissions = false;

  /// Sure+ `accounts.loan_rates`: the show response's `accountable` block
  /// prefills the type's fields, and loans get insurance, interest basis,
  /// principal-only transfers and rate changes.
  bool _loanRates = false;
  bool _loadingDetails = false;

  /// The `accountable` block the fields were prefilled from. Without it the
  /// type's fields start empty and are sent only when filled in; with it,
  /// whatever differs from the prefill is sent (empty clears).
  Map<String, dynamic>? _accountable;
  final Map<String, String> _initialText = {};
  final Map<String, String?> _initialChoices = {};
  DateTime? _initialStartDate;
  DateTime? _initialPurchaseDate;
  DateTime? _initialExpirationDate;
  bool _principalOnly = false;
  bool _initialPrincipalOnly = false;
  List<_RateChange> _rateChanges = [];
  List<_RateChange> _initialRateChanges = const [];

  bool _submitting = false;
  bool _deleting = false;
  String? _error;

  bool get _editing => widget.account != null;
  bool get _prefilled => _accountable != null;

  /// What a 422 "Linked accounts ..." locks on servers without
  /// `accounts.permissions` (the fields the web form hides).
  static const _refusalLocked = {
    'balance',
    'currency',
    'accountable_attributes.initial_balance',
    'accountable_attributes.purchase_date',
  };

  bool _isLocked(String field) =>
      _lockedFields.contains(field) ||
      (_linkedRefused && _refusalLocked.contains(field));

  /// Rate changes replace the whole list on PATCH, so they are editable only
  /// once the current list is known.
  bool get _rateChangesEditable => _loanRates && (!_editing || _prefilled);

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(widget.today ?? DateTime.now());
    _openingDate = DateTime(today.year - 2, today.month, today.day);
    final account = widget.account;
    if (account != null) {
      _name.text = account.name;
      _currency = account.currency;
      _subtype = account.subtype;
      _institution.text = account.institutionName ?? '';
    } else if (_type != null) {
      _choices.addAll(_defaultChoices(_type!.accountType));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = widget.account;
    if (account != null && _balance.text.isEmpty) {
      final value = accountBalanceValue(account);
      _balance.text = NumberFormat.decimalPatternDigits(
        locale: Localizations.localeOf(context).toString(),
        decimalDigits: 2,
      ).format(value).replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');
    }
    if (_currency == null) {
      try {
        _currency = context.read<AccountsProvider>().familyCurrency;
      } on ProviderNotFoundException {
        // Tests without an AccountsProvider.
      }
      _currency ??= 'USD';
    }
    if (!_featuresRead) {
      _featuresRead = true;
      _readFeatures();
    }
  }

  void _readFeatures() {
    try {
      final features = context.read<ServerFeaturesProvider>();
      _permissions = features.has(ServerFeaturesProvider.accountsPermissions);
      _loanRates = features.has(ServerFeaturesProvider.accountsLoanRates);
    } on ProviderNotFoundException {
      return;
    }
    final account = widget.account;
    if (account == null) return;
    _applyPermissions(account);
    if (!_loanRates) return;
    final accountable = account.accountable;
    if (accountable != null) {
      _prefill(accountable);
    } else {
      _loadingDetails = true;
      Future.microtask(_loadDetails);
    }
  }

  void _applyPermissions(Account account) {
    if (!_permissions) return;
    _lockedFields = {...?account.lockedFields};
    _canDelete = account.canDelete;
  }

  /// Fetches the show response for its `accountable` block. On failure the
  /// sheet works as without the feature.
  Future<void> _loadDetails() async {
    final token = await _token();
    if (!mounted) return;
    final result = token == null
        ? const <String, dynamic>{}
        : await _service.getAccount(
            accessToken: token, id: widget.account!.id);
    if (!mounted) return;
    final fresh = result['account'];
    setState(() {
      _loadingDetails = false;
      if (result['success'] == true && fresh is Account) {
        _applyPermissions(fresh);
        final accountable = fresh.accountable;
        if (accountable != null) _prefill(accountable);
      }
    });
  }

  String? _numberText(dynamic value, {bool integer = false}) {
    if (value == null) return null;
    final n = value is num ? value : num.tryParse(value.toString());
    if (n == null) return value.toString();
    if (integer) return n.round().toString();
    final format = NumberFormat.decimalPattern(_locale)
      ..maximumFractionDigits = 6
      ..turnOffGrouping();
    return format.format(n);
  }

  static DateTime? _parseDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : DateUtils.dateOnly(parsed);
  }

  /// Fills the type's fields from the show response's `accountable` block
  /// and remembers them, so [_body] sends only what changed.
  void _prefill(Map<String, dynamic> a) {
    _accountable = a;
    void text(String key, dynamic value, {bool number = false, bool integer = false}) {
      final t = number || integer
          ? _numberText(value, integer: integer)
          : value?.toString();
      if (t == null) return;
      _field(key).text = t;
      _initialText[key] = t;
    }

    void choice(String key, dynamic value) {
      if (value != null && value.toString().isNotEmpty) {
        _choices[key] = value.toString();
      }
      _initialChoices[key] = _choices[key];
    }

    switch (_type?.accountType) {
      case 'credit_card':
        for (final k in const [
          'available_credit',
          'apr',
          'minimum_payment',
          'annual_fee',
        ]) {
          text(k, a[k], number: true);
        }
        choice('statement_close_day', a['statement_close_day']);
        choice('due_day', a['due_day']);
        _expirationDate = _initialExpirationDate = _parseDate(a['expiration_date']);
      case 'loan':
        for (final k in const [
          'interest_rate',
          'initial_balance',
          'down_payment',
          'insurance_rate',
        ]) {
          text(k, a[k], number: true);
        }
        text('term_months', a['term_months'], integer: true);
        choice('rate_type', a['rate_type']);
        choice('insurance_rate_type', a['insurance_rate_type']);
        choice('day_count_convention', a['day_count_convention']);
        _startDate = _initialStartDate = _parseDate(a['start_date']);
        _principalOnly =
            _initialPrincipalOnly = a['principal_only_transfers'] == true;
        final rows = a['rate_changes'];
        _rateChanges = [
          if (rows is List)
            for (final row in rows)
              if (row is Map && _parseDate(row['effective_date']) != null)
                (
                  date: _parseDate(row['effective_date'])!,
                  rate: row['rate']?.toString() ?? '',
                ),
        ]..sort((x, y) => x.date.compareTo(y.date));
        _initialRateChanges = List.unmodifiable(_rateChanges);
      case 'vehicle':
        text('make', a['make']);
        text('model', a['model']);
        text('year', a['year'], integer: true);
        text('mileage_value', a['mileage_value'], integer: true);
        choice('mileage_unit', a['mileage_unit']);
        text('initial_balance', a['initial_balance'], number: true);
        _purchaseDate = _initialPurchaseDate = _parseDate(a['purchase_date']);
      case 'property':
        text('year_built', a['year_built'], integer: true);
        text('area_value', a['area_value'], integer: true);
        choice('area_unit', a['area_unit']);
        final address = a['address_attributes'];
        final map = address is Map ? address : const {};
        for (final k in _addressKeys) {
          text(k, map[k]);
        }
        choice('country', map['country']);
      case 'crypto':
        choice('tax_treatment', a['tax_treatment']);
    }
  }

  static const _addressKeys = [
    'line1',
    'line2',
    'locality',
    'region',
    'postal_code',
  ];

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _institution.dispose();
    _notes.dispose();
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);

  String get _locale => Localizations.localeOf(context).toString();

  void _selectType(AccountFormType type) {
    setState(() {
      _type = type;
      _subtype = null;
      _choices
        ..clear()
        ..addAll(_defaultChoices(type.accountType));
      _error = null;
    });
  }

  /// The web form's preselected options, for a new account.
  Map<String, String?> _defaultChoices(String accountType) {
    switch (accountType) {
      case 'loan':
        return {'rate_type': 'fixed'};
      case 'vehicle':
        return {'mileage_unit': 'mi'};
      case 'property':
        return {'area_unit': 'sqft'};
      case 'crypto':
        return {'tax_treatment': 'taxable'};
      default:
        return const {};
    }
  }

  // ---- Validation ----

  String? _validateBalance(String? value) {
    final l = AppLocalizations.of(context);
    if (_isLocked('balance')) return null;
    if (value == null || value.trim().isEmpty) return l.spaBalanceRequired;
    try {
      AmountParser.parse(value, locale: _locale);
    } on FormatException {
      return l.spaInvalidNumber;
    }
    return null;
  }

  String? _validateName(String? value) => (value == null || value.trim().isEmpty)
      ? AppLocalizations.of(context).spaNameRequired
      : null;

  String? _validateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      AmountParser.parse(value, locale: _locale);
      return null;
    } on FormatException {
      return AppLocalizations.of(context).spaInvalidNumber;
    }
  }

  String? _validateInteger(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return int.tryParse(value.trim()) == null
        ? AppLocalizations.of(context).spaInvalidWholeNumber
        : null;
  }

  // ---- Body ----

  String _canonical(String text) =>
      AmountParser.canonicalize(text, locale: _locale);

  static String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// The JSON inside `account`. On edit only what changed is sent, so a
  /// linked account's balance and currency are never sent untouched.
  Map<String, dynamic> _body() {
    final type = _type!;
    final account = widget.account;
    final body = <String, dynamic>{};
    final attrs = <String, dynamic>{};

    if (account == null) body['accountable_type'] = type.accountableType;

    final name = _name.text.trim();
    if (account == null || name != account.name) body['name'] = name;

    if (!_isLocked('balance')) {
      final balance = _canonical(_balance.text);
      if (account == null ||
          double.parse(balance) != accountBalanceValue(account)) {
        body['balance'] = balance;
      }
    }
    if (!_isLocked('currency') &&
        (account == null || _currency != account.currency)) {
      body['currency'] = _currency;
    }

    // Depository's subtype is an account field on the web form; the other
    // types post it with the accountable.
    final subtypeChanged = account == null
        ? (_subtype != null && _subtype!.isNotEmpty)
        : _subtype != account.subtype;
    if (subtypeChanged) {
      if (type.accountType == 'depository') {
        body['subtype'] = _subtype ?? '';
      } else {
        attrs['subtype'] = _subtype ?? '';
      }
    }

    // With a prefill, a field is sent when it differs from it (emptied
    // means null); without one, when it is filled in.
    String? edited(String key) {
      final value = _fields[key]?.text.trim() ?? '';
      if (_prefilled && value == (_initialText[key] ?? '')) return null;
      if (value.isEmpty && !_prefilled) return null;
      return value;
    }

    void text(String key) {
      final value = edited(key);
      if (value != null) attrs[key] = value.isEmpty ? null : value;
    }

    void number(String key) {
      final value = edited(key);
      if (value != null) attrs[key] = value.isEmpty ? null : _canonical(value);
    }

    void integer(String key) {
      final value = edited(key);
      if (value == null) return;
      if (value.isEmpty) {
        attrs[key] = null;
      } else if (int.tryParse(value) != null) {
        attrs[key] = int.parse(value);
      }
    }

    void choice(String key) {
      final value = _choices[key];
      if (_prefilled && value == _initialChoices[key]) return;
      if (value != null) attrs[key] = value == '' ? null : value;
    }

    void date(String key, DateTime? value, DateTime? initial) {
      if (value != null && (!_prefilled || value != initial)) {
        attrs[key] = _date(value);
      }
    }

    switch (type.accountType) {
      case 'credit_card':
        number('available_credit');
        number('apr');
        number('minimum_payment');
        number('annual_fee');
        date('expiration_date', _expirationDate, _initialExpirationDate);
        choice('statement_close_day');
        choice('due_day');
      case 'loan':
        number('interest_rate');
        choice('rate_type');
        integer('term_months');
        number('initial_balance');
        number('down_payment');
        date('start_date', _startDate, _initialStartDate);
        if (_loanRates) {
          number('insurance_rate');
          choice('insurance_rate_type');
          choice('day_count_convention');
          if (_principalOnly != _initialPrincipalOnly) {
            attrs['principal_only_transfers'] = _principalOnly;
          }
          if (_rateChangesEditable &&
              !listEquals(_rateChanges, _initialRateChanges)) {
            attrs['rate_changes'] = [
              for (final r in _rateChanges)
                {'effective_date': _date(r.date), 'rate': r.rate},
            ];
          }
        }
      case 'vehicle':
        text('make');
        text('model');
        integer('year');
        integer('mileage_value');
        choice('mileage_unit');
        if (!_isLocked('accountable_attributes.initial_balance')) {
          number('initial_balance');
        }
        if (!_isLocked('accountable_attributes.purchase_date')) {
          date('purchase_date', _purchaseDate, _initialPurchaseDate);
        }
        // The server tells an edited purchase price from an untouched one by
        // comparing it with the price the form showed.
        final accountable = _accountable;
        if (attrs.isNotEmpty &&
            accountable != null &&
            accountable.containsKey('initial_balance_shown') &&
            !_isLocked('accountable_attributes.initial_balance_shown')) {
          attrs['initial_balance_shown'] = accountable['initial_balance_shown'];
        }
      case 'property':
        integer('year_built');
        integer('area_value');
        choice('area_unit');
        final address = <String, dynamic>{};
        var addressChanged = !_prefilled;
        for (final key in _addressKeys) {
          final value = _fields[key]?.text.trim() ?? '';
          if (value != (_initialText[key] ?? '')) addressChanged = true;
          if (value.isNotEmpty || _prefilled) address[key] = value;
        }
        if (_choices['country'] != _initialChoices['country']) {
          addressChanged = true;
        }
        if (_choices['country'] != null) address['country'] = _choices['country'];
        if (addressChanged && address.values.any((v) => v != '')) {
          attrs['address_attributes'] = address;
        }
      case 'crypto':
        choice('tax_treatment');
    }

    final institution = _institution.text.trim();
    if (account == null
        ? institution.isNotEmpty
        : institution != (account.institutionName ?? '')) {
      body['institution_name'] = institution;
    }
    final notes = _notes.text.trim();
    if (notes.isNotEmpty) body['notes'] = notes;

    if (account == null && type.accountType != 'property') {
      body['opening_balance_date'] = _date(_openingDate);
      if (_excludeFromReports) body['exclude_from_reports'] = true;
    }

    if (attrs.isNotEmpty) body['accountable_attributes'] = attrs;
    return body;
  }

  // ---- Actions ----

  Future<String?> _token() async {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _unauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  String _errorText(Map<String, dynamic> result) {
    final l = AppLocalizations.of(context);
    if (result['code'] == 'insufficient_scope') return l.spaReadOnlyAccess;
    return result['error']?.toString() ?? l.spaSaveFailed;
  }

  static bool _isLinkedRefusal(Map<String, dynamic> result) =>
      result['status'] == 422 &&
      (result['error']?.toString().startsWith('Linked accounts') ?? false);

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    if (_type == null || !_formKey.currentState!.validate()) return;
    if (_type!.accountType == 'property' &&
        !_editing &&
        (_subtype == null || _subtype!.isEmpty)) {
      setState(() => _error = l.spaPropertyTypeRequired);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });

    final body = _body();
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      await _unauthorized();
      return;
    }
    final result = _editing
        ? await _service.updateAccount(
            accessToken: token, id: widget.account!.id, account: body)
        : await _service.createAccount(accessToken: token, account: body);
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return;
    }
    final saved = result['account'];
    if (result['success'] == true && saved is Account) {
      messenger.showSnackBar(SnackBar(
        content: Text(_editing ? l.spaSaved : l.spaCreated),
      ));
      navigator.pop(AccountFormResult.saved(saved));
      return;
    }
    setState(() {
      _submitting = false;
      if (_isLinkedRefusal(result)) _linkedRefused = true;
      _error = _errorText(result);
    });
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final account = widget.account!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(dl.spaDeleteConfirmTitle(account.name)),
          content: Text(dl.spaDeleteConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      await _unauthorized();
      return;
    }
    final result =
        await _service.deleteAccount(accessToken: token, id: account.id);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return;
    }
    if (result['success'] == true) {
      messenger.showSnackBar(SnackBar(content: Text(l.spaDeleted)));
      navigator.pop(const AccountFormResult.deleted());
      return;
    }
    setState(() {
      _deleting = false;
      if (_isLinkedRefusal(result)) _linkedRefused = true;
      _error = _errorText(result);
    });
  }

  // ---- Pickers ----

  Future<void> _pick({
    required String title,
    required List<PickerOption> options,
    required String? selected,
    required ValueChanged<String> onPicked,
  }) async {
    final picked = await MetadataPickerSheet.show(
      context,
      title: title,
      options: options,
      initialSelection: {if (selected != null) selected},
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => onPicked(picked.first));
  }

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime> onPicked,
    DateTime? last,
  }) async {
    final now = DateTime.now();
    final lastDate = last ?? DateTime(now.year + 30);
    final initial = current ?? (last ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(lastDate) ? lastDate : initial,
      firstDate: DateTime(1900),
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final type = _type;
    return type == null ? _typeStep(context) : _detailsStep(context, type);
  }

  Widget _typeStep(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    return SureSheet(
      title: l.spaAddAccount,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SurePanel.rows(
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                SureListRow(
                  key: const ValueKey('spaConnectBank'),
                  leading: const _RoundIcon(SureIcons.landmark),
                  title: l.spaConnectBank,
                  subtitle: l.spaConnectBankSub,
                  trailing: SureIcon(SureIcons.externalLink,
                      size: 16, color: palette.textSubdued),
                  onTap: () => Navigator.of(context)
                      .pop(const AccountFormResult.connectBank()),
                ),
              ],
            ),
            SureSectionHeader(label: l.spaOrByHand, padding: _headerPadding),
            SurePanel.rows(
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                for (final t in kAccountFormTypes)
                  SureListRow(
                    key: ValueKey('spaType-${t.accountType}'),
                    leading: AccountTypeIcon(accountType: t.accountType),
                    title: accountFormTypeLabel(l, t.accountType),
                    showChevron: true,
                    onTap: () => _selectType(t),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _balanceLabel(AppLocalizations l, AccountFormType type) {
    if (type.isLiability) return l.spaAmountOwed;
    if (type.accountType == 'depository') return l.spaCurrentBalance;
    return l.spaCurrentValue;
  }

  String _optionLabel(List<PickerOption> options, String? id, String fallback) {
    if (id == null) return fallback;
    for (final o in options) {
      if (o.id == id) return o.label;
    }
    return id.isEmpty ? fallback : id;
  }

  Widget _detailsStep(BuildContext context, AccountFormType type) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canGoBack = !_editing && widget.initialType == null;
    final busy = _submitting || _deleting;
    final optional = _editing && !_prefilled ? l.spaUnchanged : l.spaOptional;

    final subtypes =
        accountSubtypeOptions(l, type.accountType, currency: _currency);

    return SureSheet(
      title: _editing ? l.spaEditAccount : accountFormTypeLabel(l, type.accountType),
      actionLabel: _editing ? l.dsSave : l.spaAdd,
      actionKey: const ValueKey('spaSave'),
      onAction: busy || _loadingDetails ? null : _submit,
      busy: _submitting,
      cancelLabel: canGoBack ? l.spaBackToType : null,
      onCancel: canGoBack
          ? () => setState(() {
                _type = null;
                _error = null;
              })
          : null,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _balanceLabel(l, type),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
              const SizedBox(height: 4),
              FormSheetAmountField(
                key: const ValueKey('spaBalance'),
                controller: _balance,
                validator: _validateBalance,
                suffix: _currency,
                signed: true,
                enabled: !_isLocked('balance') && !busy,
                autofocus: !_editing,
              ),
              if (_isLocked('balance'))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l.spaSyncedFromBank,
                    key: const ValueKey('spaSynced'),
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: palette.textSecondary),
                  ),
                ),
              const SizedBox(height: 16),
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    fieldKey: const ValueKey('spaName'),
                    label: l.spaName,
                    controller: _name,
                    hint: l.spaNameHint,
                    validator: _validateName,
                    textCapitalization: TextCapitalization.words,
                    enabled: !busy,
                  ),
                  SureListRow(
                    key: const ValueKey('spaCurrency'),
                    title: l.spaCurrency,
                    value: _currency,
                    // Read-only when the provider owns it.
                    showChevron: !_isLocked('currency'),
                    onTap: _isLocked('currency') || busy
                        ? null
                        : () => _pick(
                              title: l.spaCurrency,
                              options: [
                                for (final c in kProfileCurrencies)
                                  PickerOption(id: c.$1, label: c.$2),
                              ],
                              selected: _currency,
                              onPicked: (v) => _currency = v,
                            ),
                  ),
                  if (subtypes.isNotEmpty)
                    SureListRow(
                      key: const ValueKey('spaSubtype'),
                      title: type.accountType == 'property'
                          ? l.spaPropertyType
                          : l.spaSubtype,
                      value: _optionLabel(subtypes, _subtype, l.spaNone),
                      showChevron: true,
                      onTap: busy
                          ? null
                          : () => _pick(
                                title: type.accountType == 'property'
                                    ? l.spaPropertyType
                                    : l.spaSubtype,
                                options: [
                                  if (type.accountType != 'property')
                                    PickerOption(id: '', label: l.spaNone),
                                  ...subtypes,
                                ],
                                selected: _subtype ?? '',
                                onPicked: (v) => _subtype = v,
                              ),
                    ),
                ],
              ),
              ..._typeSections(l, type, optional, busy),
              _moreSection(l, type, optional, busy),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              if (_editing && !_linkedRefused && _canDelete != false) ...[
                const SizedBox(height: 24),
                SureButtonPanel(
                  key: const ValueKey('spaDelete'),
                  label: l.spaDeleteAccount,
                  destructive: true,
                  busy: _deleting,
                  onPressed: busy ? null : _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberRow(
    String key,
    String label,
    String hint, {
    bool integer = false,
    String? suffix,
    bool enabled = true,
  }) {
    return FormSheetFieldRow(
      fieldKey: ValueKey('spa-$key'),
      label: label,
      controller: _field(key),
      hint: hint,
      mono: true,
      suffix: suffix,
      enabled: enabled,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      validator: integer ? _validateInteger : _validateNumber,
    );
  }

  Widget _textRow(String key, String label, String hint, {bool enabled = true}) {
    return FormSheetFieldRow(
      fieldKey: ValueKey('spa-$key'),
      label: label,
      controller: _field(key),
      hint: hint,
      enabled: enabled,
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _choiceRow(
    String key,
    String label,
    List<PickerOption> options,
    String fallback, {
    bool enabled = true,
  }) {
    return SureListRow(
      key: ValueKey('spa-$key'),
      title: label,
      value: _optionLabel(options, _choices[key], fallback),
      showChevron: true,
      onTap: !enabled
          ? null
          : () => _pick(
                title: label,
                options: options,
                selected: _choices[key],
                onPicked: (v) => _choices[key] = v,
              ),
    );
  }

  Widget _dateRow(
    String key,
    String label,
    DateTime? value,
    String fallback,
    ValueChanged<DateTime> onPicked, {
    DateTime? last,
    bool enabled = true,
  }) {
    return SureListRow(
      key: ValueKey('spa-$key'),
      title: label,
      value: value == null ? fallback : SureDates.shortOf(context, value),
      showChevron: true,
      onTap: !enabled
          ? null
          : () => _pickDate(current: value, onPicked: onPicked, last: last),
    );
  }

  List<PickerOption> _dayOptions(AppLocalizations l) => [
        PickerOption(id: '', label: l.spaNone),
        for (var d = 1; d <= 31; d++)
          PickerOption(id: '$d', label: l.spaDayOfMonth(d)),
      ];

  List<Widget> _typeSections(
    AppLocalizations l,
    AccountFormType type,
    String optional,
    bool busy,
  ) {
    const gap = SizedBox(height: 16);
    final enabled = !busy;
    switch (type.accountType) {
      case 'credit_card':
        return [
          gap,
          SurePanel.rows(children: [
            _numberRow('available_credit', l.spaAvailableCredit, optional,
                enabled: enabled),
            _numberRow('apr', l.spaApr, optional, suffix: '%', enabled: enabled),
            _numberRow('minimum_payment', l.spaMinimumPayment, optional,
                enabled: enabled),
            _choiceRow('statement_close_day', l.spaStatementCloseDay,
                _dayOptions(l), optional,
                enabled: enabled),
            _choiceRow('due_day', l.spaDueDay, _dayOptions(l), optional,
                enabled: enabled),
          ]),
        ];
      case 'loan':
        return [
          gap,
          SurePanel.rows(children: [
            _numberRow('interest_rate', l.spaInterestRate, optional,
                suffix: '%', enabled: enabled),
            _choiceRow(
              'rate_type',
              l.spaRateType,
              [
                PickerOption(id: 'fixed', label: l.spaRateFixed),
                PickerOption(id: 'variable', label: l.spaRateVariable),
                PickerOption(id: 'adjustable', label: l.spaRateAdjustable),
              ],
              optional,
              enabled: enabled,
            ),
            _numberRow('term_months', l.spaTerm, optional,
                integer: true, suffix: l.spaMonthsSuffix, enabled: enabled),
            _dateRow('start_date', l.spaStartDate, _startDate, optional,
                (d) => _startDate = d,
                last: DateTime.now(), enabled: enabled),
            _numberRow('initial_balance', l.spaOriginalAmount, optional,
                enabled: enabled),
          ]),
        ];
      case 'vehicle':
        return [
          gap,
          SurePanel.rows(children: [
            _textRow('make', l.spaMake, optional, enabled: enabled),
            _textRow('model', l.spaModel, optional, enabled: enabled),
            _numberRow('year', l.spaYear, optional,
                integer: true, enabled: enabled),
            _numberRow('mileage_value', l.spaMileage, optional,
                integer: true, enabled: enabled),
            _choiceRow(
              'mileage_unit',
              l.spaMileageUnit,
              [
                PickerOption(id: 'mi', label: l.spaMiles),
                PickerOption(id: 'km', label: l.spaKilometers),
              ],
              optional,
              enabled: enabled,
            ),
            ..._vehicleAnchorRows(l, optional, enabled),
          ]),
          if (_lockedFields
              .contains('accountable_attributes.initial_balance')) ...[
            _syncedFootnote(l, const ValueKey('sa2VehicleSynced')),
          ],
        ];
      case 'property':
        return [
          gap,
          SurePanel.rows(children: [
            _numberRow('year_built', l.spaYearBuilt, optional,
                integer: true, enabled: enabled),
            _numberRow('area_value', l.spaArea, optional,
                integer: true, enabled: enabled),
            _choiceRow(
              'area_unit',
              l.spaAreaUnit,
              [
                PickerOption(id: 'sqft', label: l.spaSquareFeet),
                PickerOption(id: 'sqm', label: l.spaSquareMeters),
              ],
              optional,
              enabled: enabled,
            ),
          ]),
          SureSectionHeader(label: l.spaAddress, padding: _headerPadding),
          SurePanel.rows(children: [
            _textRow('line1', l.spaStreet, optional, enabled: enabled),
            _textRow('line2', l.spaStreet2, optional, enabled: enabled),
            _textRow('locality', l.spaCity, optional, enabled: enabled),
            _textRow('region', l.spaRegion, optional, enabled: enabled),
            _textRow('postal_code', l.spaPostalCode, optional,
                enabled: enabled),
            _choiceRow(
              'country',
              l.spaCountry,
              [
                for (final c in kProfileCountries)
                  PickerOption(id: c.$1, label: c.$2),
              ],
              optional,
              enabled: enabled,
            ),
          ]),
        ];
      case 'crypto':
        return [
          gap,
          SurePanel.rows(children: [
            _choiceRow(
              'tax_treatment',
              l.spaTaxTreatment,
              [
                PickerOption(id: 'taxable', label: l.spaTaxable),
                PickerOption(id: 'tax_deferred', label: l.spaTaxDeferred),
                PickerOption(id: 'tax_exempt', label: l.spaTaxExempt),
              ],
              optional,
              enabled: enabled,
            ),
          ]),
        ];
      default:
        return const [];
    }
  }

  Widget _moreSection(
    AppLocalizations l,
    AccountFormType type,
    String optional,
    bool busy,
  ) {
    final enabled = !busy;
    final rows = <Widget>[
      _textRowFor(_institution, 'spaInstitution', l.spaInstitution, optional,
          enabled),
      if (type.accountType == 'credit_card') ...[
        _numberRow('annual_fee', l.spaAnnualFee, optional, enabled: enabled),
        _dateRow('expiration_date', l.spaExpirationDate, _expirationDate,
            optional, (d) => _expirationDate = d,
            enabled: enabled),
      ],
      if (type.accountType == 'loan') ...[
        _numberRow('down_payment', l.spaDownPayment, optional,
            enabled: enabled),
        if (_loanRates) ..._loanRateRows(l, optional, enabled),
      ],
      if (!_editing && type.accountType != 'property')
        _dateRow('opening_balance_date', l.spaOpeningDate, _openingDate,
            optional, (d) => _openingDate = d,
            last: DateTime.now(), enabled: enabled),
      FormSheetFieldRow(
        fieldKey: const ValueKey('spaNotes'),
        label: l.spaNotes,
        controller: _notes,
        hint: optional,
        maxLines: 3,
        enabled: enabled,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
      ),
      if (!_editing && type.accountType != 'property')
        SureListRow(
          key: const ValueKey('spaExclude'),
          title: l.spaExcludeFromReports,
          trailing: Switch.adaptive(
            value: _excludeFromReports,
            onChanged: enabled
                ? (v) => setState(() => _excludeFromReports = v)
                : null,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SureSectionHeader(
          key: const ValueKey('spaMore'),
          label: l.spaMore,
          actionLabel: _showMore ? l.dshHide : l.dshShow,
          onAction: () => setState(() => _showMore = !_showMore),
          padding: _headerPadding,
        ),
        if (_showMore) SurePanel.rows(children: rows),
        if (_showMore &&
            type.accountType == 'loan' &&
            _rateChangesEditable) ...[
          SureSectionHeader(
              label: l.sa2RateChanges, padding: _headerPadding),
          _rateChangesPanel(l, enabled),
        ],
      ],
    );
  }

  Widget _syncedFootnote(AppLocalizations l, Key key) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        l.spaSyncedFromBank,
        key: key,
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      ),
    );
  }

  /// Purchase price and date: editable, read-only when `locked_fields`
  /// names them, or hidden after a linked 422 (servers without
  /// `accounts.permissions`).
  List<Widget> _vehicleAnchorRows(
    AppLocalizations l,
    String optional,
    bool enabled,
  ) {
    final palette = SureColors.of(context).palette;
    const price = 'accountable_attributes.initial_balance';
    const date = 'accountable_attributes.purchase_date';
    final priceText = _field('initial_balance').text;
    return [
      if (_lockedFields.contains(price))
        SureListRow(
          key: const ValueKey('spa-initial_balance'),
          title: l.spaPurchasePrice,
          trailing: priceText.isEmpty
              ? Text('—', style: TextStyle(color: palette.textSecondary))
              : MoneyText(priceText,
                  trend: MoneyTrend.neutral,
                  color: palette.textSecondary,
                  style: const TextStyle(fontSize: 15)),
        )
      else if (!_isLocked(price))
        _numberRow('initial_balance', l.spaPurchasePrice, optional,
            enabled: enabled),
      // The web offers the purchase date only once the account exists (it
      // re-anchors the opening balance).
      if (_editing)
        if (_lockedFields.contains(date))
          SureListRow(
            key: const ValueKey('spa-purchase_date'),
            title: l.spaPurchaseDate,
            value: _purchaseDate == null
                ? '—'
                : SureDates.shortOf(context, _purchaseDate!),
          )
        else if (!_isLocked(date))
          _dateRow('purchase_date', l.spaPurchaseDate, _purchaseDate,
              optional, (d) => _purchaseDate = d,
              last: DateTime.now(), enabled: enabled),
    ];
  }

  /// Sure+ `accounts.loan_rates` loan fields in the More section.
  List<Widget> _loanRateRows(
    AppLocalizations l,
    String optional,
    bool enabled,
  ) {
    return [
      _numberRow('insurance_rate', l.sa2InsuranceRate, optional,
          suffix: '%', enabled: enabled),
      _choiceRow(
        'insurance_rate_type',
        l.sa2InsuranceType,
        [
          PickerOption(id: '', label: l.spaNone),
          PickerOption(id: 'level_term', label: l.sa2InsuranceLevelTerm),
          PickerOption(id: 'decreasing_life', label: l.sa2InsuranceDecreasing),
        ],
        optional,
        enabled: enabled,
      ),
      _choiceRow(
        'day_count_convention',
        l.sa2DayCount,
        [
          PickerOption(id: 'thirty_360', label: l.sa2DayCountThirty360),
          PickerOption(id: 'actual_365', label: l.sa2DayCountActual365),
          PickerOption(id: 'actual_actual', label: l.sa2DayCountActualActual),
        ],
        optional,
        enabled: enabled,
      ),
      SureListRow(
        key: const ValueKey('sa2PrincipalOnly'),
        title: l.sa2PrincipalOnly,
        subtitle: l.sa2PrincipalOnlySub,
        trailing: Switch.adaptive(
          value: _principalOnly,
          onChanged:
              enabled ? (v) => setState(() => _principalOnly = v) : null,
        ),
      ),
    ];
  }

  String _rateText(String rate) {
    final n = num.tryParse(rate);
    if (n == null) return '$rate%';
    final format = NumberFormat.decimalPattern(_locale)
      ..maximumFractionDigits = 6;
    return '${format.format(n)}%';
  }

  Widget _rateChangesPanel(AppLocalizations l, bool enabled) {
    final palette = SureColors.of(context).palette;
    return SurePanel.rows(
      key: const ValueKey('sa2RateChanges'),
      children: [
        for (final (i, change) in _rateChanges.indexed)
          Semantics(
            key: ValueKey('sa2RateChange-$i'),
            customSemanticsActions: {
              CustomSemanticsAction(label: l.commonDelete): () =>
                  _removeRateChange(change),
            },
            child: SureSwipeActions(
              enabled: enabled,
              actions: [
                SureSwipeAction(
                  label: l.commonDelete,
                  color: palette.destructive,
                  onPressed: () => _removeRateChange(change),
                ),
              ],
              child: ColoredBox(
                color: palette.container,
                child: SureListRow(
                  title: SureDates.fullOf(context, change.date),
                  value: _rateText(change.rate),
                  showChevron: true,
                  onTap: enabled ? () => _editRateChange(change) : null,
                ),
              ),
            ),
          ),
        SureListRow(
          key: const ValueKey('sa2AddRateChange'),
          leading: SureIcon(SureIcons.plus, size: 18, color: palette.link),
          title: l.sa2AddRateChange,
          titleColor: palette.link,
          onTap: enabled ? () => _editRateChange(null) : null,
        ),
      ],
    );
  }

  void _removeRateChange(_RateChange change) =>
      setState(() => _rateChanges = [..._rateChanges]..remove(change));

  /// Adds or edits one rate change. One rate per effective date: picking a
  /// date another row has replaces that row, as the server keys them.
  Future<void> _editRateChange(_RateChange? existing) async {
    final result = await showSureSheet<_RateChange>(
      context: context,
      builder: (_) => _RateChangeSheet(initial: existing),
    );
    if (result == null || !mounted) return;
    setState(() {
      _rateChanges = [
        for (final r in _rateChanges)
          if (r != existing && r.date != result.date) r,
        result,
      ]..sort((x, y) => x.date.compareTo(y.date));
    });
  }

  Widget _textRowFor(
    TextEditingController controller,
    String key,
    String label,
    String hint,
    bool enabled,
  ) {
    return FormSheetFieldRow(
      fieldKey: ValueKey(key),
      label: label,
      controller: controller,
      hint: hint,
      enabled: enabled,
      textCapitalization: TextCapitalization.words,
    );
  }
}

/// Section headers inside the sheet line up with the panel edge.
const _headerPadding = EdgeInsets.fromLTRB(4, 16, 4, 6);

/// A 28 px neutral inset circle with a Lucide glyph (as AccountTypeIcon).
class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);

  final String icon;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: palette.surfaceInset,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SureIcon(icon, size: 15, color: palette.textSecondary),
      ),
    );
  }
}

/// One row of a loan's `rate_changes`: the annual rate (a canonical decimal
/// string, as the server sends it) in force from [date].
typedef _RateChange = ({DateTime date, String rate});

/// Add or edit one rate change: effective date and rate.
class _RateChangeSheet extends StatefulWidget {
  const _RateChangeSheet({this.initial});

  final _RateChange? initial;

  @override
  State<_RateChangeSheet> createState() => _RateChangeSheetState();
}

class _RateChangeSheetState extends State<_RateChangeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _rate = TextEditingController();
  late DateTime _date =
      widget.initial?.date ?? DateUtils.dateOnly(DateTime.now());

  String get _locale => Localizations.localeOf(context).toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initial = widget.initial;
    if (initial != null && _rate.text.isEmpty) {
      final n = num.tryParse(initial.rate);
      _rate.text = n == null
          ? initial.rate
          : (NumberFormat.decimalPattern(_locale)
                ..maximumFractionDigits = 6
                ..turnOffGrouping())
              .format(n);
    }
  }

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  /// The server's bound: 0 to 100 (`Loan::MAX_INTEREST_RATE`).
  String? _validateRate(String? value) {
    final l = AppLocalizations.of(context);
    if (value == null || value.trim().isEmpty) return l.sa2RateRequired;
    final double rate;
    try {
      rate = AmountParser.parse(value, locale: _locale).value;
    } on FormatException {
      return l.spaInvalidNumber;
    }
    return rate < 0 || rate > 100 ? l.sa2RateOutOfRange : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 50),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateUtils.dateOnly(picked));
  }

  void _done() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop<_RateChange>((
      date: _date,
      rate: AmountParser.canonicalize(_rate.text.trim(), locale: _locale),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SureSheet(
      title: l.sa2RateChange,
      actionLabel: widget.initial == null ? l.spaAdd : l.dsSave,
      actionKey: const ValueKey('sa2RateChangeSave'),
      onAction: _done,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: SurePanel.rows(children: [
            SureListRow(
              key: const ValueKey('sa2RateChangeDate'),
              title: l.sa2EffectiveDate,
              value: SureDates.fullOf(context, _date),
              showChevron: true,
              onTap: _pickDate,
            ),
            FormSheetFieldRow(
              fieldKey: const ValueKey('sa2RateChangeRate'),
              label: l.sa2Rate,
              controller: _rate,
              hint: '5.25',
              mono: true,
              suffix: '%',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _validateRate,
            ),
          ]),
        ),
      ),
    );
  }
}
