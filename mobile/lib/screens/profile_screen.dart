import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/profile_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/metadata_picker_sheet.dart';
import 'form_sheet_fields.dart';
import 'profile_options.dart';
import 'settings_links.dart';

/// The languages a user can pick for themselves: the two the app ships.
/// Labels as the web's language_options writes them.
const List<ProfileOption> kProfileUserLocales = [
  ('en', 'English (en)'),
  ('sv', 'Swedish (sv)'),
];

/// The native profile and preferences screen on a Sure+ server
/// (`profile.write`), replacing the web's /settings/profile and
/// /settings/preferences. Email, password and MFA stay on the web; the
/// household name is shown read-only because the API doesn't accept it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.onNameSaved,
  });

  final ProfileService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Defaults to [AuthProvider.updateUserName].
  final Future<void> Function(String? firstName, String? lastName)?
      onNameSaved;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileService _service;
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // The picked values; compared with [_profile] to find the changes.
  String? _locale;
  String? _period;
  String? _currency;
  String? _country;
  String? _timezone;
  String? _dateFormat;
  String? _householdLocale;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileService();
    _firstName.addListener(_onEdited);
    _lastName.addListener(_onEdited);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _unauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  Future<void> _nameSaved(String? first, String? last) async {
    final handler = widget.onNameSaved;
    if (handler != null) return handler(first, last);
    try {
      await context
          .read<AuthProvider>()
          .updateUserName(firstName: first, lastName: last);
    } on ProviderNotFoundException {
      // Not mounted under the app's providers (tests).
    }
  }

  void _apply(UserProfile profile) {
    _profile = profile;
    _firstName.text = profile.firstName ?? '';
    _lastName.text = profile.lastName ?? '';
    _locale = profile.locale;
    _period = profile.defaultPeriod;
    final h = profile.household;
    _currency = h.currency;
    _country = h.country;
    _timezone = h.timezone;
    _dateFormat = h.dateFormat;
    _householdLocale = h.locale;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.getProfile(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _apply(result['profile'] as UserProfile);
        _error = null;
      }
    });
  }

  /// Only the fields that differ from the loaded profile, in the shape
  /// `PATCH /api/v1/users/me` takes.
  Map<String, dynamic> get _changes {
    final p = _profile;
    if (p == null) return const {};
    final h = p.household;
    final family = <String, dynamic>{
      if (_currency != h.currency) 'currency': _currency,
      if (_country != h.country) 'country': _country,
      if (_timezone != h.timezone) 'timezone': _timezone,
      if (_dateFormat != h.dateFormat) 'date_format': _dateFormat,
      if (_householdLocale != h.locale) 'locale': _householdLocale,
    };
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    return {
      if (first != (p.firstName ?? '').trim()) 'first_name': first,
      if (last != (p.lastName ?? '').trim()) 'last_name': last,
      // "" is "automatic"; the server stores it as no locale.
      if (_locale != p.locale) 'locale': _locale ?? '',
      if (_period != p.defaultPeriod) 'default_period': _period,
      if (family.isNotEmpty) 'family_attributes': family,
    };
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final changes = _changes;
    if (changes.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result =
        await _service.updateProfile(accessToken: token, user: changes);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true) {
      setState(() {
        _saving = false;
        _error = result['code'] == 'insufficient_scope'
            ? l.spmReadOnlyAccess
            : result['error']?.toString() ?? l.manageActionFailed;
      });
      return;
    }
    final profile = result['profile'] as UserProfile;
    setState(() {
      _saving = false;
      _apply(profile);
    });
    if (changes.containsKey('first_name') || changes.containsKey('last_name')) {
      await _nameSaved(profile.firstName, profile.lastName);
    }
    messenger.showSnackBar(SnackBar(content: Text(l.spmProfileSaved)));
  }

  /// A short list: the option sheet. Adds [current] when the server holds a
  /// value outside [options], so it still shows as selected.
  Future<void> _pickShort(
    String title,
    List<ProfileOption> options,
    String? current,
    ValueChanged<String?> onPicked, {
    String? automaticLabel,
  }) async {
    final picked = await showManageOptionSheet<String?>(
      context,
      title: title,
      selected: current,
      options: [
        if (automaticLabel != null) (null, automaticLabel),
        ..._withCurrent(options, current),
      ],
    );
    if (picked != null && mounted) setState(() => onPicked(picked.value));
  }

  /// A long list: the searchable picker sheet.
  Future<void> _pickLong(
    String title,
    List<ProfileOption> options,
    String? current,
    ValueChanged<String> onPicked,
  ) async {
    final picked = await MetadataPickerSheet.show(
      context,
      title: title,
      options: [
        for (final (value, label) in _withCurrent(options, current))
          PickerOption(id: value, label: label),
      ],
      initialSelection: {if (current != null) current},
    );
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => onPicked(picked.first));
    }
  }

  static List<ProfileOption> _withCurrent(
      List<ProfileOption> options, String? current) {
    if (current == null || options.any((o) => o.$1 == current)) return options;
    return [(current, current), ...options];
  }

  static String? _label(List<ProfileOption> options, String? value) {
    if (value == null) return null;
    for (final (v, label) in options) {
      if (v == value) return label;
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profile = _profile;
    final dirty = profile != null && _changes.isNotEmpty;

    final Widget content;
    if (profile == null && _loading) {
      content = const ManageLoading();
    } else if (profile == null) {
      content = SureEmptyState(
        key: const ValueKey('profileError'),
        icon: SureIcons.circleAlert,
        title: l.spmProfileLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else {
      content = _form(context, l, profile);
    }

    return SureLargeTitleScaffold(
      title: l.shellProfile,
      leading: manageBackLink(context),
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          SureNavTextButton(
            key: const ValueKey('profileSave'),
            label: l.commonSave,
            onPressed: dirty ? _save : null,
          ),
      ],
      slivers: [SliverToBoxAdapter(child: content)],
    );
  }

  Widget _form(BuildContext context, AppLocalizations l, UserProfile profile) {
    final palette = SureColors.of(context).palette;
    final notSet = l.spmProfileNotSet;
    final periods = [for (final p in kProfilePeriods) (p, periodLabel(l, p))];

    SureListRow picker(String title, String? value, VoidCallback onTap,
            {Key? key}) =>
        SureListRow(
          key: key,
          title: title,
          value: value ?? notSet,
          showChevron: true,
          onTap: _saving ? null : onTap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: ManageErrorText(_error!),
          ),
        SureSectionHeader(label: l.spmProfileYou),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            FormSheetFieldRow(
              label: l.spmProfileFirstName,
              fieldKey: const ValueKey('profileFirstName'),
              controller: _firstName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
            ),
            FormSheetFieldRow(
              label: l.spmProfileLastName,
              fieldKey: const ValueKey('profileLastName'),
              controller: _lastName,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
            ),
            SureListRow(title: l.spmProfileEmail, value: profile.email),
            picker(
              l.spmProfileLanguage,
              _locale == null
                  ? l.spmProfileLanguageAuto
                  : _label(kProfileUserLocales, _locale),
              () => _pickShort(l.spmProfileLanguage, kProfileUserLocales,
                  _locale, (v) => _locale = v,
                  automaticLabel: l.spmProfileLanguageAuto),
              key: const ValueKey('profileLocale'),
            ),
            picker(
              l.spmProfileDefaultPeriod,
              _label(periods, _period),
              () => _pickShort(l.spmProfileDefaultPeriod, periods, _period,
                  (v) => _period = v ?? _period),
              key: const ValueKey('profileDefaultPeriod'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            SettingsWebRow(
              title: l.spmProfileChangeOnWeb,
              subtitle: l.spmProfileChangeOnWebSubtitle,
              path: '/settings/security',
            ),
          ],
        ),
        SureSectionHeader(label: l.spmProfileHousehold),
        SurePanel.rows(
          margin: settingsPanelMargin,
          children: [
            SureListRow(
              title: l.spmProfileHouseholdName,
              value: profile.household.name,
            ),
            picker(
              l.spmProfileCurrency,
              _currency,
              () => _pickLong(l.spmProfileCurrency, kProfileCurrencies,
                  _currency, (v) => _currency = v),
              key: const ValueKey('profileCurrency'),
            ),
            picker(
              l.spmProfileCountry,
              _label(kProfileCountries, _country),
              () => _pickLong(l.spmProfileCountry, kProfileCountries, _country,
                  (v) => _country = v),
              key: const ValueKey('profileCountry'),
            ),
            picker(
              l.spmProfileTimezone,
              _timezone?.replaceAll('_', ' '),
              () => _pickLong(l.spmProfileTimezone, kProfileTimezones,
                  _timezone, (v) => _timezone = v),
              key: const ValueKey('profileTimezone'),
            ),
            picker(
              l.spmProfileDateFormat,
              _label(kProfileDateFormats, _dateFormat),
              () => _pickShort(l.spmProfileDateFormat, kProfileDateFormats,
                  _dateFormat, (v) => _dateFormat = v ?? _dateFormat),
              key: const ValueKey('profileDateFormat'),
            ),
            picker(
              l.spmProfileLanguage,
              _label(kProfileHouseholdLocales, _householdLocale),
              () => _pickShort(
                  l.spmProfileLanguage,
                  kProfileHouseholdLocales,
                  _householdLocale,
                  (v) => _householdLocale = v ?? _householdLocale),
              key: const ValueKey('profileHouseholdLocale'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
          child: Text(
            l.spmProfileHouseholdFooter,
            style: TextStyle(
                fontSize: 13, height: 1.35, color: palette.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// The label of a `User#default_period` value, like the web's Period labels.
String periodLabel(AppLocalizations l, String key) => switch (key) {
      'last_day' => l.spmPeriodLastDay,
      'current_week' => l.spmPeriodCurrentWeek,
      'last_7_days' => l.spmPeriodLast7Days,
      'current_month' => l.spmPeriodCurrentMonth,
      'last_month' => l.spmPeriodLastMonth,
      'last_30_days' => l.spmPeriodLast30Days,
      'last_90_days' => l.spmPeriodLast90Days,
      'current_year' => l.spmPeriodCurrentYear,
      'last_365_days' => l.spmPeriodLast365Days,
      'last_5_years' => l.spmPeriodLast5Years,
      'last_10_years' => l.spmPeriodLast10Years,
      'all_time' => l.spmPeriodAllTime,
      _ => key,
    };
