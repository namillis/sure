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
  String get commonRefresh => 'Refresh';

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
  String get navMore => 'More';

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
  String get dashboardNoAccountsSubtitle =>
      'Add accounts in the web app to see them here.';

  @override
  String get dashboardFilterEmpty => 'No accounts match the current filter';

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
  String get transactionFormAmountRequired => 'Amount is required';

  @override
  String get transactionFormAmountInvalid => 'Please enter a valid amount';

  @override
  String get transactionFormDateLabel => 'Date';

  @override
  String get transactionFormNameLabel => 'Name';

  @override
  String get transactionFormCategoryLabel => 'Category';

  @override
  String get transactionEditTitle => 'Edit Transaction';

  @override
  String get transactionEditNameLabel => 'Name';

  @override
  String get transactionEditNameRequired => 'Name is required';

  @override
  String get transactionEditNotesLabel => 'Notes';

  @override
  String get transactionEditCategoryLabel => 'Category';

  @override
  String get transactionEditMerchantLabel => 'Merchant';

  @override
  String get transactionEditTagsLabel => 'Tags';

  @override
  String get transactionEditSaving => 'Saving…';

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
  String get transactionsListEmpty => 'No transactions';

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
  String get settingsSectionConnection => 'Connection';

  @override
  String get settingsSectionDataManagement => 'Data Management';

  @override
  String get settingsSectionSecurity => 'Security';

  @override
  String get settingsSectionDangerZone => 'Danger Zone';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsProxyHeadersLabel => 'Custom Proxy Headers';

  @override
  String get settingsPrivacyHideAmountsLabel => 'Hide amounts';

  @override
  String get settingsPrivacyHideAmountsContent =>
      'Mask money values across the app';

  @override
  String get settingsBiometricLabel => 'Biometric Lock';

  @override
  String get settingsBiometricEnable => 'Enable biometric lock?';

  @override
  String get settingsBiometricEnableContent =>
      'Require biometric authentication when resuming the app.';

  @override
  String get settingsCheckForUpdates => 'Check for Updates';

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
  String get settingsClearDataSuccess => 'Local data cleared';

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
  String get settingsDebugLogs => 'Debug Logs';

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
  String get connectivityOffline => 'You are offline';

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
  String get accountDetailRefreshTooltip => 'Refresh account details';

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
  String settingsAppVersion(String version) {
    return 'App Version: $version';
  }

  @override
  String get settingsCheckForUpdatesSubtitle =>
      'See if a newer version is available';

  @override
  String get settingsContactUs => 'Contact us';

  @override
  String get settingsDebugLogsSemantics => 'Open debug logs';

  @override
  String get settingsDebugLogsSubtitle => 'View app diagnostic logs';

  @override
  String get settingsGroupByAccountType => 'Group by Account Type';

  @override
  String get settingsGroupByAccountTypeSubtitle =>
      'Group accounts by type (Crypto, Bank, etc.)';

  @override
  String get settingsProxyHeadersTileTitle => 'Custom proxy headers';

  @override
  String get settingsProxyHeadersTileSubtitleEmpty =>
      'Optional headers for a reverse proxy or auth gateway';

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
  String get transactionEditNoTags => 'No tags available';

  @override
  String get transactionEditUnknownTag => 'Unknown tag';

  @override
  String get transactionEditSyncedOnly =>
      'Only synced transactions can be edited from mobile.';

  @override
  String get transactionEditCategoryHelper => 'Choose a replacement category';

  @override
  String get transactionEditMerchantHelper => 'Choose a replacement merchant';

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
  String get transactionsListEditTooltip => 'Edit transaction';

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
  String get moreBudgets => 'Budgets';

  @override
  String get moreBudgetsSubtitle => 'Budgeted vs. actual spending by category';

  @override
  String get budgetsTitle => 'Budgets';

  @override
  String get budgetsPreviousMonth => 'Previous month';

  @override
  String get budgetsNextMonth => 'Next month';

  @override
  String get budgetsBudgeted => 'Budgeted';

  @override
  String get budgetsActual => 'Actual';

  @override
  String get budgetsRemaining => 'Remaining';

  @override
  String get budgetsIncome => 'Income';

  @override
  String budgetsExpectedIncome(String amount) {
    return 'Expected $amount';
  }

  @override
  String budgetsOfAmount(String amount) {
    return 'of $amount';
  }

  @override
  String budgetsAmountLeft(String amount) {
    return '$amount left';
  }

  @override
  String budgetsOverBy(String amount) {
    return '$amount over';
  }

  @override
  String budgetsRolledOver(String amount) {
    return '+$amount rolled over';
  }

  @override
  String get budgetsSharedBudget => 'Shared budget';

  @override
  String get budgetsNoLimit => 'No budget';

  @override
  String get budgetsCategoriesTitle => 'Categories';

  @override
  String budgetsFilterOverBudget(int count) {
    return 'Over budget ($count)';
  }

  @override
  String get budgetsOverBudget => 'Over budget';

  @override
  String get budgetsNearLimit => 'Near limit';

  @override
  String budgetsBudgetNumber(int number) {
    return 'Budget $number';
  }

  @override
  String budgetsNoBudgetTitle(String month) {
    return 'No budget for $month';
  }

  @override
  String get budgetsNoBudgetMessage =>
      'Budgets are created in Sure on the web. Open Budgets there to set one up for this month.';

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
  String get moreCashFlow => 'Cash Flow';

  @override
  String get moreCashFlowSubtitle => 'Income, spending and savings by category';

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
  String accountChartChangeLabel(String change, String percent) {
    return '$change ($percent) this period';
  }

  @override
  String accountChartChangeOnlyLabel(String change) {
    return '$change this period';
  }

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
  String holdingSharesAtPrice(String quantity, String price) {
    return '$quantity shares · $price';
  }

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
  String get portfolioTitle => 'Investments';

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
  String get portfolioRecentActivity => 'Recent activity';

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
  String get shellSectionYou => 'You';

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
  String get shellSecurity => 'Security';

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
  String get shellInvestEmptyTitle => 'No investment accounts';

  @override
  String get shellInvestEmptyBody =>
      'Investment and crypto accounts you add show up here.';

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
  String activityDateRange(String start, String end) {
    return '$start – $end';
  }

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
  String get activityFilterApply => 'Apply';

  @override
  String get activityFilterSearchHint => 'Find';

  @override
  String get activityFilterNoOptions => 'Nothing to choose from yet';

  @override
  String get activityToday => 'Today';

  @override
  String get activityYesterday => 'Yesterday';

  @override
  String get activityUnknownDate => 'No date';

  @override
  String get activityEmpty => 'No transactions this month';

  @override
  String get activityEmptyFiltered => 'No transactions match.';

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
  String get activitySplit => 'Split';

  @override
  String get activityTransfer => 'Transfer';

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
  String get recurringMonthlyOut => 'Monthly out';

  @override
  String get recurringMonthlyIn => 'Monthly in';

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
  String recurringMonthlyOnDay(int day) {
    return 'Monthly on day $day';
  }

  @override
  String recurringNextDate(String date) {
    return 'Next $date';
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
  String get recurringActionEdit => 'Edit';

  @override
  String get recurringActionPause => 'Pause';

  @override
  String get recurringActionActivate => 'Activate';

  @override
  String recurringMoreActions(String name) {
    return 'More actions for $name';
  }

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
  String get insightsShowDetails => 'Show details';

  @override
  String get insightsHideDetails => 'Hide details';

  @override
  String get insightsDismissFailed => 'Couldn\'t dismiss the insight';

  @override
  String get spendingVsNormalTitle => 'Spending vs normal';

  @override
  String spendingVsNormalSoFar(String amount) {
    return '$amount so far';
  }

  @override
  String spendingVsNormalNormal(String amount) {
    return 'Normal $amount';
  }

  @override
  String spendingVsNormalAbove(String percent) {
    return '$percent above normal';
  }

  @override
  String spendingVsNormalBelow(String percent) {
    return '$percent below normal';
  }

  @override
  String get spendingVsNormalNew => 'New';

  @override
  String get spendingVsNormalShowAll => 'Show all categories';

  @override
  String get spendingVsNormalShowLess => 'Show less';

  @override
  String spendingVsNormalCategoryNormal(String amount, String normal) {
    return '$amount · normal $normal';
  }

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
  String txnDetailTagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
    );
    return '$_temp0';
  }

  @override
  String get txnDetailRemoveTag => 'Remove tag';

  @override
  String get txnDetailChooseCategory => 'Choose category';

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
  String get txnDetailSplitHeading => 'Split';

  @override
  String get txnDetailEditSplit => 'Edit split';

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
  String get txnDetailNoTags => 'No tags';

  @override
  String get dataIn => 'Import data';

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
}
