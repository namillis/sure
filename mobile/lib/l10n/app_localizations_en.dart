// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sure Finances';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonTryAgain => 'Try Again';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonAll => 'All';

  @override
  String get commonClose => 'Close';

  @override
  String get commonUndo => 'Undo';

  @override
  String get chatSuggestionNetWorth => 'What is my current net worth?';

  @override
  String get chatSuggestionSpending =>
      'How has my spending changed this month?';

  @override
  String get chatSuggestionSavings => 'How can I improve my savings rate?';

  @override
  String get chatSuggestionExpenses => 'What are my biggest expenses lately?';

  @override
  String get loginEmailLabel => 'Email';

  @override
  String get loginEmailRequired => 'Email is required';

  @override
  String get loginEmailInvalid => 'Please enter a valid email';

  @override
  String get loginPasswordLabel => 'Password';

  @override
  String get loginPasswordRequired => 'Password is required';

  @override
  String get loginSignIn => 'Sign in';

  @override
  String get loginSignInWithGoogle => 'Sign in with Google';

  @override
  String get loginMfaLabel => 'Authentication Code';

  @override
  String get loginApiKeyLabel => 'API Key';

  @override
  String get navHome => 'Home';

  @override
  String get navIntro => 'Intro';

  @override
  String get navAssistant => 'Assistant';

  @override
  String get dashboardSyncError => 'Sync failed';

  @override
  String get dashboardSyncFailed => 'Sync failed. Please try again.';

  @override
  String get dashboardRefreshing => 'Refreshing accounts…';

  @override
  String get dashboardAccountsUpdated => 'Accounts updated';

  @override
  String get dashboardSyncing => 'Syncing data from server…';

  @override
  String get dashboardSynced => 'Synced';

  @override
  String get dashboardErrorLoadingAccounts => 'Failed to load accounts';

  @override
  String get dashboardNoAccounts => 'No accounts yet';

  @override
  String get chatListTitle => 'Chats';

  @override
  String get chatListNewChat => 'New chat';

  @override
  String get chatListEmpty => 'No chats yet';

  @override
  String get chatListEmptySubtitle =>
      'Start a conversation with your AI assistant';

  @override
  String get chatListDeleteTitle => 'Delete Chat';

  @override
  String get chatConversationNewTitle => 'New Conversation';

  @override
  String get chatConversationMessageHint => 'Ask anything about your finances…';

  @override
  String chatConversationGreetingWithName(String firstName) {
    return 'Hi $firstName, how can I help?';
  }

  @override
  String get chatConversationGreetingNoName => 'Hi there, how can I help?';

  @override
  String get transactionFormNewTitle => 'New Transaction';

  @override
  String get transactionFormTypeLabel => 'Type';

  @override
  String get transactionFormTypeExpense => 'Expense';

  @override
  String get transactionFormTypeIncome => 'Income';

  @override
  String get transactionFormAmountLabel => 'Amount';

  @override
  String get transactionFormDateLabel => 'Date';

  @override
  String get transactionFormNameLabel => 'Name';

  @override
  String get transactionFormCategoryLabel => 'Category';

  @override
  String get transactionEditNameLabel => 'Name';

  @override
  String get transactionEditNameRequired => 'Name is required';

  @override
  String get transactionEditCategoryLabel => 'Category';

  @override
  String get transactionEditMerchantLabel => 'Merchant';

  @override
  String get transactionEditTagsLabel => 'Tags';

  @override
  String get transactionsListDeleteTitle => 'Delete Transaction';

  @override
  String transactionsListDeleteSingleContent(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get transactionsListDeleteMultiTitle => 'Delete Transactions';

  @override
  String get transactionsListDeleteMultiContent =>
      'Are you sure you want to delete the selected transactions?';

  @override
  String get transactionsListAuthFailed =>
      'Authentication failed: Please log in again';

  @override
  String get transactionsListNoTransactionsYet => 'No transactions yet';

  @override
  String get transactionsListEmptyAddFirst =>
      'Tap + to add your first transaction';

  @override
  String get transactionsListNoCategoryMatch =>
      'No transactions match this category';

  @override
  String get transactionsListRetry => 'Retry';

  @override
  String get transactionsListDeletedSuccess => 'Transaction deleted';

  @override
  String get transactionsListSingleDeleteFailed =>
      'Failed to delete transaction';

  @override
  String transactionsListDeletedMulti(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count transactions',
      one: 'Deleted $count transaction',
    );
    return '$_temp0';
  }

  @override
  String get transactionsListDeleteFailed => 'Failed to delete transactions';

  @override
  String get transactionsListDeleteNoToken =>
      'Failed to delete: No access token';

  @override
  String get transactionsListUndoTitle => 'Undo Transaction';

  @override
  String get transactionsListUndoRemovePending =>
      'Remove this pending transaction?';

  @override
  String get transactionsListUndoRestoreConfirm => 'Restore this transaction?';

  @override
  String get transactionsListUndoPendingRemoved =>
      'Pending transaction removed';

  @override
  String get transactionsListUndoRestored => 'Transaction restored';

  @override
  String get transactionsListUndoFailed => 'Failed to undo transaction';

  @override
  String get settingsSectionDisplay => 'Display';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsPrivacyHideAmountsLabel => 'Hide amounts';

  @override
  String get settingsUpdateAvailableTitle => 'Update Available';

  @override
  String settingsUpdateAvailableContent(String version) {
    return 'Version $version is available. Update now?';
  }

  @override
  String get settingsUpdateNewerVersionFallback => 'a newer version';

  @override
  String get settingsUpdateNow => 'Update Now';

  @override
  String get settingsNoUpdateAvailable => 'You\'re on the latest version.';

  @override
  String get settingsUpdateError => 'Could not check for updates.';

  @override
  String get settingsClearDataTitle => 'Clear All Data';

  @override
  String get settingsClearDataContent =>
      'This will remove all locally cached data. Your data on the server will not be affected.';

  @override
  String get settingsClearData => 'Clear Data';

  @override
  String get settingsDeleteAccountTitle => 'Delete Account';

  @override
  String get settingsDeleteAccount => 'Delete Account';

  @override
  String get settingsSignOutTitle => 'Sign Out';

  @override
  String get settingsSignOutContent => 'Are you sure you want to sign out?';

  @override
  String get settingsSignOut => 'Sign Out';

  @override
  String get ssoOnboardingTitle => 'Link Your Account';

  @override
  String get ssoOnboardingTabLink => 'Link existing';

  @override
  String get ssoOnboardingTabCreate => 'Create new';

  @override
  String get ssoOnboardingFirstNameLabel => 'First Name';

  @override
  String get ssoOnboardingLastNameLabel => 'Last Name';

  @override
  String get ssoOnboardingLinkButton => 'Link Account';

  @override
  String get ssoOnboardingCreateButton => 'Create Account';

  @override
  String get ssoOnboardingAcceptInvitation => 'Accept Invitation';

  @override
  String get calendarTitle => 'Account Calendar';

  @override
  String get calendarAccountTypeSection => 'Account Type';

  @override
  String get calendarSegmentAssets => 'Assets';

  @override
  String get calendarSegmentLiabilities => 'Liabilities';

  @override
  String get calendarSelectAccount => 'Select Account';

  @override
  String get calendarMonthlyChange => 'Monthly Change';

  @override
  String get calendarNoTransactions => 'No transactions on this day';

  @override
  String get moreCalendar => 'Account Calendar';

  @override
  String get moreCalendarSubtitle => 'View monthly balance changes by account';

  @override
  String get moreRecentTransactions => 'Recent Transactions';

  @override
  String get moreRecentTransactionsSubtitle =>
      'View recent transactions across all accounts';

  @override
  String get biometricTitle => 'App Locked';

  @override
  String get biometricSubtitle => 'Authenticate to continue';

  @override
  String get biometricUnlock => 'Unlock';

  @override
  String get biometricAuthenticating => 'Authenticating…';

  @override
  String get biometricLogOut => 'Log out';

  @override
  String get backendConfigTitle => 'Configuration';

  @override
  String get backendConfigSubtitle => 'Update your Sure server URL';

  @override
  String get backendConfigExampleUrlsLabel => 'Example URLs';

  @override
  String get backendConfigUrlLabel => 'Sure server URL';

  @override
  String get backendConfigUrlHint => 'https://app.sure.am';

  @override
  String get backendConfigProxyHeadersLabel => 'Custom proxy headers';

  @override
  String get backendConfigProxyHeadersSubtitle =>
      'Optional headers for a reverse proxy or auth gateway';

  @override
  String backendConfigProxyHeadersCount(int count) {
    return '$count configured';
  }

  @override
  String get backendConfigTesting => 'Testing…';

  @override
  String get backendConfigTestButton => 'Test Connection';

  @override
  String get backendConfigContinueButton => 'Continue';

  @override
  String get backendConfigChangeHint =>
      'You can change this later in the settings.';

  @override
  String get recentTransactionsTitle => 'Recent Transactions';

  @override
  String get recentTransactionsEmpty => 'No Transactions';

  @override
  String get recentTransactionsDisplayLimit => 'Display Limit';

  @override
  String recentTransactionsShowN(int count) {
    return 'Show $count';
  }

  @override
  String get recentTransactionsPullToRefresh => 'Pull to refresh';

  @override
  String get logViewerTitle => 'Debug Logs';

  @override
  String get logViewerFilterAll => 'All';

  @override
  String get logViewerFilterInfo => 'Info';

  @override
  String get logViewerFilterWarning => 'Warning';

  @override
  String get logViewerFilterError => 'Error';

  @override
  String get logViewerFilterDebug => 'Debug';

  @override
  String get logViewerAutoScrollEnable => 'Enable auto-scroll';

  @override
  String get logViewerAutoScrollDisable => 'Disable auto-scroll';

  @override
  String get logViewerCopyLogs => 'Copy logs';

  @override
  String get logViewerClearLogs => 'Clear logs';

  @override
  String get logViewerLogsCopied => 'Logs copied to clipboard';

  @override
  String get logViewerEmpty => 'No logs yet';

  @override
  String connectivityPendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions pending sync',
      one: '$count transaction pending sync',
    );
    return '$_temp0';
  }

  @override
  String get connectivitySyncNow => 'Sync Now';

  @override
  String get proxyHeadersAddHeader => 'Add header';

  @override
  String get proxyHeadersNameLabel => 'Header name';

  @override
  String get proxyHeadersNameHint => 'X-Auth-Token';

  @override
  String get proxyHeadersValueLabel => 'Header value';

  @override
  String get proxyHeadersRemove => 'Remove header';

  @override
  String get accountDetailHoldingFallback => 'Holding';

  @override
  String accountDetailCashChip(String amount) {
    return 'Cash $amount';
  }

  @override
  String get biometricLockFailedRetry =>
      'Authentication failed. Tap Unlock to try again.';

  @override
  String get settingsBiometricVerifyReason =>
      'Verify biometric to enable app lock';

  @override
  String get settingsBiometricFailed => 'Biometric authentication failed.';

  @override
  String get settingsUpdateOpenStoreError => 'Unable to open store link';

  @override
  String get settingsClearDataFailed => 'Failed to clear local data.';

  @override
  String get settingsClearDataSuccessDetailed =>
      'Local data cleared successfully. Pull to refresh to sync from server.';

  @override
  String get settingsContactOpenLinkError => 'Unable to open link';

  @override
  String get settingsResetAccountContent =>
      'Resetting your account will delete all your accounts, categories, merchants, tags, and other data, but keep your user account intact.\n\nThis action cannot be undone. Are you sure?';

  @override
  String get settingsResetAccount => 'Reset Account';

  @override
  String get settingsResetAccountInitiated =>
      'Account reset has been initiated. This may take a moment.';

  @override
  String get settingsResetAccountFailed => 'Failed to reset account';

  @override
  String get settingsDeleteAccountConfirmContent =>
      'Deleting your account will permanently remove all your data and cannot be undone.\n\nAre you sure you want to delete your account?';

  @override
  String get settingsDeleteAccountFailed => 'Failed to delete account';

  @override
  String get settingsProxyHeadersNote =>
      'Headers are sent by the app with API requests. External browser SSO pages may not receive them.';

  @override
  String get settingsProxyHeadersSaved => 'Custom proxy headers saved';

  @override
  String get settingsProxyHeadersSaveFailed =>
      'Failed to save custom proxy headers.';

  @override
  String get settingsContactUs => 'Contact us';

  @override
  String get settingsProxyHeadersTileTitle => 'Custom proxy headers';

  @override
  String settingsProxyHeadersTileSubtitleCount(int count) {
    return '$count configured';
  }

  @override
  String get settingsClearDataTileSubtitle =>
      'Remove all cached transactions and accounts';

  @override
  String get settingsResetAccountTileSubtitle =>
      'Delete all accounts, categories, merchants, and tags but keep your user account';

  @override
  String get settingsDeleteAccountTileSubtitle =>
      'Permanently remove all your data. This cannot be undone.';

  @override
  String get settingsUserFallback => 'User';

  @override
  String chatListDeleteMultiContent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count chats? This cannot be undone.',
      one: 'Delete $count chat? This cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String get chatListDeletedSuccess => 'Chats deleted';

  @override
  String get chatListDeleteFailed => 'Failed to delete chats';

  @override
  String get chatListIncomplete =>
      'Some chats may be missing. The list didn\'t finish loading.';

  @override
  String get chatListError => 'Failed to load chats';

  @override
  String get chatListJustNow => 'Just now';

  @override
  String chatListDeleteSingleContent(String title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get loginSignUpOpenError => 'Unable to open sign up page';

  @override
  String get loginApiKeyDialogTitle => 'API Key Login';

  @override
  String get loginApiKeyDialogBody => 'Enter your API key to sign in.';

  @override
  String get loginApiKeyInvalid => 'Invalid API key';

  @override
  String get loginApiKeySignIn => 'Sign In';

  @override
  String get loginDemoOrSignUpPrefix => 'Demo account or ';

  @override
  String get loginSignUpLink => 'Sign Up';

  @override
  String get loginSignUpSuffix => '!';

  @override
  String get loginMfaInfo =>
      'Two-factor authentication is enabled. Enter your code.';

  @override
  String get loginMfaCodeRequired => 'Please enter your authentication code';

  @override
  String get loginOrDivider => 'or';

  @override
  String get loginServerUrlHeading => 'Sure server URL:';

  @override
  String get loginApiKeyLoginButton => 'API-Key Login';

  @override
  String get loginBackendSettingsTooltip => 'Backend Settings';

  @override
  String get transactionEditSessionExpired =>
      'Session expired. Please login again.';

  @override
  String get transactionEditUpdated => 'Transaction updated';

  @override
  String get transactionEditUpdateFailed => 'Failed to update transaction';

  @override
  String transactionEditNameMaxLength(int max) {
    return 'Name must be $max characters or fewer';
  }

  @override
  String get transactionEditNameInvalidChars =>
      'Name contains unsupported characters';

  @override
  String transactionEditNotesMaxLength(int max) {
    return 'Notes must be $max characters or fewer';
  }

  @override
  String get transactionEditNotesInvalidChars =>
      'Notes contain unsupported characters';

  @override
  String get transactionEditNoCategory => 'No category';

  @override
  String get transactionEditCurrentCategory => 'Current category';

  @override
  String get transactionEditNoMerchant => 'No merchant';

  @override
  String get transactionEditCurrentMerchant => 'Current merchant';

  @override
  String get transactionEditUnknownTag => 'Unknown tag';

  @override
  String get transactionEditSyncedOnly =>
      'Only synced transactions can be edited from mobile.';

  @override
  String get transactionFormSessionExpired =>
      'Session expired. Please login again.';

  @override
  String get transactionFormAmountRequiredPrompt => 'Please enter an amount';

  @override
  String get transactionFormAmountInvalidNumber =>
      'Please enter a valid number';

  @override
  String get transactionFormAmountTooSmall => 'Amount must be greater than 0';

  @override
  String get transactionFormCreateSuccessOnline =>
      'Transaction created successfully';

  @override
  String get transactionFormCreateSuccessOffline =>
      'Transaction saved (will sync when online)';

  @override
  String get transactionFormCreateFailed => 'Failed to create transaction';

  @override
  String transactionFormGenericError(String error) {
    return 'Error: $error';
  }

  @override
  String get transactionFormLess => 'Less';

  @override
  String get transactionFormMore => 'More';

  @override
  String get transactionFormDateHelper => 'Optional (default: today)';

  @override
  String get transactionFormNameHelper => 'Optional (default: SureApp)';

  @override
  String get transactionFormCategoryLoading => 'Loading categories…';

  @override
  String get transactionFormCategoryHelper => 'Optional';

  @override
  String get transactionFormNoCategory => 'No category';

  @override
  String get transactionFormCreateButton => 'Create Transaction';

  @override
  String get transactionFormAmountHelper => 'Required';

  @override
  String get logViewerClearConfirm =>
      'Are you sure you want to clear all logs?';

  @override
  String get logViewerClear => 'Clear';

  @override
  String get chatConversationEditTitle => 'Edit Title';

  @override
  String get chatConversationTitleLabel => 'Chat Title';

  @override
  String get chatConversationRefreshTooltip => 'Refresh';

  @override
  String get chatConversationLoadError => 'Failed to load chat';

  @override
  String get navEnableAiChatTitle => 'Turn on AI Chat?';

  @override
  String get navEnableAiChatContent =>
      'AI Chat is currently disabled in your account settings. Would you like to turn it on now?';

  @override
  String get navEnableAiChatNotNow => 'Not now';

  @override
  String get navEnableAiChatConfirm => 'Turn on AI';

  @override
  String get navEnableAiChatFailed => 'Unable to enable AI right now.';

  @override
  String get connectivitySignInToSync => 'Please sign in to sync transactions';

  @override
  String get connectivitySyncSuccess => 'Transactions synced successfully';

  @override
  String get connectivitySyncFailed =>
      'Failed to sync transactions. Please try again.';

  @override
  String get connectivityAuthFailed =>
      'Unable to authenticate. Please try again.';

  @override
  String ssoOnboardingSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get ssoOnboardingGoogleVerified => 'Google account verified';

  @override
  String get ssoOnboardingLinkCredentialsNote =>
      'Enter your existing account credentials to link with Google Sign-In.';

  @override
  String get ssoOnboardingPendingInvitationNote =>
      'You have a pending invitation. Accept it to join an existing household.';

  @override
  String get ssoOnboardingCreateIdentityNote =>
      'Create a new account using your Google identity.';

  @override
  String get ssoOnboardingFirstNameRequired => 'First name is required';

  @override
  String get ssoOnboardingLastNameRequired => 'Last name is required';

  @override
  String get backendConfigTimeout =>
      'Connection timeout. Please check the URL and try again.';

  @override
  String get backendConfigSuccess => 'Connection successful!';

  @override
  String backendConfigServerError(int code) {
    return 'Server responded with status $code. Please check if this is a Sure backend server.';
  }

  @override
  String backendConfigConnectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String backendConfigSaveFailed(String error) {
    return 'Failed to save URL: $error';
  }

  @override
  String get backendConfigUrlRequired => 'Please enter a backend URL';

  @override
  String get backendConfigUrlScheme =>
      'URL must start with http:// or https://';

  @override
  String get backendConfigUrlInvalid => 'Please enter a valid URL';

  @override
  String get backendConfigHeadersHelp =>
      'Headers are sent by the app with API requests. External browser SSO pages may not receive them.';

  @override
  String get recentTransactionsUnknownAccount => 'Unknown Account';

  @override
  String get accountDetailUnavailable =>
      'Account details are temporarily unavailable';

  @override
  String chatListMinutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String chatListHoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String chatListDaysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get chatConversationStartFailed =>
      'Failed to start conversation. Please try again.';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get budgetsPreviousMonth => 'Previous month';

  @override
  String get budgetsNextMonth => 'Next month';

  @override
  String get budgetsIncome => 'Income';

  @override
  String budgetsRolledOver(String amount) {
    return '+$amount rolled over';
  }

  @override
  String get budgetsSharedBudget => 'Shared budget';

  @override
  String get budgetsCategoriesTitle => 'Categories';

  @override
  String budgetsFilterOverBudget(int count) {
    return 'Over budget ($count)';
  }

  @override
  String budgetsBudgetNumber(int number) {
    return 'Budget $number';
  }

  @override
  String budgetsNoBudgetTitle(String month) {
    return 'No budget for $month';
  }

  @override
  String get budgetsNotSetUpMessage =>
      'No spending limits are set for this month yet. Set them up in Sure on the web.';

  @override
  String get budgetsNoCategories =>
      'No budgeted categories or spending this month.';

  @override
  String get budgetsOfflineTitle => 'You\'re offline';

  @override
  String get budgetsOfflineMessage =>
      'Connect to the internet to load this month\'s budget.';

  @override
  String get budgetsOfflineCached =>
      'Offline. Showing the figures loaded earlier.';

  @override
  String get budgetsRefreshFailed =>
      'Couldn\'t refresh. Showing the figures loaded earlier.';

  @override
  String get budgetsLoadFailed => 'Couldn\'t load budgets';

  @override
  String get budgetsSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String budgetCategoryTransactionsEmpty(String month) {
    return 'No transactions in this category for $month.';
  }

  @override
  String get budgetCategoryTransactionsLoadMore => 'Load more';

  @override
  String get budgetCategoryTransactionsLoadFailed =>
      'Couldn\'t load transactions';

  @override
  String get cashFlowTitle => 'Cash Flow';

  @override
  String get cashFlowPeriodCurrentMonth => 'This month';

  @override
  String get cashFlowPeriodLastMonth => 'Last month';

  @override
  String get cashFlowPeriodLast30Days => 'Last 30 days';

  @override
  String get cashFlowPeriodLast90Days => 'Last 90 days';

  @override
  String get cashFlowPeriodCurrentYear => 'Year to date';

  @override
  String get cashFlowPeriodLast365Days => 'Last 365 days';

  @override
  String get cashFlowIncome => 'Income';

  @override
  String get cashFlowExpenses => 'Expenses';

  @override
  String get cashFlowNetSavings => 'Net savings';

  @override
  String cashFlowSavingsRate(String rate) {
    return '$rate savings rate';
  }

  @override
  String get cashFlowExpensesByCategory => 'Expenses by category';

  @override
  String get cashFlowIncomeByCategory => 'Income by category';

  @override
  String cashFlowShareOfExpenses(String percent) {
    return '$percent of expenses';
  }

  @override
  String cashFlowShareOfIncome(String percent) {
    return '$percent of income';
  }

  @override
  String get cashFlowEmpty => 'No income or expenses in this period';

  @override
  String get cashFlowEmptySubtitle => 'Try another period or pull to refresh.';

  @override
  String get cashFlowNoExpenses => 'No expenses in this period';

  @override
  String get cashFlowNoIncome => 'No income in this period';

  @override
  String get cashFlowLoadFailed => 'Couldn\'t load cash flow';

  @override
  String get cashFlowOffline =>
      'You\'re offline. Cash flow is calculated by your Sure server, so it needs a connection.';

  @override
  String get cashFlowOutdated => 'Outdated';

  @override
  String get cashFlowTransactionsEmpty => 'No transactions in this period';

  @override
  String get cashFlowTransactionsLoadFailed => 'Couldn\'t load transactions';

  @override
  String get accountRangeWeek => '1W';

  @override
  String get accountRangeMonth => '1M';

  @override
  String get accountRangeQuarter => '3M';

  @override
  String get accountRangeYear => '1Y';

  @override
  String get accountRangeAll => 'All';

  @override
  String get accountChartNoHistory => 'No balance history for this period';

  @override
  String get accountTabHoldings => 'Holdings';

  @override
  String get accountTabActivity => 'Activity';

  @override
  String get accountTabTransactions => 'Transactions';

  @override
  String get holdingsEmpty => 'No holdings synced yet';

  @override
  String get holdingsLoadFailed => 'Couldn\'t load holdings';

  @override
  String get holdingNoCostBasis => 'No cost basis';

  @override
  String get tradesEmpty => 'No investment activity yet';

  @override
  String get tradesLoadFailed => 'Couldn\'t load activity';

  @override
  String get tradeBuy => 'Buy';

  @override
  String get tradeSell => 'Sell';

  @override
  String portfolioAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
    );
    return '$_temp0';
  }

  @override
  String portfolioUnrealizedGain(String amount, String percent) {
    return 'Unrealized $amount ($percent)';
  }

  @override
  String get portfolioAllocation => 'Allocation';

  @override
  String get portfolioAllocationOther => 'Other';

  @override
  String get portfolioAllocationCash => 'Cash';

  @override
  String get portfolioLoadFailed => 'Couldn\'t load your investments';

  @override
  String tradeQuantityAtPrice(String quantity, String price) {
    return '$quantity @ $price';
  }

  @override
  String get shellNavActivity => 'Activity';

  @override
  String get shellNavPlan => 'Plan';

  @override
  String get shellNavInvest => 'Invest';

  @override
  String get shellSettingsTitle => 'Settings';

  @override
  String get shellSectionData => 'Data';

  @override
  String get shellSectionTools => 'Tools';

  @override
  String get shellSectionApp => 'App';

  @override
  String get shellConnections => 'Connections';

  @override
  String get shellImport => 'Import';

  @override
  String get shellCategories => 'Categories';

  @override
  String get shellTags => 'Tags';

  @override
  String get shellMerchants => 'Merchants';

  @override
  String get shellRules => 'Rules';

  @override
  String get shellExport => 'Export';

  @override
  String get shellProfile => 'Profile';

  @override
  String get shellPreferences => 'Preferences';

  @override
  String get shellServer => 'Server';

  @override
  String get shellOpensOnWeb => 'Opens on the web';

  @override
  String get shellPlanBudget => 'Budget';

  @override
  String get shellPlanRecurring => 'Recurring';

  @override
  String get shellPlanGoals => 'Goals';

  @override
  String get shellPlanBills => 'Bills';

  @override
  String get shellComingSoon => 'Coming soon';

  @override
  String get shellComingSoonBody => 'This part of the app is on its way.';

  @override
  String get shellGoalsOnWeb =>
      'Goals live on the web for now. Open them here to track your progress.';

  @override
  String get shellBillsOnWeb =>
      'Bills live on the web for now. Open them here to see what\'s coming up.';

  @override
  String get shellOpenOnWeb => 'Open on the web';

  @override
  String get shellInvestLoadFailed => 'Couldn\'t load your accounts';

  @override
  String get shellWebBack => 'Back';

  @override
  String get shellWebForward => 'Forward';

  @override
  String get shellWebOpenInSafari => 'Open in Safari';

  @override
  String get shellWebOpenInBrowser => 'Open in browser';

  @override
  String get shellWebLoadFailed => 'Couldn\'t load this page';

  @override
  String get shellWebOpenFailed => 'Couldn\'t open the link';

  @override
  String get activity => 'Activity';

  @override
  String get activitySearchHint => 'Search transactions';

  @override
  String get activityClearSearch => 'Clear search';

  @override
  String get activityFilterDate => 'Date';

  @override
  String get activityDateThisMonth => 'This month';

  @override
  String get activityDateLastMonth => 'Last month';

  @override
  String get activityDateLast90Days => 'Last 90 days';

  @override
  String get activityDateThisYear => 'This year';

  @override
  String get activityDateAll => 'All time';

  @override
  String get activityDateCustom => 'Custom range…';

  @override
  String get activityFilterCategory => 'Category';

  @override
  String get activityFilterAccount => 'Account';

  @override
  String get activityFilterTags => 'Tags';

  @override
  String get activityFilterType => 'Type';

  @override
  String get activityTypeAll => 'All types';

  @override
  String get activityTypeExpense => 'Expenses';

  @override
  String get activityTypeIncome => 'Income';

  @override
  String activityFilterCount(String label, int count) {
    return '$label · $count';
  }

  @override
  String get activityClearAll => 'Clear all';

  @override
  String get activityFilterClear => 'Clear';

  @override
  String get activityFilterSearchHint => 'Find';

  @override
  String get activityFilterNoOptions => 'Nothing to choose from yet';

  @override
  String get activityUnknownDate => 'No date';

  @override
  String get activityEmpty => 'No transactions this month';

  @override
  String get activityClearFilters => 'Clear filters';

  @override
  String get activityLoadFailed => 'Couldn\'t load transactions';

  @override
  String get activityAdd => 'Add transaction';

  @override
  String get activityPickAccount => 'Choose an account';

  @override
  String get activityNoAccounts => 'Add an account first.';

  @override
  String activitySelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get activityCategorize => 'Categorize';

  @override
  String get activityPickCategory => 'Choose a category';

  @override
  String activityCategorizing(int done, int total) {
    return 'Categorizing $done of $total…';
  }

  @override
  String activityCategorized(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Categorized $count transactions',
      one: 'Categorized 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String activityDeleting(int done, int total) {
    return 'Deleting $done of $total…';
  }

  @override
  String activityBulkPartial(int done, int total, int failed) {
    return '$done of $total done. $failed failed and are still selected.';
  }

  @override
  String get activitySessionExpired => 'Your session expired. Sign in again.';

  @override
  String get recurring => 'Recurring';

  @override
  String get recurringAdd => 'Add recurring';

  @override
  String get recurringGroupUpcoming => 'Upcoming this month';

  @override
  String get recurringGroupLater => 'Later';

  @override
  String get recurringGroupSuggested => 'Suggested';

  @override
  String get recurringGroupInactive => 'Inactive';

  @override
  String get recurringEmptyTitle => 'No recurring transactions yet';

  @override
  String get recurringEmptyBody =>
      'Add bills, subscriptions and income that repeat to see what\'s coming up.';

  @override
  String get recurringLoadFailed => 'Couldn\'t load recurring transactions';

  @override
  String get recurringRetry => 'Try again';

  @override
  String recurringEveryWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count weeks',
      one: 'Weekly',
    );
    return '$_temp0';
  }

  @override
  String recurringEveryMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count months',
      one: 'Monthly',
    );
    return '$_temp0';
  }

  @override
  String recurringEveryYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $count years',
      one: 'Yearly',
    );
    return '$_temp0';
  }

  @override
  String get recurringStatusActive => 'Active';

  @override
  String get recurringStatusPaused => 'Paused';

  @override
  String get recurringStatusInactive => 'Inactive';

  @override
  String get recurringStatusSuggested => 'Suggested';

  @override
  String get recurringStatusEnded => 'Ended';

  @override
  String get recurringIncome => 'Income';

  @override
  String get recurringExpense => 'Expense';

  @override
  String get recurringActionPause => 'Pause';

  @override
  String recurringDeleteTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get recurringDeleteBody =>
      'This removes the recurring item. Your past transactions stay as they are.';

  @override
  String get recurringDeleted => 'Recurring item deleted';

  @override
  String recurringPausedMessage(String name) {
    return '$name paused';
  }

  @override
  String recurringActivatedMessage(String name) {
    return '$name activated';
  }

  @override
  String get recurringActionFailed => 'Couldn\'t update. Please try again.';

  @override
  String get recurringNewTitle => 'New recurring';

  @override
  String get recurringEditTitle => 'Edit recurring';

  @override
  String get recurringFieldName => 'Name';

  @override
  String get recurringFieldAmount => 'Amount';

  @override
  String get recurringFieldCurrency => 'Currency';

  @override
  String get recurringFieldAccount => 'Account';

  @override
  String get recurringNoAccount => 'No account';

  @override
  String get recurringFieldNextDate => 'Next expected date';

  @override
  String get recurringFieldLastDate => 'Last occurrence';

  @override
  String get recurringFieldActive => 'Active';

  @override
  String get recurringFieldActiveHint =>
      'Inactive items aren\'t expected or counted in totals';

  @override
  String get recurringFieldAutopay => 'Autopay';

  @override
  String get recurringFieldPaymentUrl => 'Payment link';

  @override
  String get recurringFieldNotes => 'Notes';

  @override
  String get recurringCadenceNote =>
      'New items repeat monthly on the day of the next expected date. Change the schedule on the web.';

  @override
  String get recurringLockedNote =>
      'Name, amount, currency, account and schedule can only be changed on the web.';

  @override
  String get recurringErrorNameRequired => 'Enter a name';

  @override
  String get recurringErrorAmountInvalid => 'Enter an amount greater than zero';

  @override
  String get recurringErrorCurrencyInvalid => 'Use a 3-letter code, like USD';

  @override
  String get recurringErrorUrlInvalid =>
      'Enter a link starting with http:// or https://';

  @override
  String get recurringErrorLastAfterNext =>
      'Must be before the next expected date';

  @override
  String get recurringSaveFailed => 'Couldn\'t save. Please try again.';

  @override
  String get insightsTitle => 'Insights';

  @override
  String get insightsDismiss => 'Dismiss';

  @override
  String get insightsPriorityHigh => 'High priority';

  @override
  String get insightsDismissFailed => 'Couldn\'t dismiss the insight';

  @override
  String get spendingVsNormalTitle => 'Spending vs normal';

  @override
  String get accountActions => 'More actions';

  @override
  String get accountActionsUpdateBalance => 'Update balance';

  @override
  String get accountActionsAddTrade => 'Add trade';

  @override
  String get accountActionsEditTrade => 'Edit trade';

  @override
  String get accountActionsSyncNow => 'Sync now';

  @override
  String get accountActionsDate => 'Date';

  @override
  String get accountActionsNewBalance => 'New balance';

  @override
  String accountActionsCurrentBalance(String amount) {
    return 'Current balance: $amount';
  }

  @override
  String get accountActionsNote => 'Note (optional)';

  @override
  String get accountActionsSave => 'Save';

  @override
  String get accountActionsRequired => 'Required';

  @override
  String get accountActionsBalanceRequired => 'Enter the new balance';

  @override
  String get accountActionsInvalidNumber => 'Enter a valid number';

  @override
  String get accountActionsMustBePositive => 'Must be greater than zero';

  @override
  String get accountActionsFeeInvalid => 'Fees can\'t be negative';

  @override
  String get accountActionsBalanceUpdated => 'Balance updated';

  @override
  String get accountActionsBuy => 'Buy';

  @override
  String get accountActionsSell => 'Sell';

  @override
  String get accountActionsSecurity => 'Security';

  @override
  String get accountActionsSecurityHint => 'Ticker, e.g. AAPL';

  @override
  String get accountActionsSecurityRequired => 'Enter a ticker';

  @override
  String get accountActionsEditTradeNote =>
      'The security and fees can\'t be changed. Delete and re-add the trade instead.';

  @override
  String get accountActionsQuantity => 'Quantity';

  @override
  String get accountActionsPrice => 'Price per share';

  @override
  String get accountActionsFee => 'Fees (optional)';

  @override
  String get accountActionsTotalCost => 'Total cost';

  @override
  String get accountActionsTotalProceeds => 'Total proceeds';

  @override
  String get accountActionsTradeAdded => 'Trade added';

  @override
  String get accountActionsTradeUpdated => 'Trade updated';

  @override
  String get accountActionsTradeDeleted => 'Trade deleted';

  @override
  String get accountActionsDeleteTrade => 'Delete trade';

  @override
  String get accountActionsDeleteTradeConfirm =>
      'Delete this trade? This can\'t be undone.';

  @override
  String get accountActionsSyncStarting => 'Starting sync...';

  @override
  String get accountActionsSyncing => 'Syncing...';

  @override
  String accountActionsSyncElapsed(String elapsed) {
    return '$elapsed elapsed';
  }

  @override
  String get accountActionsSyncComplete => 'Sync complete';

  @override
  String get accountActionsSyncFailed => 'Sync failed';

  @override
  String accountActionsSyncFailedDetail(String message) {
    return 'Sync failed: $message';
  }

  @override
  String get accountActionsSyncTimeout =>
      'Still syncing after 2 minutes. It will keep running in the background.';

  @override
  String get accountActionsHide => 'Hide';

  @override
  String get accountActionsClose => 'Close';

  @override
  String get accountActionsNeverSynced => 'Not synced yet';

  @override
  String get accountActionsSyncedJustNow => 'Synced just now';

  @override
  String accountActionsSyncedMinutesAgo(int count) {
    return 'Synced ${count}m ago';
  }

  @override
  String accountActionsSyncedHoursAgo(int count) {
    return 'Synced ${count}h ago';
  }

  @override
  String accountActionsSyncedDaysAgo(int count) {
    return 'Synced ${count}d ago';
  }

  @override
  String get accountActionsSyncChipHint => 'Starts a sync of all accounts';

  @override
  String get txnDetail => 'Transaction';

  @override
  String get txnDetailOfflineNote =>
      'You\'re offline. Changes can be saved once you\'re back online.';

  @override
  String get txnDetailSplitLockedFields =>
      'Amount, date and type come from the split. Edit the split to change them.';

  @override
  String get txnDetailChooseMerchant => 'Choose merchant';

  @override
  String get txnDetailChooseTags => 'Choose tags';

  @override
  String get txnDetailSearchHint => 'Search';

  @override
  String txnDetailCreateOption(String name) {
    return 'Create “$name”';
  }

  @override
  String get txnDetailCreateFailed => 'Couldn\'t create it. Please try again.';

  @override
  String get txnDetailCreateOffline =>
      'Connect to the internet to create new items.';

  @override
  String get txnDetailPickerEmpty => 'No matches';

  @override
  String get txnDetailDone => 'Done';

  @override
  String get txnDetailSplitAction => 'Split transaction';

  @override
  String get txnDetailSplitOffline => 'Splits need an internet connection.';

  @override
  String get txnDetailSplitLoadFailed => 'Couldn\'t load the split details.';

  @override
  String get txnDetailSplitTitle => 'Split transaction';

  @override
  String txnDetailSplitTotal(String amount) {
    return 'Total $amount';
  }

  @override
  String txnDetailSplitRemaining(String amount) {
    return 'Remaining: $amount';
  }

  @override
  String txnDetailSplitOver(String amount) {
    return 'Over by $amount';
  }

  @override
  String get txnDetailSplitBalanced => 'The parts add up to the total.';

  @override
  String get txnDetailSplitSignHint =>
      'Positive amounts go the same way as the total; use a negative amount for a part that goes the other way.';

  @override
  String txnDetailSplitPartLabel(int number) {
    return 'Part $number';
  }

  @override
  String get txnDetailSplitRemoveRow => 'Remove part';

  @override
  String get txnDetailSplitRowName => 'Name (optional)';

  @override
  String get txnDetailSplitInvalidAmount =>
      'Enter a nonzero amount with at most 4 decimals.';

  @override
  String get txnDetailSplitUseRemaining => 'Use remaining amount';

  @override
  String get txnDetailSplitAddRow => 'Add part';

  @override
  String get txnDetailSplitNeedTwo => 'Add at least two parts.';

  @override
  String get txnDetailSplitSave => 'Save split';

  @override
  String get txnDetailSplitRemove => 'Remove split';

  @override
  String get txnDetailSplitRemoveConfirmTitle => 'Remove split?';

  @override
  String get txnDetailSplitRemoveConfirmBody =>
      'The parts are deleted and the original transaction counts again.';

  @override
  String get txnDetailSplitSaved => 'Split saved';

  @override
  String get txnDetailSplitRemoved => 'Split removed';

  @override
  String get dataInImportTitle => 'Import';

  @override
  String get dataInHistoryHeader => 'Import history';

  @override
  String get dataInHistoryEmpty => 'No imports yet.';

  @override
  String get dataInHistoryFailed => 'Couldn\'t load import history.';

  @override
  String get dataInRetry => 'Try again';

  @override
  String get dataInRefresh => 'Refresh';

  @override
  String dataInRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows',
      one: '1 row',
    );
    return '$_temp0';
  }

  @override
  String dataInInvalidRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows have errors',
      one: '1 row has errors',
    );
    return '$_temp0';
  }

  @override
  String get dataInStatusLabel => 'Status';

  @override
  String get dataInCreatedLabel => 'Created';

  @override
  String get dataInStatusLoadFailed => 'Couldn\'t refresh the status.';

  @override
  String get dataInStatusPending => 'Not started';

  @override
  String get dataInStatusImporting => 'Importing…';

  @override
  String get dataInStatusComplete => 'Complete';

  @override
  String get dataInStatusFailed => 'Failed';

  @override
  String get dataInStatusReverting => 'Reverting…';

  @override
  String get dataInStatusRevertFailed => 'Revert failed';

  @override
  String get dataInTypeTransactions => 'Transactions';

  @override
  String get dataInTypeTrades => 'Trades';

  @override
  String get dataInTypeAccounts => 'Accounts';

  @override
  String dataInStepOf(int step, int total, String title) {
    return 'Step $step of $total: $title';
  }

  @override
  String get dataInStepFile => 'Choose file';

  @override
  String get dataInStepMap => 'Map columns';

  @override
  String get dataInStepPreview => 'Preview';

  @override
  String get dataInStepPublish => 'Import';

  @override
  String dataInFileHelp(String size) {
    return 'Import transactions from a CSV file into one account. Files can be up to $size.';
  }

  @override
  String get dataInAccountLabel => 'Account';

  @override
  String get dataInNoAccounts => 'Add an account first.';

  @override
  String get dataInChooseCsv => 'Choose CSV file';

  @override
  String get dataInChooseFile => 'Choose file';

  @override
  String get dataInChooseAnother => 'Change file';

  @override
  String get dataInNotCsv => 'Choose a file that ends in .csv.';

  @override
  String get dataInFileEmpty => 'This file is empty.';

  @override
  String dataInFileTooLarge(String size) {
    return 'This file is too large. The limit is $size.';
  }

  @override
  String get dataInReadFailed => 'Couldn\'t read the file.';

  @override
  String get dataInContinue => 'Continue';

  @override
  String get dataInBack => 'Back';

  @override
  String dataInDetected(int columns, int rows) {
    String _temp0 = intl.Intl.pluralLogic(
      columns,
      locale: localeName,
      other: '$columns columns',
      one: '1 column',
    );
    String _temp1 = intl.Intl.pluralLogic(
      rows,
      locale: localeName,
      other: '$rows rows',
      one: '1 row',
    );
    return 'Found $_temp0 and $_temp1.';
  }

  @override
  String dataInRequiredLabel(String label) {
    return '$label (required)';
  }

  @override
  String get dataInColumnDate => 'Date column';

  @override
  String get dataInColumnAmount => 'Amount column';

  @override
  String get dataInColumnName => 'Name column';

  @override
  String get dataInColumnCategory => 'Category column';

  @override
  String get dataInColumnTags => 'Tags column';

  @override
  String get dataInColumnNotes => 'Notes column';

  @override
  String get dataInColumnNone => 'None';

  @override
  String get dataInDateFormat => 'Date format';

  @override
  String get dataInNumberFormat => 'Number format';

  @override
  String get dataInSignage => 'Amount signs';

  @override
  String get dataInSignagePositive => 'Income is positive';

  @override
  String get dataInSignageNegative => 'Income is negative';

  @override
  String get dataInSeparator => 'Column separator';

  @override
  String get dataInSeparatorComma => 'Comma (,)';

  @override
  String get dataInSeparatorSemicolon => 'Semicolon (;)';

  @override
  String get dataInNeedDateAndAmount =>
      'Choose the date and amount columns to continue.';

  @override
  String dataInPreviewSummary(int shown, int total) {
    return 'Showing $shown of $total rows.';
  }

  @override
  String dataInPreviewInvalid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rows don\'t match the chosen formats.',
      one: '1 row doesn\'t match the chosen formats.',
    );
    return '$_temp0';
  }

  @override
  String get dataInCategoriesNote =>
      'Categories and tags from the file may not be applied when importing from the app. You can set them on the web.';

  @override
  String get dataInPreviewEmpty => 'No rows to import.';

  @override
  String get dataInRowUntitled => '(no name)';

  @override
  String dataInRowBadDate(String value) {
    return 'Date \"$value\" doesn\'t match the date format.';
  }

  @override
  String dataInRowBadAmount(String value) {
    return 'Amount \"$value\" isn\'t a number.';
  }

  @override
  String get dataInPublish => 'Import';

  @override
  String get dataInUploading => 'Uploading…';

  @override
  String get dataInComplete => 'Import complete';

  @override
  String get dataInStillRunning =>
      'The import is still running. Check its status in the import history.';

  @override
  String get dataInKeepInBackground => 'Keep running in background';

  @override
  String get dataInRunningInBackground =>
      'The import keeps running. Its status is in the import history.';

  @override
  String get dataInRejectedRows => 'Rows the server rejected';

  @override
  String get dataInStartOver => 'Start over';

  @override
  String get dataInImportAnother => 'Import another file';

  @override
  String get dataInMoreTypesOnWeb => 'More import types on the web';

  @override
  String get dataInStatementTitle => 'Upload statement';

  @override
  String dataInStatementHelp(String size) {
    return 'Add a PDF, CSV or XLSX statement to the Statement Vault. Files can be up to $size.';
  }

  @override
  String get dataInStatementWrongType => 'Choose a PDF, CSV or XLSX file.';

  @override
  String get dataInUpload => 'Upload';

  @override
  String dataInStatementUploaded(String name) {
    return 'Uploaded $name.';
  }

  @override
  String get dataInStatementViewOnWeb => 'View statements on the web';

  @override
  String dataInStatementDuplicate(String date) {
    return 'Already uploaded on $date.';
  }

  @override
  String get dataInStatementDuplicateHidden =>
      'This file is already in the Statement Vault.';

  @override
  String get dataInStatementFailed => 'The statement couldn\'t be uploaded.';

  @override
  String get dataInStatementPickAccount =>
      'Choose an account to see its statements.';

  @override
  String get dataInStatementListFailed => 'Couldn\'t load statements.';

  @override
  String get dataInStatementListEmpty => 'No statements for this account yet.';

  @override
  String get dataInStatementRecent => 'Recent statements';

  @override
  String dataInStatementPeriod(String start, String end) {
    return '$start – $end';
  }

  @override
  String dataInStatementAdded(String date) {
    return 'Added $date';
  }

  @override
  String get manageSearch => 'Search';

  @override
  String get manageClearSearch => 'Clear search';

  @override
  String manageNoMatches(String query) {
    return 'Nothing matches “$query”.';
  }

  @override
  String get manageNameLabel => 'Name';

  @override
  String get manageNameRequired => 'Enter a name.';

  @override
  String get manageColor => 'Color';

  @override
  String manageColorOption(int number) {
    return 'Color $number';
  }

  @override
  String get manageColorAutomatic => 'Automatic';

  @override
  String get manageEditOnWeb => 'Edit on the web';

  @override
  String get manageActionFailed => 'Something went wrong. Try again.';

  @override
  String get manageCategoriesTitle => 'Categories';

  @override
  String get manageCategoriesEmpty => 'No categories yet';

  @override
  String get manageCategoriesEmptyBody =>
      'Add one with +. Categories sort your spending and income.';

  @override
  String get manageCategoriesLoadFailed => 'Couldn\'t load categories.';

  @override
  String get manageCategoryAdd => 'Add category';

  @override
  String get manageCategoryNew => 'New category';

  @override
  String get manageCategoryParent => 'Parent category';

  @override
  String get manageCategoryNoParent => 'None (top level)';

  @override
  String get manageCategoryIconHint =>
      'Sure picks an icon that fits the name. You can change it on the web.';

  @override
  String manageCategoryCreated(String name) {
    return 'Category “$name” added';
  }

  @override
  String manageCategorySubcategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subcategories',
      one: '1 subcategory',
      zero: 'No subcategories',
    );
    return '$_temp0';
  }

  @override
  String manageCategoryInParent(String parent) {
    return 'Subcategory of $parent';
  }

  @override
  String get manageCategoryInfoBody =>
      'Rename, recolor, change the icon of, merge or delete categories on the web.';

  @override
  String get manageTagsTitle => 'Tags';

  @override
  String get manageTagsEmpty => 'No tags yet';

  @override
  String get manageTagsEmptyBody =>
      'Tags group transactions across categories, like a trip or a project.';

  @override
  String get manageTagsLoadFailed => 'Couldn\'t load tags.';

  @override
  String get manageTagAdd => 'Add tag';

  @override
  String get manageTagNew => 'New tag';

  @override
  String get manageTagEdit => 'Edit tag';

  @override
  String manageTagCreated(String name) {
    return 'Tag “$name” added';
  }

  @override
  String get manageTagSaved => 'Tag saved';

  @override
  String get manageTagDeleted => 'Tag deleted';

  @override
  String get manageTagDelete => 'Delete tag';

  @override
  String manageTagDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get manageTagDeleteBody =>
      'The tag is removed from every transaction that has it. This can\'t be undone.';

  @override
  String get manageMerchantsTitle => 'Merchants';

  @override
  String get manageMerchantsEmpty => 'No merchants yet';

  @override
  String get manageMerchantsEmptyBody =>
      'Merchants you add, and the ones your bank connections find, show up here.';

  @override
  String get manageMerchantsLoadFailed => 'Couldn\'t load merchants.';

  @override
  String get manageMerchantAdd => 'Add merchant';

  @override
  String get manageMerchantNew => 'New merchant';

  @override
  String get manageMerchantWebsite => 'Website (optional)';

  @override
  String get manageMerchantWebsiteInvalid =>
      'Enter a web address like example.com.';

  @override
  String manageMerchantCreated(String name) {
    return 'Merchant “$name” added';
  }

  @override
  String manageMerchantExists(String name) {
    return '“$name” already exists';
  }

  @override
  String get manageMerchantFamily => 'Added by you';

  @override
  String get manageMerchantProvider => 'From a bank connection';

  @override
  String get manageMerchantInfoBody =>
      'Rename, recolor, set the website or logo of, merge or delete merchants on the web.';

  @override
  String get manageExportTitle => 'Export data';

  @override
  String get manageExportIntro =>
      'An export is a ZIP file with your accounts, transactions, trades, categories, merchants and rules as CSV files, plus all of it in one all.ndjson file. Attachments are listed but their files aren\'t included.';

  @override
  String get manageExportCreate => 'Create export';

  @override
  String get manageExportStarted =>
      'Export started. It can take a few minutes.';

  @override
  String get manageExportHistory => 'Exports';

  @override
  String get manageExportEmpty =>
      'No exports yet. Create one to get a copy of your data.';

  @override
  String get manageExportLoadFailed => 'Couldn\'t load exports.';

  @override
  String get manageExportAdminOnly => 'Only a family admin can export data.';

  @override
  String get manageExportStatusPending => 'Queued';

  @override
  String get manageExportStatusProcessing => 'Preparing';

  @override
  String get manageExportStatusCompleted => 'Ready';

  @override
  String get manageExportStatusFailed => 'Failed';

  @override
  String get manageExportDownload => 'Download';

  @override
  String get manageExportDownloadFailed => 'Couldn\'t download the export.';

  @override
  String get manageExportStillPreparing =>
      'Still preparing. Pull down to check again.';

  @override
  String get p3roInsightsEmpty => 'No insights right now';

  @override
  String get p3roInsightsEmptyBody =>
      'New insights about your spending show up here.';

  @override
  String get p3roInsightsUnavailable => 'Insights aren\'t turned on';

  @override
  String get p3roInsightsUnavailableBody =>
      'Insights are a preview feature. Turn on preview features in your settings on the web to see them here.';

  @override
  String get p3roInsightsLoadFailed => 'Couldn\'t load insights.';

  @override
  String get p3roInsightsDismissHint => 'Swipe to dismiss';

  @override
  String get p3roConnectionsManageOnWeb => 'Manage connections on the web';

  @override
  String get p3roConnectionsEmpty => 'No connections yet';

  @override
  String get p3roConnectionsEmptyBody =>
      'Connect a bank or broker on the web to sync accounts automatically.';

  @override
  String get p3roConnectionsLoadFailed => 'Couldn\'t load connections.';

  @override
  String get p3roConnectionStatusConnected => 'Connected';

  @override
  String get p3roConnectionStatusSyncing => 'Syncing';

  @override
  String get p3roConnectionStatusNeedsAttention => 'Needs attention';

  @override
  String get p3roConnectionStatusDeleting => 'Being removed';

  @override
  String get p3roConnectionReconnect => 'The bank needs you to sign in again.';

  @override
  String p3roConnectionAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '$count account',
      zero: 'No accounts',
    );
    return '$_temp0';
  }

  @override
  String p3roConnectionAccountsNeedSetup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts need setup',
      one: '$count account needs setup',
    );
    return '$_temp0';
  }

  @override
  String get p3roConnectionPendingSetup => 'Accounts are waiting to be set up.';

  @override
  String get p3roConnectionFixOnWeb => 'Fix on the web';

  @override
  String get p3roRulesManageOnWeb => 'Create or reorder rules on the web';

  @override
  String get p3roRulesEmpty => 'No rules yet';

  @override
  String get p3roRulesEmptyBody =>
      'Rules categorize, tag and rename transactions automatically. Create them on the web.';

  @override
  String get p3roRulesLoadFailed => 'Couldn\'t load rules.';

  @override
  String get p3roRuleActive => 'Active';

  @override
  String get p3roRuleInactive => 'Inactive';

  @override
  String get p3roRuleResourceTransaction => 'Transactions';

  @override
  String get p3roRuleTitle => 'Rule';

  @override
  String get p3roRuleLoadFailed => 'Couldn\'t load this rule.';

  @override
  String get p3roRuleNotFound => 'This rule no longer exists.';

  @override
  String get p3roRuleConditions => 'Conditions';

  @override
  String get p3roRuleActions => 'Actions';

  @override
  String get p3roRuleRecentRuns => 'Recent runs';

  @override
  String get p3roRuleNoRuns => 'This rule hasn\'t run yet.';

  @override
  String get p3roRuleRunsLoadFailed => 'Couldn\'t load recent runs.';

  @override
  String p3roRuleEffectiveFrom(String date) {
    return 'Applies to transactions from $date';
  }

  @override
  String get p3roRuleAllTransactions => 'All transactions';

  @override
  String p3roRuleIf(String condition) {
    return 'If $condition';
  }

  @override
  String get p3roRuleMatchAll => 'All of these match';

  @override
  String get p3roRuleMatchAny => 'Any of these match';

  @override
  String p3roRuleQuoted(String value) {
    return '“$value”';
  }

  @override
  String get p3roRuleFieldName => 'Name';

  @override
  String get p3roRuleFieldAmount => 'Amount';

  @override
  String get p3roRuleFieldMerchant => 'Merchant';

  @override
  String get p3roRuleFieldCategory => 'Category';

  @override
  String get p3roRuleFieldTag => 'Tag';

  @override
  String get p3roRuleFieldAccount => 'Account';

  @override
  String get p3roRuleFieldType => 'Type';

  @override
  String get p3roRuleFieldDetails => 'Details';

  @override
  String get p3roRuleFieldNotes => 'Notes';

  @override
  String p3roRuleOpContains(String field, String value) {
    return '$field contains $value';
  }

  @override
  String p3roRuleOpNotContains(String field, String value) {
    return '$field doesn\'t contain $value';
  }

  @override
  String p3roRuleOpStartsWith(String field, String value) {
    return '$field starts with $value';
  }

  @override
  String p3roRuleOpEndsWith(String field, String value) {
    return '$field ends with $value';
  }

  @override
  String p3roRuleOpRegex(String field, String value) {
    return '$field matches the pattern $value';
  }

  @override
  String p3roRuleOpEquals(String field, String value) {
    return '$field is $value';
  }

  @override
  String p3roRuleOpNotEquals(String field, String value) {
    return '$field is not $value';
  }

  @override
  String p3roRuleOpEmpty(String field) {
    return '$field is empty';
  }

  @override
  String p3roRuleOpNotEmpty(String field) {
    return '$field is not empty';
  }

  @override
  String p3roRuleOpGreater(String field, String value) {
    return '$field is more than $value';
  }

  @override
  String p3roRuleOpAtLeast(String field, String value) {
    return '$field is at least $value';
  }

  @override
  String p3roRuleOpLess(String field, String value) {
    return '$field is less than $value';
  }

  @override
  String p3roRuleOpAtMost(String field, String value) {
    return '$field is at most $value';
  }

  @override
  String get p3roRuleTypeIncome => 'income';

  @override
  String get p3roRuleTypeExpense => 'expense';

  @override
  String get p3roRuleTypeTransfer => 'transfer';

  @override
  String get p3roRuleSomeCategory => 'a category';

  @override
  String get p3roRuleSomeTag => 'a tag';

  @override
  String get p3roRuleSomeMerchant => 'a merchant';

  @override
  String get p3roRuleSomeAccount => 'an account';

  @override
  String p3roRuleActionSetCategory(String value) {
    return 'Set category to $value';
  }

  @override
  String p3roRuleActionAddTag(String value) {
    return 'Add tag $value';
  }

  @override
  String p3roRuleActionSetMerchant(String value) {
    return 'Set merchant to $value';
  }

  @override
  String p3roRuleActionRename(String value) {
    return 'Rename to $value';
  }

  @override
  String p3roRuleActionTransfer(String value) {
    return 'Mark as a transfer or payment to $value';
  }

  @override
  String p3roRuleActionActivityLabel(String value) {
    return 'Set investment activity to $value';
  }

  @override
  String get p3roRuleActionExclude => 'Exclude from budgets and reports';

  @override
  String get p3roRuleActionAutoCategorize => 'Categorize with AI';

  @override
  String get p3roRuleActionAutoMerchants => 'Detect merchants with AI';

  @override
  String get p3roRuleActionClassifier =>
      'Categorize with the classifier (no AI)';

  @override
  String get p3roRuleActionFillMerchants =>
      'Fill missing merchants from similar transactions';

  @override
  String get p3roRuleActionEmail => 'Send an email notification';

  @override
  String get p3roRuleActionSplit => 'Split the transaction';

  @override
  String get p3roRuleRunSuccess => 'Succeeded';

  @override
  String get p3roRuleRunFailed => 'Failed';

  @override
  String get p3roRuleRunPending => 'Running';

  @override
  String get p3roRuleRunManual => 'Run by hand';

  @override
  String get p3roRuleRunScheduled => 'Automatic';

  @override
  String p3roRuleRunCounts(int modified, int processed) {
    return '$modified of $processed transactions changed';
  }

  @override
  String p3roRuleRunQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions queued',
      one: '$count transaction queued',
    );
    return '$_temp0';
  }

  @override
  String p3apZeroHoldingsHidden(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings worth $amount hidden',
      one: '1 holding worth $amount hidden',
    );
    return '$_temp0';
  }

  @override
  String p3apZeroHoldingsShown(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count holdings worth $amount shown',
      one: '1 holding worth $amount shown',
    );
    return '$_temp0';
  }

  @override
  String get p3apShow => 'Show';

  @override
  String get p3apHide => 'Hide';

  @override
  String p3apAllHoldingsZero(String amount) {
    return 'Every holding is worth $amount';
  }

  @override
  String get p3apSetPriceTitle => 'Set price';

  @override
  String get p3apSetPriceIntro =>
      'Saves a closing price for a security no price provider tracks. Values update after the account syncs.';

  @override
  String p3apCurrentPrice(String price) {
    return 'Current price: $price';
  }

  @override
  String get p3apPriceLabel => 'Price per share';

  @override
  String get p3apPriceRequired => 'Enter a price';

  @override
  String get p3apPriceInvalid => 'Enter a price greater than 0';

  @override
  String get p3apPriceSaved =>
      'Price saved. Values update after the account syncs.';

  @override
  String get p3apPriceSelfHostedOnly =>
      'Prices can only be set on a self-hosted server, because they are shared by everyone on the server.';

  @override
  String get p3apPriceNotAllowed =>
      'This security can\'t be priced from your accounts. You need a trade in it, or to hold it in a linked account you can edit.';

  @override
  String get p3ocUpdatedJustNow => 'Updated just now';

  @override
  String p3ocUpdatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count minutes ago',
      one: 'Updated $count minute ago',
    );
    return '$_temp0';
  }

  @override
  String p3ocUpdatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count hours ago',
      one: 'Updated $count hour ago',
    );
    return '$_temp0';
  }

  @override
  String p3ocUpdatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Updated $count days ago',
      one: 'Updated $count day ago',
    );
    return '$_temp0';
  }

  @override
  String get p3ocOfflineMayBeOutdated =>
      'You\'re offline. Data shown may be out of date.';

  @override
  String get p3rpTitle => 'Reports';

  @override
  String get p3rpPeriodMonth => 'Month';

  @override
  String get p3rpPeriodThreeMonths => '3M';

  @override
  String get p3rpPeriodYearToDate => 'YTD';

  @override
  String get p3rpPeriodYear => '1Y';

  @override
  String get p3rpNetWorth => 'Net worth';

  @override
  String get p3rpNetWorthChartLabel => 'Net worth over the selected period';

  @override
  String get p3rpNetWorthNoHistory => 'No balance history for this period.';

  @override
  String get p3rpNetWorthFailed => 'Couldn\'t load net worth history.';

  @override
  String get p3rpCashFlow => 'Cash flow';

  @override
  String get p3rpIn => 'In';

  @override
  String get p3rpOut => 'Out';

  @override
  String get p3rpSaved => 'Saved';

  @override
  String p3rpSavedShare(String percent) {
    return '$percent of In';
  }

  @override
  String get p3rpCashFlowFailed => 'Couldn\'t load cash flow.';

  @override
  String get p3rpSpending => 'Spending by category';

  @override
  String get p3rpNoSpending => 'No spending in this period.';

  @override
  String p3rpShowAll(int count) {
    return 'Show all ($count)';
  }

  @override
  String get p3rpShowLess => 'Show less';

  @override
  String p3rpAboveNormal(String percent) {
    return '$percent above normal';
  }

  @override
  String get dsToday => 'Today';

  @override
  String get dsYesterday => 'Yesterday';

  @override
  String get dsCancel => 'Cancel';

  @override
  String get dsSave => 'Save';

  @override
  String get dsDone => 'Done';

  @override
  String get dsSplit => 'Split';

  @override
  String get dsTransfer => 'Transfer';

  @override
  String get dsUncategorized => 'Uncategorized';

  @override
  String get dsCategorize => 'Categorize';

  @override
  String get dsDelete => 'Delete';

  @override
  String get dsPending => 'Pending';

  @override
  String get dsFailed => 'Failed';

  @override
  String get dsaSelect => 'Select';

  @override
  String dsaNoMatchesFor(String query) {
    return 'No matches for \"$query\"';
  }

  @override
  String get dsaNoMatches => 'No matches';

  @override
  String get dsaNoMatchesBody => 'Try fewer filters or a longer date range.';

  @override
  String get dsaEmptyTitle => 'No transactions yet';

  @override
  String get dsaEmptyBody => 'Add one with + or connect an account on the web.';

  @override
  String get dsaEmptyMonthBody =>
      'Transactions you add or sync this month show up here.';

  @override
  String dsaSummary(String range, String inflow, String outflow) {
    return '$range · In $inflow · Out $outflow';
  }

  @override
  String dsaSummaryPartial(int loaded, int total) {
    return 'Totals for the $loaded of $total loaded';
  }

  @override
  String get dsaCategorizeFailed => 'Couldn\'t categorize the transaction.';

  @override
  String get dspSyncedJustNow => 'synced just now';

  @override
  String dspSyncedMinutesAgo(int count) {
    return 'synced ${count}m ago';
  }

  @override
  String dspSyncedHoursAgo(int count) {
    return 'synced ${count}h ago';
  }

  @override
  String dspSyncedDaysAgo(int count) {
    return 'synced ${count}d ago';
  }

  @override
  String dspSharesAtPrice(String quantity, String price) {
    return '$quantity sh · $price';
  }

  @override
  String get dspClearFilter => 'Clear filter';

  @override
  String get dspSelect => 'Select transactions';

  @override
  String get dspDoneSelecting => 'Done selecting';

  @override
  String get dspDeleteSelected => 'Delete selected';

  @override
  String get dspNewTransaction => 'New transaction';

  @override
  String dstSplitValue(int count) {
    return 'Split ($count)';
  }

  @override
  String get dstAddNote => 'Add a note';

  @override
  String get dstAddTag => 'Add tag';

  @override
  String get dstRecurring => 'Recurring';

  @override
  String get dstRecurringSetUp => 'Set up';

  @override
  String get dstOpenOnWeb => 'Open on the web';

  @override
  String get dstDeleteTransaction => 'Delete transaction';

  @override
  String get dstEditAmount => 'Edit amount';

  @override
  String get dstSearchCategories => 'Search categories';

  @override
  String get dstNoCategoryMatches => 'No categories match';

  @override
  String get dstNoCategoryMatchesBody => 'Try a different search.';

  @override
  String get dstNoCategories => 'No categories yet';

  @override
  String get dshOutdated => 'Outdated';

  @override
  String get dshShowAmounts => 'Show amounts';

  @override
  String get dshHideAmounts => 'Hide amounts';

  @override
  String dshSpendingAbove(String percent) {
    return 'Spending $percent above normal';
  }

  @override
  String dshSpendingBelow(String percent) {
    return 'Spending $percent below normal';
  }

  @override
  String get dshSpendingAboutNormal => 'Spending about normal';

  @override
  String get dshRecent => 'Recent';

  @override
  String get dshSeeAll => 'See all';

  @override
  String get dshAccounts => 'Accounts';

  @override
  String get dshAddAccount => 'Add account';

  @override
  String dshGroupTitle(String type, int count) {
    return '$type · $count';
  }

  @override
  String dshEmptyAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count empty accounts',
      one: '1 empty account',
    );
    return '$_temp0';
  }

  @override
  String get dshShow => 'Show';

  @override
  String get dshHide => 'Hide';

  @override
  String get dshGroupNoAccounts => 'No accounts of this type';

  @override
  String get dshTypeDepository => 'Cash';

  @override
  String get dshTypeCreditCard => 'Credit cards';

  @override
  String get dshTypeInvestment => 'Investments';

  @override
  String get dshTypeCrypto => 'Crypto';

  @override
  String get dshTypeProperty => 'Property';

  @override
  String get dshTypeVehicle => 'Vehicles';

  @override
  String get dshTypeOtherAsset => 'Other assets';

  @override
  String get dshTypeLoan => 'Loans';

  @override
  String get dshTypeOtherLiability => 'Other liabilities';

  @override
  String get dshEmptyBody =>
      'Connect a bank on the web, or add a manual account like a house or car.';

  @override
  String get dshConnectOnWeb => 'Connect on the web';

  @override
  String get dshAddManualAccount => 'Add a manual account';

  @override
  String dshOfflineShowing(String age) {
    return 'Offline · showing data from $age ago';
  }

  @override
  String get dshOfflineShowingJustNow => 'Offline · showing data from just now';

  @override
  String dshAgoMinutes(int count) {
    return '${count}m';
  }

  @override
  String dshAgoHours(int count) {
    return '${count}h';
  }

  @override
  String dshAgoDays(int count) {
    return '${count}d';
  }

  @override
  String get dshAgoNow => 'now';

  @override
  String get dshSyncShort => 'Sync';

  @override
  String get dshSyncFailedShort => 'Failed';

  @override
  String get dshAddTransaction => 'Add';

  @override
  String get ds2iEmptyTitle => 'No investments yet';

  @override
  String get ds2iEmptyBody =>
      'Connect a brokerage or add an investment account on the web.';

  @override
  String get ds2iCurrency => 'Currency';

  @override
  String get ds2pNoLimit => 'no limit';

  @override
  String ds2pOverBy(String amount) {
    return 'Over by $amount';
  }

  @override
  String get ds2pLeft => 'left';

  @override
  String get ds2pOver => 'over';

  @override
  String ds2pSpentOf(String spent, String budgeted) {
    return '$spent spent of $budgeted';
  }

  @override
  String ds2pDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get ds2pNoBudgetBody =>
      'Budgets are set up on the web. They show here once they exist.';

  @override
  String get ds2pSetUpOnWeb => 'Set up on the web';

  @override
  String get ds2pEditOnWeb => 'Edit on web';

  @override
  String ds2pMonthlySummary(String outflow, String inflow) {
    return 'Monthly out $outflow · in $inflow';
  }

  @override
  String get ds2pResume => 'Resume';

  @override
  String get ds2sProfileOnWeb => 'Profile on web';

  @override
  String get ds2sImportUpload => 'Import · Upload statement';

  @override
  String get ds2sImportCsv => 'Import CSV';

  @override
  String get ds2sMetadata => 'Categories, tags, merchants';

  @override
  String get ds2sThemeAuto => 'Auto';

  @override
  String get ds2sFaceIdLock => 'Face ID lock';

  @override
  String get ds2sTouchIdLock => 'Touch ID lock';

  @override
  String get ds2sBiometricLock => 'Biometric lock';

  @override
  String get ds2sPasswordPasskeys => 'Password and passkeys';

  @override
  String get ds2sVersion => 'Version';

  @override
  String get ds2sCheckForUpdates => 'Check for updates';

  @override
  String get ds2sDebugLogs => 'Debug logs';

  @override
  String get ds2sSignOut => 'Sign out';

  @override
  String get ds2sAccountActionsLink =>
      'Clear local data · Reset · Delete account';

  @override
  String get ds2sAccountActions => 'Account actions';

  @override
  String get ds2sClearLocalData => 'Clear local data';

  @override
  String get ds2sResetAccount => 'Reset account';

  @override
  String get ds2sDeleteAccount => 'Delete account';

  @override
  String ds3rSince(String date) {
    return 'since $date';
  }

  @override
  String ds3rOtherCurrency(String amount, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Also $amount in $count accounts',
      one: 'Also $amount in 1 account',
    );
    return '$_temp0';
  }

  @override
  String get ds3rEmptyBody => 'Try a longer range.';

  @override
  String get ds3fNewTransaction => 'New transaction';

  @override
  String get ds3fAdd => 'Add';

  @override
  String get ds3fClearCategory => 'Clear category';

  @override
  String get ds3fOptional => 'Optional';

  @override
  String ds3fWasBalance(String amount) {
    return 'Was $amount';
  }

  @override
  String get ds3fAsOf => 'As of';

  @override
  String get ds3fNote => 'Note';

  @override
  String get ds3fFee => 'Fees';

  @override
  String get ds3fPrice => 'Price';

  @override
  String get ds3aTitle => 'Assistant';

  @override
  String get ds3aNewChat => 'New chat';

  @override
  String get ds3aSearchHint => 'Search chats';

  @override
  String get ds3aClearSearch => 'Clear search';

  @override
  String get ds3aEmptyTitle => 'Ask about your money';

  @override
  String get ds3aEmptyBody => '“How much did I spend on groceries last month?”';

  @override
  String ds3aNoMatches(String query) {
    return 'No chats match “$query”';
  }

  @override
  String get ds3aNoMatchesBody => 'Try a different word.';

  @override
  String ds3aSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get ds3aSelectAll => 'Select all';

  @override
  String get ds3aDeleteSelected => 'Delete selected';

  @override
  String get ds3aDeleteFailed => 'Couldn\'t delete the chat.';

  @override
  String get ds3aNow => 'now';

  @override
  String ds3aMinutesShort(int minutes) {
    return '${minutes}m';
  }

  @override
  String ds3aHoursShort(int hours) {
    return '${hours}h';
  }

  @override
  String get ds3aBack => 'Chats';

  @override
  String get ds3aMenu => 'Chat actions';

  @override
  String get ds3aRename => 'Rename';

  @override
  String get ds3aRefresh => 'Refresh';

  @override
  String get ds3aComposerHint => 'Ask anything…';

  @override
  String get ds3aSend => 'Send';

  @override
  String get ds3aDisclaimer => 'AI responses are informational only.';

  @override
  String get ds3aThinking => 'Thinking';

  @override
  String get ds3aReplyFailed => 'Couldn\'t get a reply.';

  @override
  String get ds3aRetry => 'Retry';

  @override
  String get ds3aSendFailed => 'Couldn\'t send the message.';

  @override
  String get ds4aServerRow => 'Server';

  @override
  String get ds4aApiKeyLink => 'Sign in with an API key';

  @override
  String get ds4aShowPassword => 'Show password';

  @override
  String get ds4aHidePassword => 'Hide password';

  @override
  String get ds4aDismissError => 'Dismiss';

  @override
  String get ds4aCodeLabel => 'Code';

  @override
  String get ds4aCodeHint => '6-digit code';

  @override
  String get ds4aLockedTitle => 'Sure+ is locked';

  @override
  String get ds4aUnlockFaceId => 'Unlock with Face ID';

  @override
  String get ds4aUnlockTouchId => 'Unlock with Touch ID';

  @override
  String get ds4aIntroTitle => 'Intro experience coming soon';

  @override
  String get ds4aIntroBody =>
      'We\'re building a richer onboarding journey to learn about your goals, milestones, and day-to-day needs. For now, start a conversation with Sure in the Assistant tab and tell it where you are in your financial journey.';

  @override
  String get ds4tLogShare => 'Share logs';

  @override
  String get ds4tLogAutoScroll => 'Auto-scroll';

  @override
  String get ds4tCalendarMonthlyChange => 'Monthly change';

  @override
  String get ds4tCalendarNoAccounts => 'No accounts of this type';

  @override
  String get ds4dExportEmptyTitle => 'No exports yet';

  @override
  String get ds4dExportEmptyBody => 'Create one to get a copy of your data.';

  @override
  String get ds4dFormatsHeader => 'Formats';

  @override
  String get ds4dChoose => 'Choose';

  @override
  String txnParityTransferTo(String account) {
    return 'To $account';
  }

  @override
  String txnParityTransferFrom(String account) {
    return 'From $account';
  }

  @override
  String get txnParityTransferOtherAccount => 'another account';

  @override
  String get txnParityBudgetsTitle => 'Budgets and reports';

  @override
  String get txnParityBudgetsExcluded => 'Excluded';

  @override
  String get txnParityBudgetsOneTime => 'One-time';

  @override
  String get txnParityBudgetsFundsMovement => 'Transfer, not counted';

  @override
  String get txnParityBudgetsCcPayment => 'Card payment, not counted';

  @override
  String get txnParityBudgetsCountedExpense => 'Counted as expense';

  @override
  String get txnParityBudgetsIncluded => 'Included';

  @override
  String get txnParityChangeOnWeb => 'Change on the web';

  @override
  String get txnParityMarkRecurring => 'Mark as recurring';

  @override
  String get txnParityRecurringOffline =>
      'Recurring needs an internet connection.';

  @override
  String get txnParityOpenOnWebSubtitle =>
      'Attachments, transfer matching and more';

  @override
  String get billsSectionOverdue => 'Overdue';

  @override
  String get billsSectionDue => 'Due this month';

  @override
  String billsSectionPaid(int count) {
    return 'Paid this month · $count';
  }

  @override
  String get billsSectionLater => 'Later';

  @override
  String billsSectionPaused(int count) {
    return 'Paused · $count';
  }

  @override
  String get billsShow => 'Show';

  @override
  String get billsHide => 'Hide';

  @override
  String get billsLeftToPay => 'left to pay';

  @override
  String billsPaidOf(String paid, String total, int paidCount, int billCount) {
    String _temp0 = intl.Intl.pluralLogic(
      billCount,
      locale: localeName,
      other: '$billCount bills',
      one: '1 bill',
    );
    return '$paid paid of $total · $paidCount of $_temp0';
  }

  @override
  String billsOtherCurrencies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bills',
      one: '1 bill',
    );
    return 'Also $_temp0 in other currencies';
  }

  @override
  String billsDueOn(String date) {
    return 'Due $date';
  }

  @override
  String billsPaidOn(String date) {
    return 'Paid $date';
  }

  @override
  String get billsAutopay => 'Autopay';

  @override
  String get billsTypeSubscription => 'Subscription';

  @override
  String get billsTypeInstallment => 'Installment';

  @override
  String billsTrialEnds(String date) {
    return 'Trial ends $date';
  }

  @override
  String billsRenews(String date) {
    return 'Renews $date';
  }

  @override
  String get billsPay => 'Pay';

  @override
  String billsPaySemantics(String name) {
    return 'Open the payment page for $name';
  }

  @override
  String get billsEmptyTitle => 'No bills yet';

  @override
  String get billsEmptyBody =>
      'Mark a transaction as recurring, or find bills from your history on the web.';

  @override
  String get billsFindOnWeb => 'Find bills on the web';

  @override
  String get billsLoadFailed => 'Couldn\'t load bills';

  @override
  String get billsRefreshFailed => 'Couldn\'t refresh bills.';

  @override
  String get billsOfflineTitle => 'You\'re offline';

  @override
  String get billsOfflineBody => 'Bills need an internet connection.';

  @override
  String get spdConnectionSyncNow => 'Sync now';

  @override
  String get spdConnectionDisconnect => 'Disconnect';

  @override
  String spdConnectionDisconnectTitle(String name) {
    return 'Disconnect $name?';
  }

  @override
  String get spdConnectionDisconnectBody =>
      'Its accounts stop syncing. You can connect it again on the web.';

  @override
  String get spdConnectionStatusScheduled => 'Scheduled for deletion';

  @override
  String get spdConnectionErrorSyncNotSupported =>
      'This connection updates from your device, not from the server. Manage it on the web.';

  @override
  String get spdConnectionErrorDisconnectNotSupported =>
      'This connection can\'t be disconnected here. Disconnect it on the web.';

  @override
  String get spdConnectionErrorManualSync =>
      'This connection needs a security code to sync. Sync it on the web.';

  @override
  String get spdConnectionErrorNotConnected =>
      'This connection isn\'t authorized. Reconnect it on the web.';

  @override
  String get spdConnectionErrorReconnect =>
      'This connection needs a new login. Log in again on the web.';

  @override
  String get spdConnectionErrorUnlinkFailed =>
      'Some accounts couldn\'t be unlinked, so the connection is still connected. Try again on the web.';

  @override
  String get spdConnectionErrorForbidden =>
      'Only a family admin, or for Plaid the person who connected it, can manage this connection.';

  @override
  String get spdConnectionErrorScope =>
      'This sign-in can only read data. Manage the connection on the web.';

  @override
  String get spdConnectionActionFailed => 'Couldn\'t update the connection.';

  @override
  String get spmReadOnlyAccess =>
      'This sign-in can only view data. Sign in again with full access to make changes.';

  @override
  String get spmCategoryEdit => 'Edit category';

  @override
  String get spmCategoryIconHintEdit => 'Change the icon on the web.';

  @override
  String get spmCategorySaved => 'Category saved';

  @override
  String get spmCategoryDeleted => 'Category deleted';

  @override
  String get spmCategoryDelete => 'Delete category';

  @override
  String spmCategoryDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get spmCategoryDeleteBody =>
      'Its transactions move to the category you pick below, or stay uncategorized. This can\'t be undone.';

  @override
  String spmCategoryDeleteSubcategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Its $count subcategories become top-level categories.',
      one: 'Its subcategory becomes a top-level category.',
    );
    return '$_temp0';
  }

  @override
  String get spmCategoryDeleteMoveTo => 'Move transactions to';

  @override
  String get spmCategoryDeleteUncategorized => 'Leave uncategorized';

  @override
  String get spmMerchantEdit => 'Edit merchant';

  @override
  String get spmMerchantSaved => 'Merchant saved';

  @override
  String get spmMerchantDeleted => 'Merchant deleted';

  @override
  String get spmMerchantDelete => 'Delete merchant';

  @override
  String spmMerchantDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get spmMerchantDeleteBody =>
      'Its transactions keep their details but lose the merchant, and its recurring transactions are removed. This can\'t be undone.';

  @override
  String get spmProfileYou => 'You';

  @override
  String get spmProfileFirstName => 'First name';

  @override
  String get spmProfileLastName => 'Last name';

  @override
  String get spmProfileEmail => 'Email';

  @override
  String get spmProfileChangeOnWeb => 'Change on the web';

  @override
  String get spmProfileChangeOnWebSubtitle => 'Email, password and MFA';

  @override
  String get spmProfileLanguage => 'Language';

  @override
  String get spmProfileLanguageAuto => 'Automatic';

  @override
  String get spmProfileDefaultPeriod => 'Default period';

  @override
  String get spmProfileHousehold => 'Household';

  @override
  String get spmProfileHouseholdName => 'Name';

  @override
  String get spmProfileCurrency => 'Currency';

  @override
  String get spmProfileCountry => 'Country';

  @override
  String get spmProfileTimezone => 'Time zone';

  @override
  String get spmProfileDateFormat => 'Date format';

  @override
  String get spmProfileHouseholdFooter =>
      'Household settings apply to everyone in your household.';

  @override
  String get spmProfileNotSet => 'Not set';

  @override
  String get spmProfileSaved => 'Profile saved';

  @override
  String get spmProfileLoadFailed => 'Couldn\'t load your profile.';

  @override
  String get spmPeriodLastDay => 'Last day';

  @override
  String get spmPeriodCurrentWeek => 'Current week';

  @override
  String get spmPeriodLast7Days => 'Last 7 days';

  @override
  String get spmPeriodCurrentMonth => 'Current month';

  @override
  String get spmPeriodLastMonth => 'Last month';

  @override
  String get spmPeriodLast30Days => 'Last 30 days';

  @override
  String get spmPeriodLast90Days => 'Last 90 days';

  @override
  String get spmPeriodCurrentYear => 'Current year';

  @override
  String get spmPeriodLast365Days => 'Last 365 days';

  @override
  String get spmPeriodLast5Years => 'Last 5 years';

  @override
  String get spmPeriodLast10Years => 'Last 10 years';

  @override
  String get spmPeriodAllTime => 'All time';

  @override
  String spgSectionActive(int count) {
    return 'Active · $count';
  }

  @override
  String spgSectionPaused(int count) {
    return 'Paused · $count';
  }

  @override
  String spgSectionCompleted(int count) {
    return 'Completed · $count';
  }

  @override
  String spgSectionArchived(int count) {
    return 'Archived · $count';
  }

  @override
  String get spgNewGoal => 'New goal';

  @override
  String get spgEditGoal => 'Edit goal';

  @override
  String get spgCreate => 'Create';

  @override
  String get spgEmptyTitle => 'No goals yet';

  @override
  String get spgEmptyBody =>
      'Set a target, link the accounts you save into, and watch your progress add up.';

  @override
  String get spgCreateFirst => 'Create your first goal';

  @override
  String get spgPreviewTitle => 'Goals are a preview feature';

  @override
  String get spgPreviewBody =>
      'Goals need preview features, which are turned off for your account.';

  @override
  String get spgPreviewAction => 'Turn on preview features on the web';

  @override
  String get spgLoadFailed => 'Couldn\'t load your goals';

  @override
  String spgDue(String date) {
    return 'Due $date';
  }

  @override
  String get spgNoDate => 'No date';

  @override
  String get spgReserve => 'Reserve';

  @override
  String get spgPastDue => 'Past due';

  @override
  String spgDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String spgMonthsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months left',
      one: '1 month left',
    );
    return '$_temp0';
  }

  @override
  String spgAmountOf(String current, String target) {
    return '$current of $target';
  }

  @override
  String spgCatchUp(String amount) {
    return 'Save $amount/mo to catch up';
  }

  @override
  String spgPendingPledges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pending pledges',
      one: '1 pending pledge',
    );
    return '$_temp0';
  }

  @override
  String get spgStatusOnTrack => 'On track';

  @override
  String get spgStatusBehind => 'Behind';

  @override
  String get spgStatusReached => 'Reached';

  @override
  String get spgStatusOpen => 'Open';

  @override
  String get spgStatusFunded => 'Reserve intact';

  @override
  String get spgStatusDepleted => 'Needs topping up';

  @override
  String get spgStatusPaused => 'Paused';

  @override
  String get spgStatusCompleted => 'Completed';

  @override
  String get spgStatusArchived => 'Archived';

  @override
  String spgOfTarget(String target) {
    return 'of $target';
  }

  @override
  String spgOfTargetDue(String target, String date) {
    return 'of $target · due $date';
  }

  @override
  String get spgSavedToward => 'I saved toward this';

  @override
  String get spgPledgeRecord => 'Record';

  @override
  String get spgPledgeFrom => 'From';

  @override
  String get spgPledgeHint =>
      'Sure confirms it once the money shows up in that account.';

  @override
  String get spgPendingHeader => 'Pending pledges';

  @override
  String spgPledgeFromAccount(String amount, String account) {
    return '$amount from $account';
  }

  @override
  String spgPledgeAmount(String amount) {
    return '$amount pledged';
  }

  @override
  String get spgPledgeConfirmsTransfer => 'Confirms when it shows up';

  @override
  String get spgPledgeConfirmsManual => 'Confirms on your next balance update';

  @override
  String spgPledgeExpires(String confirm, String date) {
    return '$confirm · expires $date';
  }

  @override
  String get spgPledgeExtend => 'Extend';

  @override
  String get spgPledgeExtended => 'Pledge extended by 7 days';

  @override
  String get spgPledgeCancelTitle => 'Cancel this pledge?';

  @override
  String spgPledgeCancelBody(String amount) {
    return 'The $amount pledge will be removed. You can record a new one anytime.';
  }

  @override
  String get spgPledgeCancelConfirm => 'Cancel pledge';

  @override
  String get spgPledgeKeep => 'Keep';

  @override
  String get spgPledgeCancelled => 'Pledge cancelled';

  @override
  String get spgPledgeSaved => 'Pledge recorded';

  @override
  String get spgFundingHeader => 'Funding accounts';

  @override
  String get spgWholeBalance => 'Whole balance';

  @override
  String get spgPlanHeader => 'Plan';

  @override
  String get spgMonthlyTarget => 'Monthly target';

  @override
  String get spgPace => 'Pace';

  @override
  String spgPerMonth(String amount) {
    return '$amount/mo';
  }

  @override
  String get spgProjected => 'Projected completion';

  @override
  String get spgTimeLeft => 'Time left';

  @override
  String get spgNotes => 'Notes';

  @override
  String get spgEdit => 'Edit';

  @override
  String get spgLifecycleOnWeb => 'Pause or archive on the web';

  @override
  String get spgDelete => 'Delete goal';

  @override
  String get spgDeleteTitle => 'Delete goal?';

  @override
  String spgDeleteBody(String name) {
    return 'Delete \"$name\"? Its pledges are removed too. This can\'t be undone.';
  }

  @override
  String get spgDeleted => 'Goal deleted';

  @override
  String get spgSaved => 'Goal saved';

  @override
  String get spgCreated => 'Goal created';

  @override
  String get spgIconAndColor => 'Icon and color';

  @override
  String get spgIcon => 'Icon';

  @override
  String get spgKindOneOff => 'One-off goal';

  @override
  String get spgKindOneOffHint =>
      'Save toward something, then close it when you spend it.';

  @override
  String get spgKindReserve => 'Reserve';

  @override
  String get spgKindReserveHint =>
      'A balance to keep, like an emergency fund. It has no due date.';

  @override
  String get spgName => 'Name';

  @override
  String get spgNameHint => 'Emergency fund';

  @override
  String get spgNameRequired => 'Enter a name';

  @override
  String get spgTarget => 'Target';

  @override
  String get spgTargetInvalid => 'Enter an amount above zero';

  @override
  String get spgBy => 'By';

  @override
  String get spgFundFrom => 'Fund from';

  @override
  String get spgFundFromHint =>
      'Leave an amount blank to use the account\'s whole balance.';

  @override
  String get spgNoFundable =>
      'Add a cash, investment or crypto account to fund a goal.';

  @override
  String get spgAccountsRequired =>
      'Pick at least one account to fund this goal.';

  @override
  String get spbEditTotals => 'Edit totals';

  @override
  String get spbTotalBudget => 'Total budget';

  @override
  String get spbExpectedIncome => 'Expected income';

  @override
  String spbSpentThisMonth(String amount) {
    return 'Spent $amount this month';
  }

  @override
  String spbSpentInPeriod(String amount) {
    return 'Spent $amount';
  }

  @override
  String get spbRollover => 'Roll over unused amount';

  @override
  String get spbTransactions => 'Transactions';

  @override
  String get spbSharedReadOnly => 'This budget is shared with you read-only.';

  @override
  String get spbInvalidAmount => 'Enter an amount of 0 or more.';

  @override
  String get spbSaveFailed => 'Couldn\'t save the budget.';

  @override
  String get spbSaved => 'Budget saved';

  @override
  String get sprRulesReorderOnWeb => 'Reorder rules on the web';

  @override
  String get sprRulesEmptyBody =>
      'Rules categorize, tag and rename transactions automatically. Tap + to create one.';

  @override
  String get sprRuleNew => 'New rule';

  @override
  String get sprRuleEdit => 'Edit rule';

  @override
  String get sprRuleName => 'Name';

  @override
  String get sprRuleNameHint => 'Optional';

  @override
  String get sprRuleIfHeader => 'If a transaction';

  @override
  String get sprRuleThenHeader => 'Then';

  @override
  String get sprRuleAddCondition => 'Add condition';

  @override
  String get sprRuleAddGroup => 'Add condition group';

  @override
  String get sprRuleAddAction => 'Add action';

  @override
  String get sprRuleNoConditions =>
      'No conditions: the rule applies to every transaction.';

  @override
  String get sprRuleRemove => 'Remove';

  @override
  String get sprRulePickField => 'Field';

  @override
  String get sprRulePickOperator => 'Comparison';

  @override
  String get sprRulePickValue => 'Value';

  @override
  String get sprRulePickAction => 'Action';

  @override
  String get sprRulePickGroup => 'Match';

  @override
  String get sprRuleChooseValue => 'Choose…';

  @override
  String get sprRuleEnterValue => 'Enter a value';

  @override
  String sprRuleTagsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
    );
    return '$_temp0';
  }

  @override
  String get sprOpLike => 'contains';

  @override
  String get sprOpNotLike => 'doesn\'t contain';

  @override
  String get sprOpStartsWith => 'starts with';

  @override
  String get sprOpEndsWith => 'ends with';

  @override
  String get sprOpRegex => 'matches the pattern';

  @override
  String get sprOpEquals => 'is';

  @override
  String get sprOpNotEquals => 'is not';

  @override
  String get sprOpEmpty => 'is empty';

  @override
  String get sprOpNotEmpty => 'is not empty';

  @override
  String get sprOpGreater => 'is more than';

  @override
  String get sprOpAtLeast => 'is at least';

  @override
  String get sprOpLess => 'is less than';

  @override
  String get sprOpAtMost => 'is at most';

  @override
  String get sprActSetCategory => 'Set category';

  @override
  String get sprActAddTags => 'Add tags';

  @override
  String get sprActSetMerchant => 'Set merchant';

  @override
  String get sprActRename => 'Rename to';

  @override
  String get sprActActivity => 'Set investment activity';

  @override
  String get sprActTransfer => 'Mark as transfer or payment to';

  @override
  String get sprRuleSplitOnWeb => 'Edit the split on the web';

  @override
  String get sprRuleNeedsAction => 'Add at least one action.';

  @override
  String get sprRuleMissingValue => 'Fill in every value, or remove the row.';

  @override
  String get sprRuleEmptyGroup =>
      'Add a condition to each group, or remove the group.';

  @override
  String get sprRuleAmountInvalid => 'Enter a number.';

  @override
  String get sprRuleSaved => 'Rule saved';

  @override
  String get sprRuleDeleted => 'Rule deleted';

  @override
  String get sprRuleApply => 'Apply to past transactions';

  @override
  String get sprRuleApplying => 'Applying… this can take a few seconds.';

  @override
  String get sprRuleApplyTitle => 'Apply this rule?';

  @override
  String sprRuleApplyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'It will change $count transactions.',
      one: 'It will change 1 transaction.',
    );
    return '$_temp0';
  }

  @override
  String sprRuleApplyAbove(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active rules run before it.',
      one: '1 active rule runs before it.',
    );
    return '$_temp0';
  }

  @override
  String sprRuleApplyAiCost(String cost) {
    return 'Uses AI categorization · about $cost';
  }

  @override
  String get sprRuleApplyAiNoCost => 'Uses AI categorization · cost unknown';

  @override
  String get sprRuleApplyConfirm => 'Apply';

  @override
  String sprRuleApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Changed $count transactions',
      one: 'Changed 1 transaction',
    );
    return '$_temp0';
  }

  @override
  String get sprRuleApplyRunning =>
      'Another rule is running. Try again in a moment.';

  @override
  String get sprRuleEditLink => 'Edit';

  @override
  String get sprRuleDuplicate => 'Duplicate';

  @override
  String get sprRuleDelete => 'Delete';

  @override
  String get sprRuleDeleteTitle => 'Delete this rule?';

  @override
  String get sprRuleDeleteBody =>
      'Transactions it already changed stay as they are.';

  @override
  String sprRuleCopyName(String name) {
    return '$name (copy)';
  }

  @override
  String get spaAddAccount => 'Add account';

  @override
  String get spaEditAccount => 'Edit account';

  @override
  String get spaConnectBank => 'Connect a bank';

  @override
  String get spaConnectBankSub => 'Link accounts on the web';

  @override
  String get spaOrByHand => 'Or add one by hand';

  @override
  String get spaTypeDepository => 'Cash or bank';

  @override
  String get spaTypeInvestment => 'Investment';

  @override
  String get spaTypeCrypto => 'Crypto';

  @override
  String get spaTypeProperty => 'Property';

  @override
  String get spaTypeVehicle => 'Vehicle';

  @override
  String get spaTypeCreditCard => 'Credit card';

  @override
  String get spaTypeLoan => 'Loan';

  @override
  String get spaTypeOtherAsset => 'Other asset';

  @override
  String get spaTypeOtherLiability => 'Other liability';

  @override
  String get spaBackToType => '‹ Type';

  @override
  String get spaAdd => 'Add';

  @override
  String get spaCurrentBalance => 'Current balance';

  @override
  String get spaCurrentValue => 'Current value';

  @override
  String get spaAmountOwed => 'Amount owed';

  @override
  String get spaSyncedFromBank => 'Synced from your bank';

  @override
  String get spaName => 'Name';

  @override
  String get spaNameHint => 'Required';

  @override
  String get spaNameRequired => 'Enter a name';

  @override
  String get spaBalanceRequired => 'Enter an amount';

  @override
  String get spaInvalidNumber => 'Enter a number';

  @override
  String get spaInvalidWholeNumber => 'Enter a whole number';

  @override
  String get spaCurrency => 'Currency';

  @override
  String get spaSubtype => 'Subtype';

  @override
  String get spaPropertyType => 'Property type';

  @override
  String get spaPropertyTypeRequired => 'Choose a property type';

  @override
  String get spaNone => 'None';

  @override
  String get spaOptional => 'Optional';

  @override
  String get spaUnchanged => 'Unchanged';

  @override
  String get spaAvailableCredit => 'Available credit';

  @override
  String get spaApr => 'APR';

  @override
  String get spaMinimumPayment => 'Minimum payment';

  @override
  String get spaAnnualFee => 'Annual fee';

  @override
  String get spaExpirationDate => 'Expiration date';

  @override
  String get spaStatementCloseDay => 'Statement closes';

  @override
  String get spaDueDay => 'Payment due';

  @override
  String spaDayOfMonth(int day) {
    return 'Day $day';
  }

  @override
  String get spaInterestRate => 'Interest rate';

  @override
  String get spaRateType => 'Rate type';

  @override
  String get spaRateFixed => 'Fixed';

  @override
  String get spaRateVariable => 'Variable';

  @override
  String get spaRateAdjustable => 'Adjustable';

  @override
  String get spaTerm => 'Term';

  @override
  String get spaMonthsSuffix => 'months';

  @override
  String get spaStartDate => 'Start date';

  @override
  String get spaOriginalAmount => 'Original amount';

  @override
  String get spaDownPayment => 'Down payment';

  @override
  String get spaMake => 'Make';

  @override
  String get spaModel => 'Model';

  @override
  String get spaYear => 'Year';

  @override
  String get spaMileage => 'Mileage';

  @override
  String get spaMileageUnit => 'Mileage unit';

  @override
  String get spaMiles => 'Miles';

  @override
  String get spaKilometers => 'Kilometers';

  @override
  String get spaPurchasePrice => 'Purchase price';

  @override
  String get spaPurchaseDate => 'Purchase date';

  @override
  String get spaYearBuilt => 'Year built';

  @override
  String get spaArea => 'Area';

  @override
  String get spaAreaUnit => 'Area unit';

  @override
  String get spaSquareFeet => 'Square feet';

  @override
  String get spaSquareMeters => 'Square meters';

  @override
  String get spaAddress => 'Address';

  @override
  String get spaStreet => 'Street';

  @override
  String get spaStreet2 => 'Apt, suite';

  @override
  String get spaCity => 'City';

  @override
  String get spaRegion => 'State or region';

  @override
  String get spaPostalCode => 'Postal code';

  @override
  String get spaCountry => 'Country';

  @override
  String get spaTaxTreatment => 'Tax treatment';

  @override
  String get spaTaxable => 'Taxable';

  @override
  String get spaTaxDeferred => 'Tax-deferred';

  @override
  String get spaTaxExempt => 'Tax-exempt';

  @override
  String get spaMore => 'More';

  @override
  String get spaInstitution => 'Institution';

  @override
  String get spaNotes => 'Notes';

  @override
  String get spaOpeningDate => 'Opening balance date';

  @override
  String get spaExcludeFromReports => 'Exclude from reports';

  @override
  String get spaSubCash => 'Cash';

  @override
  String get spaSubChecking => 'Checking';

  @override
  String get spaSubSavings => 'Savings';

  @override
  String get spaSubHsa => 'Health Savings Account';

  @override
  String get spaSubCd => 'Certificate of Deposit';

  @override
  String get spaSubMoneyMarket => 'Money Market';

  @override
  String get spaSubMortgage => 'Mortgage';

  @override
  String get spaSubStudentLoan => 'Student Loan';

  @override
  String get spaSubAutoLoan => 'Auto Loan';

  @override
  String get spaSubHomeEquity => 'Home Equity Loan';

  @override
  String get spaSubLineOfCredit => 'Line of Credit';

  @override
  String get spaSubBusinessLoan => 'Business Loan';

  @override
  String get spaSubOtherLoan => 'Other Loan';

  @override
  String get spaSubWallet => 'Crypto Wallet';

  @override
  String get spaSubExchange => 'Crypto Exchange';

  @override
  String get spaSubSingleFamily => 'Single Family Home';

  @override
  String get spaSubMultiFamily => 'Multi-Family Home';

  @override
  String get spaSubCondo => 'Condominium';

  @override
  String get spaSubTownhouse => 'Townhouse';

  @override
  String get spaSubInvestmentProperty => 'Investment Property';

  @override
  String get spaSubSecondHome => 'Second Home';

  @override
  String get spaSubApartment => 'Apartment';

  @override
  String get spaSubPlot => 'Plot / Land';

  @override
  String get spaSubCommercial => 'Commercial Property';

  @override
  String get spaSubAgriLand => 'Agricultural Land';

  @override
  String get spaCreated => 'Account added';

  @override
  String get spaSaved => 'Account saved';

  @override
  String get spaSaveFailed => 'Couldn\'t save the account';

  @override
  String get spaDeleteAccount => 'Delete account';

  @override
  String spaDeleteConfirmTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get spaDeleteConfirmBody =>
      'Its transactions and history are removed. This can\'t be undone.';

  @override
  String get spaDeleted => 'Account deleted';

  @override
  String get spaReadOnlyAccess =>
      'This sign-in can only view data. Sign in again with full access to change accounts.';

  @override
  String get spaInvestEmptyBody =>
      'Add an investment or crypto account, or connect a brokerage.';
}
