import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_sv.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('sv')
  ];

  /// Application title shown in the OS task switcher.
  ///
  /// In en, this message translates to:
  /// **'Sure Finances'**
  String get appTitle;

  /// Generic cancel action label.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic save/confirm action label.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Generic retry action label.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get commonTryAgain;

  /// Generic delete action label.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Label for the 'All' filter chip (currency filter, category filter, etc.).
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// Generic refresh action label.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// Generic close/dismiss action label.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic undo action label.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// Suggested chat prompt on the empty assistant screen.
  ///
  /// In en, this message translates to:
  /// **'What is my current net worth?'**
  String get chatSuggestionNetWorth;

  /// Suggested chat prompt on the empty assistant screen.
  ///
  /// In en, this message translates to:
  /// **'How has my spending changed this month?'**
  String get chatSuggestionSpending;

  /// Suggested chat prompt on the empty assistant screen.
  ///
  /// In en, this message translates to:
  /// **'How can I improve my savings rate?'**
  String get chatSuggestionSavings;

  /// Suggested chat prompt on the empty assistant screen.
  ///
  /// In en, this message translates to:
  /// **'What are my biggest expenses lately?'**
  String get chatSuggestionExpenses;

  /// Label for the email text field on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginEmailLabel;

  /// Validation error when email field is empty.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get loginEmailRequired;

  /// Validation error when email format is invalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get loginEmailInvalid;

  /// Label for the password field on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPasswordLabel;

  /// Validation error when password field is empty.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get loginPasswordRequired;

  /// Primary sign-in button label.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginSignIn;

  /// Google SSO button label.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get loginSignInWithGoogle;

  /// Label for the MFA code input field.
  ///
  /// In en, this message translates to:
  /// **'Authentication Code'**
  String get loginMfaLabel;

  /// Label for the API key input field.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get loginApiKeyLabel;

  /// Bottom navigation label for the Home (dashboard) tab.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Bottom navigation label for the Intro tab.
  ///
  /// In en, this message translates to:
  /// **'Intro'**
  String get navIntro;

  /// Bottom navigation label for the AI assistant tab.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get navAssistant;

  /// Bottom navigation label for the More tab.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// Snackbar message when a sync attempt fails.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get dashboardSyncError;

  /// Snackbar message when a sync attempt fails with retry instruction.
  ///
  /// In en, this message translates to:
  /// **'Sync failed. Please try again.'**
  String get dashboardSyncFailed;

  /// Snackbar message while accounts are being refreshed after a transaction.
  ///
  /// In en, this message translates to:
  /// **'Refreshing accounts…'**
  String get dashboardRefreshing;

  /// Snackbar message shown after accounts refresh completes.
  ///
  /// In en, this message translates to:
  /// **'Accounts updated'**
  String get dashboardAccountsUpdated;

  /// Snackbar message while sync is in progress.
  ///
  /// In en, this message translates to:
  /// **'Syncing data from server…'**
  String get dashboardSyncing;

  /// Label shown in the sync status indicator after a successful sync.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get dashboardSynced;

  /// Error state message when accounts fail to load.
  ///
  /// In en, this message translates to:
  /// **'Failed to load accounts'**
  String get dashboardErrorLoadingAccounts;

  /// Empty state message when no accounts exist.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get dashboardNoAccounts;

  /// Empty state subtitle when no accounts exist.
  ///
  /// In en, this message translates to:
  /// **'Add accounts in the web app to see them here.'**
  String get dashboardNoAccountsSubtitle;

  /// Empty state when the active account filter returns no results.
  ///
  /// In en, this message translates to:
  /// **'No accounts match the current filter'**
  String get dashboardFilterEmpty;

  /// Title for the chat list screen / app bar.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatListTitle;

  /// FAB tooltip for creating a new chat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatListNewChat;

  /// Empty-state heading on the chat list screen.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get chatListEmpty;

  /// Empty-state subtitle on the chat list screen.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation with your AI assistant'**
  String get chatListEmptySubtitle;

  /// Title for the delete-chat confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get chatListDeleteTitle;

  /// Placeholder title for a new conversation before it is saved.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get chatConversationNewTitle;

  /// Hint text inside the chat message input field.
  ///
  /// In en, this message translates to:
  /// **'Ask anything about your finances…'**
  String get chatConversationMessageHint;

  /// Greeting shown in a new conversation when the user's first name is known.
  ///
  /// In en, this message translates to:
  /// **'Hi {firstName}, how can I help?'**
  String chatConversationGreetingWithName(String firstName);

  /// Greeting shown in a new conversation when the user's first name is not available.
  ///
  /// In en, this message translates to:
  /// **'Hi there, how can I help?'**
  String get chatConversationGreetingNoName;

  /// App bar title for the new-transaction form.
  ///
  /// In en, this message translates to:
  /// **'New Transaction'**
  String get transactionFormNewTitle;

  /// Label for the transaction type segmented control.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get transactionFormTypeLabel;

  /// Segment label for an expense transaction.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get transactionFormTypeExpense;

  /// Segment label for an income transaction.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get transactionFormTypeIncome;

  /// Label for the amount input field.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get transactionFormAmountLabel;

  /// Validation error when amount is empty.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get transactionFormAmountRequired;

  /// Validation error when amount is not a number.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get transactionFormAmountInvalid;

  /// Label for the date picker field.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get transactionFormDateLabel;

  /// Label for the transaction name/payee field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get transactionFormNameLabel;

  /// Label for the category picker field.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get transactionFormCategoryLabel;

  /// App bar title for the edit-transaction screen.
  ///
  /// In en, this message translates to:
  /// **'Edit Transaction'**
  String get transactionEditTitle;

  /// Label for the name field in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get transactionEditNameLabel;

  /// Validation error when name is empty in edit form.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get transactionEditNameRequired;

  /// Label for the notes field in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get transactionEditNotesLabel;

  /// Label for the category field in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get transactionEditCategoryLabel;

  /// Label for the merchant field in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Merchant'**
  String get transactionEditMerchantLabel;

  /// Label for the tags field in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get transactionEditTagsLabel;

  /// In-progress label shown on the save button while saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get transactionEditSaving;

  /// Title for the single-transaction delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Transaction'**
  String get transactionsListDeleteTitle;

  /// Body of the delete confirmation dialog for a named transaction.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String transactionsListDeleteSingleContent(String name);

  /// Title for the multi-transaction delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Transactions'**
  String get transactionsListDeleteMultiTitle;

  /// Body of the multi-transaction delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the selected transactions?'**
  String get transactionsListDeleteMultiContent;

  /// Empty-state message when no transactions exist.
  ///
  /// In en, this message translates to:
  /// **'No transactions'**
  String get transactionsListEmpty;

  /// Snackbar message when the API returns an auth failure.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed: Please log in again'**
  String get transactionsListAuthFailed;

  /// Empty-state heading when an account has no transactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get transactionsListNoTransactionsYet;

  /// Empty-state subtitle prompting the user to add their first transaction.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add your first transaction'**
  String get transactionsListEmptyAddFirst;

  /// Empty state shown when category filter returns no transactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions match this category'**
  String get transactionsListNoCategoryMatch;

  /// Button label on the transactions error state.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get transactionsListRetry;

  /// Snackbar after a single transaction is deleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get transactionsListDeletedSuccess;

  /// Snackbar when deleting a single transaction fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete transaction'**
  String get transactionsListSingleDeleteFailed;

  /// Snackbar message after multiple transactions are deleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Deleted {count} transaction} other{Deleted {count} transactions}}'**
  String transactionsListDeletedMulti(int count);

  /// Snackbar when multi-delete fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete transactions'**
  String get transactionsListDeleteFailed;

  /// Snackbar when delete fails due to missing token.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: No access token'**
  String get transactionsListDeleteNoToken;

  /// Title for the undo-transaction dialog.
  ///
  /// In en, this message translates to:
  /// **'Undo Transaction'**
  String get transactionsListUndoTitle;

  /// Confirmation question for removing a pending transaction.
  ///
  /// In en, this message translates to:
  /// **'Remove this pending transaction?'**
  String get transactionsListUndoRemovePending;

  /// Confirmation question for restoring a transaction.
  ///
  /// In en, this message translates to:
  /// **'Restore this transaction?'**
  String get transactionsListUndoRestoreConfirm;

  /// Snackbar after a pending transaction is removed.
  ///
  /// In en, this message translates to:
  /// **'Pending transaction removed'**
  String get transactionsListUndoPendingRemoved;

  /// Snackbar after a transaction is restored.
  ///
  /// In en, this message translates to:
  /// **'Transaction restored'**
  String get transactionsListUndoRestored;

  /// Snackbar when undoing a transaction fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to undo transaction'**
  String get transactionsListUndoFailed;

  /// Settings section header for display/appearance options.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsSectionDisplay;

  /// Settings section header for server/connection options.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsSectionConnection;

  /// Settings section header for data import/export options.
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get settingsSectionDataManagement;

  /// Settings section header for security options.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSectionSecurity;

  /// Settings section header for destructive actions.
  ///
  /// In en, this message translates to:
  /// **'Danger Zone'**
  String get settingsSectionDangerZone;

  /// Label for the theme picker setting.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeLabel;

  /// Theme option: follow system setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Theme option: light mode.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme option: dark mode.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Label for the custom proxy headers setting.
  ///
  /// In en, this message translates to:
  /// **'Custom Proxy Headers'**
  String get settingsProxyHeadersLabel;

  /// Label for the toggle that masks monetary amounts across the app.
  ///
  /// In en, this message translates to:
  /// **'Hide amounts'**
  String get settingsPrivacyHideAmountsLabel;

  /// Subtitle describing the hide-amounts toggle.
  ///
  /// In en, this message translates to:
  /// **'Mask money values across the app'**
  String get settingsPrivacyHideAmountsContent;

  /// Label for the biometric lock toggle.
  ///
  /// In en, this message translates to:
  /// **'Biometric Lock'**
  String get settingsBiometricLabel;

  /// Title of the dialog to enable biometric lock.
  ///
  /// In en, this message translates to:
  /// **'Enable biometric lock?'**
  String get settingsBiometricEnable;

  /// Body text of the enable-biometric dialog.
  ///
  /// In en, this message translates to:
  /// **'Require biometric authentication when resuming the app.'**
  String get settingsBiometricEnableContent;

  /// Label for the check-for-updates action.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get settingsCheckForUpdates;

  /// Title for the update-available dialog.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get settingsUpdateAvailableTitle;

  /// Body text for the update-available dialog.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available. Update now?'**
  String settingsUpdateAvailableContent(String version);

  /// Fallback used in the update-available dialog when the store version number is unknown (e.g. 'Version a newer version is available').
  ///
  /// In en, this message translates to:
  /// **'a newer version'**
  String get settingsUpdateNewerVersionFallback;

  /// Confirm button in the update-available dialog.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get settingsUpdateNow;

  /// Snackbar when no update is available.
  ///
  /// In en, this message translates to:
  /// **'You\'re on the latest version.'**
  String get settingsNoUpdateAvailable;

  /// Snackbar when the update check fails.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates.'**
  String get settingsUpdateError;

  /// Title for the clear-all-data confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear All Data'**
  String get settingsClearDataTitle;

  /// Body text for the clear-all-data dialog.
  ///
  /// In en, this message translates to:
  /// **'This will remove all locally cached data. Your data on the server will not be affected.'**
  String get settingsClearDataContent;

  /// Confirm button in the clear-data dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear Data'**
  String get settingsClearData;

  /// Snackbar after local data is cleared.
  ///
  /// In en, this message translates to:
  /// **'Local data cleared'**
  String get settingsClearDataSuccess;

  /// Title for the delete-account confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsDeleteAccountTitle;

  /// Confirm button in the delete-account dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get settingsDeleteAccount;

  /// Title for the sign-out confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get settingsSignOutTitle;

  /// Body text for the sign-out dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get settingsSignOutContent;

  /// Confirm button in the sign-out dialog and settings list tile label.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get settingsSignOut;

  /// Label for the debug logs navigation tile.
  ///
  /// In en, this message translates to:
  /// **'Debug Logs'**
  String get settingsDebugLogs;

  /// App bar title for the SSO onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Link Your Account'**
  String get ssoOnboardingTitle;

  /// Tab label for linking an existing Sure account via SSO.
  ///
  /// In en, this message translates to:
  /// **'Link existing'**
  String get ssoOnboardingTabLink;

  /// Tab label for creating a new Sure account via SSO.
  ///
  /// In en, this message translates to:
  /// **'Create new'**
  String get ssoOnboardingTabCreate;

  /// Label for the first-name field on the SSO onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get ssoOnboardingFirstNameLabel;

  /// Label for the last-name field on the SSO onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get ssoOnboardingLastNameLabel;

  /// Button label to link an existing account.
  ///
  /// In en, this message translates to:
  /// **'Link Account'**
  String get ssoOnboardingLinkButton;

  /// Button label to create a new account.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get ssoOnboardingCreateButton;

  /// Tab and submit button label when the user has a pending household invitation to accept.
  ///
  /// In en, this message translates to:
  /// **'Accept Invitation'**
  String get ssoOnboardingAcceptInvitation;

  /// App bar title for the account calendar screen.
  ///
  /// In en, this message translates to:
  /// **'Account Calendar'**
  String get calendarTitle;

  /// Section header for the account-type selector on the calendar screen.
  ///
  /// In en, this message translates to:
  /// **'Account Type'**
  String get calendarAccountTypeSection;

  /// Segment label for asset-type accounts on the calendar.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get calendarSegmentAssets;

  /// Segment label for liability-type accounts on the calendar.
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get calendarSegmentLiabilities;

  /// Placeholder shown in the account dropdown when none is selected.
  ///
  /// In en, this message translates to:
  /// **'Select Account'**
  String get calendarSelectAccount;

  /// Label for the monthly-change metric on the calendar screen.
  ///
  /// In en, this message translates to:
  /// **'Monthly Change'**
  String get calendarMonthlyChange;

  /// Empty-state message when no transactions exist for the selected day.
  ///
  /// In en, this message translates to:
  /// **'No transactions on this day'**
  String get calendarNoTransactions;

  /// Menu item title for Account Calendar in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Account Calendar'**
  String get moreCalendar;

  /// Subtitle for the Account Calendar menu item in the More screen.
  ///
  /// In en, this message translates to:
  /// **'View monthly balance changes by account'**
  String get moreCalendarSubtitle;

  /// Menu item title for Recent Transactions in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get moreRecentTransactions;

  /// Subtitle for the Recent Transactions menu item.
  ///
  /// In en, this message translates to:
  /// **'View recent transactions across all accounts'**
  String get moreRecentTransactionsSubtitle;

  /// Heading shown on the biometric lock screen.
  ///
  /// In en, this message translates to:
  /// **'App Locked'**
  String get biometricTitle;

  /// Subtitle shown on the biometric lock screen.
  ///
  /// In en, this message translates to:
  /// **'Authenticate to continue'**
  String get biometricSubtitle;

  /// Button label when biometric prompt is ready.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get biometricUnlock;

  /// Button label while the biometric prompt is in progress.
  ///
  /// In en, this message translates to:
  /// **'Authenticating…'**
  String get biometricAuthenticating;

  /// Button to log out from the biometric lock screen.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get biometricLogOut;

  /// Headline on the backend configuration screen.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get backendConfigTitle;

  /// Subtitle below the headline on the backend configuration screen.
  ///
  /// In en, this message translates to:
  /// **'Update your Sure server URL'**
  String get backendConfigSubtitle;

  /// Label for the example URLs info box on the config screen.
  ///
  /// In en, this message translates to:
  /// **'Example URLs'**
  String get backendConfigExampleUrlsLabel;

  /// Label for the server URL field on the config screen.
  ///
  /// In en, this message translates to:
  /// **'Sure server URL'**
  String get backendConfigUrlLabel;

  /// Hint text for the server URL field.
  ///
  /// In en, this message translates to:
  /// **'https://app.sure.am'**
  String get backendConfigUrlHint;

  /// Label for the custom proxy headers section on the config screen.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy headers'**
  String get backendConfigProxyHeadersLabel;

  /// Subtitle for the proxy headers expansion tile when no headers are configured.
  ///
  /// In en, this message translates to:
  /// **'Optional headers for a reverse proxy or auth gateway'**
  String get backendConfigProxyHeadersSubtitle;

  /// Subtitle for the proxy headers expansion tile when headers are configured.
  ///
  /// In en, this message translates to:
  /// **'{count} configured'**
  String backendConfigProxyHeadersCount(int count);

  /// Label on the test-connection button while the test is in progress.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get backendConfigTesting;

  /// Button label to test the server connection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get backendConfigTestButton;

  /// Button label to proceed after saving configuration.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get backendConfigContinueButton;

  /// Helper text below the config form.
  ///
  /// In en, this message translates to:
  /// **'You can change this later in the settings.'**
  String get backendConfigChangeHint;

  /// App bar title for the recent transactions screen.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recentTransactionsTitle;

  /// Empty-state message on the recent transactions screen.
  ///
  /// In en, this message translates to:
  /// **'No Transactions'**
  String get recentTransactionsEmpty;

  /// Tooltip for the display-limit popup menu on the recent transactions screen.
  ///
  /// In en, this message translates to:
  /// **'Display Limit'**
  String get recentTransactionsDisplayLimit;

  /// Menu item label to show N recent transactions.
  ///
  /// In en, this message translates to:
  /// **'Show {count}'**
  String recentTransactionsShowN(int count);

  /// Empty-state subtitle prompting the user to pull to refresh.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get recentTransactionsPullToRefresh;

  /// App bar title for the log viewer screen.
  ///
  /// In en, this message translates to:
  /// **'Debug Logs'**
  String get logViewerTitle;

  /// Log level filter chip: show all log entries.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get logViewerFilterAll;

  /// Log level filter chip: show info entries only.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logViewerFilterInfo;

  /// Log level filter chip: show warning entries only.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logViewerFilterWarning;

  /// Log level filter chip: show error entries only.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logViewerFilterError;

  /// Log level filter chip: show debug entries only.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get logViewerFilterDebug;

  /// Tooltip for the auto-scroll toggle button when auto-scroll is off.
  ///
  /// In en, this message translates to:
  /// **'Enable auto-scroll'**
  String get logViewerAutoScrollEnable;

  /// Tooltip for the auto-scroll toggle button when auto-scroll is on.
  ///
  /// In en, this message translates to:
  /// **'Disable auto-scroll'**
  String get logViewerAutoScrollDisable;

  /// Tooltip for the copy-logs action button.
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get logViewerCopyLogs;

  /// Tooltip for the clear-logs action button.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get logViewerClearLogs;

  /// Snackbar message after logs are copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logViewerLogsCopied;

  /// Empty-state message shown when there are no log entries to display.
  ///
  /// In en, this message translates to:
  /// **'No logs yet'**
  String get logViewerEmpty;

  /// Message shown in the connectivity banner when the device has no network.
  ///
  /// In en, this message translates to:
  /// **'You are offline'**
  String get connectivityOffline;

  /// Connectivity banner message showing how many transactions are queued for sync.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} transaction pending sync} other{{count} transactions pending sync}}'**
  String connectivityPendingSync(int count);

  /// Button label in the connectivity banner to trigger an immediate sync.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get connectivitySyncNow;

  /// Button label to add a new custom proxy header.
  ///
  /// In en, this message translates to:
  /// **'Add header'**
  String get proxyHeadersAddHeader;

  /// Label for the header-name input field.
  ///
  /// In en, this message translates to:
  /// **'Header name'**
  String get proxyHeadersNameLabel;

  /// Hint text for the header-name input (example header name).
  ///
  /// In en, this message translates to:
  /// **'X-Auth-Token'**
  String get proxyHeadersNameHint;

  /// Label for the header-value input field.
  ///
  /// In en, this message translates to:
  /// **'Header value'**
  String get proxyHeadersValueLabel;

  /// Tooltip for the remove-header icon button.
  ///
  /// In en, this message translates to:
  /// **'Remove header'**
  String get proxyHeadersRemove;

  /// Tooltip for the refresh button on the account detail header.
  ///
  /// In en, this message translates to:
  /// **'Refresh account details'**
  String get accountDetailRefreshTooltip;

  /// Fallback label when a holding has no name.
  ///
  /// In en, this message translates to:
  /// **'Holding'**
  String get accountDetailHoldingFallback;

  /// Label for the cash position chip in the account detail header.
  ///
  /// In en, this message translates to:
  /// **'Cash {amount}'**
  String accountDetailCashChip(String amount);

  /// Snackbar shown on the biometric lock screen when authentication fails.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed. Tap Unlock to try again.'**
  String get biometricLockFailedRetry;

  /// Reason shown in the system biometric prompt when enabling app lock from settings.
  ///
  /// In en, this message translates to:
  /// **'Verify biometric to enable app lock'**
  String get settingsBiometricVerifyReason;

  /// Snackbar shown when biometric verification fails while enabling app lock.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication failed.'**
  String get settingsBiometricFailed;

  /// Snackbar shown when the app store update link cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Unable to open store link'**
  String get settingsUpdateOpenStoreError;

  /// Snackbar shown when clearing local data fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear local data.'**
  String get settingsClearDataFailed;

  /// Snackbar shown after local data is cleared, prompting the user to pull to refresh.
  ///
  /// In en, this message translates to:
  /// **'Local data cleared successfully. Pull to refresh to sync from server.'**
  String get settingsClearDataSuccessDetailed;

  /// Snackbar shown when the contact/Discord link cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Unable to open link'**
  String get settingsContactOpenLinkError;

  /// Body text for the reset-account confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Resetting your account will delete all your accounts, categories, merchants, tags, and other data, but keep your user account intact.\n\nThis action cannot be undone. Are you sure?'**
  String get settingsResetAccountContent;

  /// Title and confirm button label for the reset-account action.
  ///
  /// In en, this message translates to:
  /// **'Reset Account'**
  String get settingsResetAccount;

  /// Snackbar shown after an account reset is initiated.
  ///
  /// In en, this message translates to:
  /// **'Account reset has been initiated. This may take a moment.'**
  String get settingsResetAccountInitiated;

  /// Snackbar shown when resetting the account fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to reset account'**
  String get settingsResetAccountFailed;

  /// Body text for the delete-account confirmation dialog on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account will permanently remove all your data and cannot be undone.\n\nAre you sure you want to delete your account?'**
  String get settingsDeleteAccountConfirmContent;

  /// Snackbar shown when deleting the account fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account'**
  String get settingsDeleteAccountFailed;

  /// Explanatory note shown in the custom proxy headers dialog.
  ///
  /// In en, this message translates to:
  /// **'Headers are sent by the app with API requests. External browser SSO pages may not receive them.'**
  String get settingsProxyHeadersNote;

  /// Snackbar shown after custom proxy headers are saved.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy headers saved'**
  String get settingsProxyHeadersSaved;

  /// Snackbar shown when saving custom proxy headers fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to save custom proxy headers.'**
  String get settingsProxyHeadersSaveFailed;

  /// App version list tile title on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'App Version: {version}'**
  String settingsAppVersion(String version);

  /// Subtitle for the check-for-updates list tile.
  ///
  /// In en, this message translates to:
  /// **'See if a newer version is available'**
  String get settingsCheckForUpdatesSubtitle;

  /// Title for the contact-us list tile on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get settingsContactUs;

  /// Accessibility label for the debug logs list tile.
  ///
  /// In en, this message translates to:
  /// **'Open debug logs'**
  String get settingsDebugLogsSemantics;

  /// Subtitle for the debug logs list tile.
  ///
  /// In en, this message translates to:
  /// **'View app diagnostic logs'**
  String get settingsDebugLogsSubtitle;

  /// Title for the group-by-account-type toggle on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Group by Account Type'**
  String get settingsGroupByAccountType;

  /// Subtitle for the group-by-account-type toggle.
  ///
  /// In en, this message translates to:
  /// **'Group accounts by type (Crypto, Bank, etc.)'**
  String get settingsGroupByAccountTypeSubtitle;

  /// Title for the custom proxy headers list tile on the settings screen.
  ///
  /// In en, this message translates to:
  /// **'Custom proxy headers'**
  String get settingsProxyHeadersTileTitle;

  /// Subtitle for the custom proxy headers list tile when no headers are configured.
  ///
  /// In en, this message translates to:
  /// **'Optional headers for a reverse proxy or auth gateway'**
  String get settingsProxyHeadersTileSubtitleEmpty;

  /// Subtitle for the custom proxy headers list tile when headers are configured.
  ///
  /// In en, this message translates to:
  /// **'{count} configured'**
  String settingsProxyHeadersTileSubtitleCount(int count);

  /// Subtitle for the clear-local-data list tile.
  ///
  /// In en, this message translates to:
  /// **'Remove all cached transactions and accounts'**
  String get settingsClearDataTileSubtitle;

  /// Subtitle for the reset-account list tile in the danger zone.
  ///
  /// In en, this message translates to:
  /// **'Delete all accounts, categories, merchants, and tags but keep your user account'**
  String get settingsResetAccountTileSubtitle;

  /// Subtitle for the delete-account list tile in the danger zone.
  ///
  /// In en, this message translates to:
  /// **'Permanently remove all your data. This cannot be undone.'**
  String get settingsDeleteAccountTileSubtitle;

  /// Fallback display name when the user has no name set.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get settingsUserFallback;

  /// Body text for the multi-chat delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Delete {count} chat? This cannot be undone.} other{Delete {count} chats? This cannot be undone.}}'**
  String chatListDeleteMultiContent(int count);

  /// Snackbar shown after multiple chats are deleted.
  ///
  /// In en, this message translates to:
  /// **'Chats deleted'**
  String get chatListDeletedSuccess;

  /// Snackbar shown when deleting multiple chats fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete chats'**
  String get chatListDeleteFailed;

  /// Banner on the chat list screen when some pages of chats failed to load.
  ///
  /// In en, this message translates to:
  /// **'Some chats may be missing. The list didn\'t finish loading.'**
  String get chatListIncomplete;

  /// Error-state heading on the chat list screen.
  ///
  /// In en, this message translates to:
  /// **'Failed to load chats'**
  String get chatListError;

  /// Relative time label for very recent chats.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get chatListJustNow;

  /// Body text for the single-chat delete confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?'**
  String chatListDeleteSingleContent(String title);

  /// Snackbar shown when the sign-up page cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'Unable to open sign up page'**
  String get loginSignUpOpenError;

  /// Title for the API key login dialog on the login screen.
  ///
  /// In en, this message translates to:
  /// **'API Key Login'**
  String get loginApiKeyDialogTitle;

  /// Body text for the API key login dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter your API key to sign in.'**
  String get loginApiKeyDialogBody;

  /// Fallback error shown when an API key login fails.
  ///
  /// In en, this message translates to:
  /// **'Invalid API key'**
  String get loginApiKeyInvalid;

  /// Sign-in button label in the API key login dialog.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginApiKeySignIn;

  /// Leading text before the Sign Up link on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Demo account or '**
  String get loginDemoOrSignUpPrefix;

  /// Tappable Sign Up link text on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get loginSignUpLink;

  /// Trailing punctuation after the Sign Up link on the login screen.
  ///
  /// In en, this message translates to:
  /// **'!'**
  String get loginSignUpSuffix;

  /// Info banner shown when MFA is required during login.
  ///
  /// In en, this message translates to:
  /// **'Two-factor authentication is enabled. Enter your code.'**
  String get loginMfaInfo;

  /// Validation error when the MFA code field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your authentication code'**
  String get loginMfaCodeRequired;

  /// Divider label between primary and alternate sign-in options.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get loginOrDivider;

  /// Heading above the displayed server URL on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Sure server URL:'**
  String get loginServerUrlHeading;

  /// Button label to open the API key login dialog.
  ///
  /// In en, this message translates to:
  /// **'API-Key Login'**
  String get loginApiKeyLoginButton;

  /// Tooltip for the backend settings button on the login screen.
  ///
  /// In en, this message translates to:
  /// **'Backend Settings'**
  String get loginBackendSettingsTooltip;

  /// Snackbar shown when the session expires while editing a transaction.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again.'**
  String get transactionEditSessionExpired;

  /// Snackbar shown after a transaction is updated successfully.
  ///
  /// In en, this message translates to:
  /// **'Transaction updated'**
  String get transactionEditUpdated;

  /// Fallback snackbar shown when updating a transaction fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to update transaction'**
  String get transactionEditUpdateFailed;

  /// Validation error when the transaction name exceeds the maximum length.
  ///
  /// In en, this message translates to:
  /// **'Name must be {max} characters or fewer'**
  String transactionEditNameMaxLength(int max);

  /// Validation error when the transaction name contains control characters.
  ///
  /// In en, this message translates to:
  /// **'Name contains unsupported characters'**
  String get transactionEditNameInvalidChars;

  /// Validation error when the notes exceed the maximum length.
  ///
  /// In en, this message translates to:
  /// **'Notes must be {max} characters or fewer'**
  String transactionEditNotesMaxLength(int max);

  /// Validation error when the notes contain control characters.
  ///
  /// In en, this message translates to:
  /// **'Notes contain unsupported characters'**
  String get transactionEditNotesInvalidChars;

  /// Dropdown option representing no selected category in the edit form.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get transactionEditNoCategory;

  /// Fallback dropdown label for the currently selected category when its name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Current category'**
  String get transactionEditCurrentCategory;

  /// Dropdown option representing no selected merchant in the edit form.
  ///
  /// In en, this message translates to:
  /// **'No merchant'**
  String get transactionEditNoMerchant;

  /// Fallback dropdown label for the currently selected merchant when its name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Current merchant'**
  String get transactionEditCurrentMerchant;

  /// Message shown when no tags are available to select in the edit form.
  ///
  /// In en, this message translates to:
  /// **'No tags available'**
  String get transactionEditNoTags;

  /// Fallback label for a selected tag whose name is unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown tag'**
  String get transactionEditUnknownTag;

  /// Notice shown when a transaction cannot be edited because it is not yet synced.
  ///
  /// In en, this message translates to:
  /// **'Only synced transactions can be edited from mobile.'**
  String get transactionEditSyncedOnly;

  /// Helper text under the category dropdown in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Choose a replacement category'**
  String get transactionEditCategoryHelper;

  /// Helper text under the merchant dropdown in the edit form.
  ///
  /// In en, this message translates to:
  /// **'Choose a replacement merchant'**
  String get transactionEditMerchantHelper;

  /// Snackbar shown when the session expires while creating a transaction.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please login again.'**
  String get transactionFormSessionExpired;

  /// Validation error when the amount field is empty in the create form.
  ///
  /// In en, this message translates to:
  /// **'Please enter an amount'**
  String get transactionFormAmountRequiredPrompt;

  /// Validation error when the amount is not a valid number.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number'**
  String get transactionFormAmountInvalidNumber;

  /// Validation error when the amount is zero or negative.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than 0'**
  String get transactionFormAmountTooSmall;

  /// Snackbar shown after a transaction is created while online.
  ///
  /// In en, this message translates to:
  /// **'Transaction created successfully'**
  String get transactionFormCreateSuccessOnline;

  /// Snackbar shown after a transaction is saved while offline.
  ///
  /// In en, this message translates to:
  /// **'Transaction saved (will sync when online)'**
  String get transactionFormCreateSuccessOffline;

  /// Snackbar shown when creating a transaction fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to create transaction'**
  String get transactionFormCreateFailed;

  /// Snackbar shown when an unexpected error occurs while creating a transaction.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String transactionFormGenericError(String error);

  /// Toggle label to hide the optional transaction fields.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get transactionFormLess;

  /// Toggle label to show the optional transaction fields.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get transactionFormMore;

  /// Helper text for the date field in the create form.
  ///
  /// In en, this message translates to:
  /// **'Optional (default: today)'**
  String get transactionFormDateHelper;

  /// Helper text for the name field in the create form.
  ///
  /// In en, this message translates to:
  /// **'Optional (default: SureApp)'**
  String get transactionFormNameHelper;

  /// Placeholder shown while categories are loading in the create form.
  ///
  /// In en, this message translates to:
  /// **'Loading categories…'**
  String get transactionFormCategoryLoading;

  /// Helper text for the category dropdown in the create form.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get transactionFormCategoryHelper;

  /// Dropdown option representing no selected category in the create form.
  ///
  /// In en, this message translates to:
  /// **'No category'**
  String get transactionFormNoCategory;

  /// Submit button label on the create-transaction form.
  ///
  /// In en, this message translates to:
  /// **'Create Transaction'**
  String get transactionFormCreateButton;

  /// Helper text under the amount field indicating it is required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get transactionFormAmountHelper;

  /// Body text for the clear-logs confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all logs?'**
  String get logViewerClearConfirm;

  /// Confirm button label in the clear-logs dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logViewerClear;

  /// Title for the edit-chat-title dialog.
  ///
  /// In en, this message translates to:
  /// **'Edit Title'**
  String get chatConversationEditTitle;

  /// Label for the chat title input field in the edit dialog.
  ///
  /// In en, this message translates to:
  /// **'Chat Title'**
  String get chatConversationTitleLabel;

  /// Tooltip for the refresh button in the chat conversation screen.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get chatConversationRefreshTooltip;

  /// Error-state heading when a chat fails to load.
  ///
  /// In en, this message translates to:
  /// **'Failed to load chat'**
  String get chatConversationLoadError;

  /// Title for the dialog prompting the user to enable AI chat.
  ///
  /// In en, this message translates to:
  /// **'Turn on AI Chat?'**
  String get navEnableAiChatTitle;

  /// Body text for the enable-AI-chat dialog.
  ///
  /// In en, this message translates to:
  /// **'AI Chat is currently disabled in your account settings. Would you like to turn it on now?'**
  String get navEnableAiChatContent;

  /// Dismiss button in the enable-AI-chat dialog.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get navEnableAiChatNotNow;

  /// Confirm button in the enable-AI-chat dialog.
  ///
  /// In en, this message translates to:
  /// **'Turn on AI'**
  String get navEnableAiChatConfirm;

  /// Snackbar shown when enabling AI chat fails.
  ///
  /// In en, this message translates to:
  /// **'Unable to enable AI right now.'**
  String get navEnableAiChatFailed;

  /// Tooltip for the edit button on a transaction row.
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get transactionsListEditTooltip;

  /// Snackbar shown when trying to sync without being signed in.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to sync transactions'**
  String get connectivitySignInToSync;

  /// Snackbar shown after transactions sync successfully.
  ///
  /// In en, this message translates to:
  /// **'Transactions synced successfully'**
  String get connectivitySyncSuccess;

  /// Snackbar shown when a manual sync fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync transactions. Please try again.'**
  String get connectivitySyncFailed;

  /// Snackbar shown when authentication fails during a manual sync.
  ///
  /// In en, this message translates to:
  /// **'Unable to authenticate. Please try again.'**
  String get connectivityAuthFailed;

  /// Header text on the SSO onboarding screen showing the signed-in Google email.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String ssoOnboardingSignedInAs(String email);

  /// Header text on the SSO onboarding screen when the Google email is unknown.
  ///
  /// In en, this message translates to:
  /// **'Google account verified'**
  String get ssoOnboardingGoogleVerified;

  /// Explanatory note on the link-existing form prompting the user to enter their credentials.
  ///
  /// In en, this message translates to:
  /// **'Enter your existing account credentials to link with Google Sign-In.'**
  String get ssoOnboardingLinkCredentialsNote;

  /// Explanatory note on the create form when the user has a pending household invitation.
  ///
  /// In en, this message translates to:
  /// **'You have a pending invitation. Accept it to join an existing household.'**
  String get ssoOnboardingPendingInvitationNote;

  /// Explanatory note on the create form when creating a brand-new account via Google.
  ///
  /// In en, this message translates to:
  /// **'Create a new account using your Google identity.'**
  String get ssoOnboardingCreateIdentityNote;

  /// Validation error when the first-name field is empty on the SSO onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get ssoOnboardingFirstNameRequired;

  /// Validation error when the last-name field is empty on the SSO onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get ssoOnboardingLastNameRequired;

  /// Error shown when the connection test times out.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout. Please check the URL and try again.'**
  String get backendConfigTimeout;

  /// Message shown when the connection test succeeds.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get backendConfigSuccess;

  /// Error shown when the server returns a non-success status during the connection test.
  ///
  /// In en, this message translates to:
  /// **'Server responded with status {code}. Please check if this is a Sure backend server.'**
  String backendConfigServerError(int code);

  /// Error shown when the connection test fails with an exception.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String backendConfigConnectionFailed(String error);

  /// Error shown when saving the backend URL fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to save URL: {error}'**
  String backendConfigSaveFailed(String error);

  /// Validation error when the backend URL field is empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter a backend URL'**
  String get backendConfigUrlRequired;

  /// Validation error when the backend URL is missing an http(s) scheme.
  ///
  /// In en, this message translates to:
  /// **'URL must start with http:// or https://'**
  String get backendConfigUrlScheme;

  /// Validation error when the backend URL is malformed.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL'**
  String get backendConfigUrlInvalid;

  /// Helper text below the custom proxy headers section on the backend config screen.
  ///
  /// In en, this message translates to:
  /// **'Headers are sent by the app with API requests. External browser SSO pages may not receive them.'**
  String get backendConfigHeadersHelp;

  /// Fallback label when a transaction's account cannot be resolved.
  ///
  /// In en, this message translates to:
  /// **'Unknown Account'**
  String get recentTransactionsUnknownAccount;

  /// Error message shown when account detail and balances both fail to load.
  ///
  /// In en, this message translates to:
  /// **'Account details are temporarily unavailable'**
  String get accountDetailUnavailable;

  /// Relative time label for a chat updated some minutes ago.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String chatListMinutesAgo(int minutes);

  /// Relative time label for a chat updated some hours ago.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String chatListHoursAgo(int hours);

  /// Relative time label for a chat updated some days ago.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String chatListDaysAgo(int days);

  /// Fallback snackbar shown when creating a new conversation from the first message fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to start conversation. Please try again.'**
  String get chatConversationStartFailed;

  /// Menu item title for Budgets in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get moreBudgets;

  /// Subtitle for the Budgets menu item in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Budgeted vs. actual spending by category'**
  String get moreBudgetsSubtitle;

  /// App bar title of the Budgets screen.
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get budgetsTitle;

  /// Tooltip for the button that shows the previous month's budget.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get budgetsPreviousMonth;

  /// Tooltip for the button that shows the next month's budget.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get budgetsNextMonth;

  /// Label for the total amount budgeted for spending this month.
  ///
  /// In en, this message translates to:
  /// **'Budgeted'**
  String get budgetsBudgeted;

  /// Label for the amount actually spent this month.
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get budgetsActual;

  /// Label for the amount left to spend this month.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get budgetsRemaining;

  /// Label for the month's actual income in the budget summary.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get budgetsIncome;

  /// Expected income for the month, shown next to actual income.
  ///
  /// In en, this message translates to:
  /// **'Expected {amount}'**
  String budgetsExpectedIncome(String amount);

  /// Budget limit shown after the amount spent in a category, e.g. '$120 of $300'.
  ///
  /// In en, this message translates to:
  /// **'of {amount}'**
  String budgetsOfAmount(String amount);

  /// Amount still available to spend in a category.
  ///
  /// In en, this message translates to:
  /// **'{amount} left'**
  String budgetsAmountLeft(String amount);

  /// Amount by which a category's spending exceeds its budget.
  ///
  /// In en, this message translates to:
  /// **'{amount} over'**
  String budgetsOverBy(String amount);

  /// Unspent amount carried over from the previous month into this category.
  ///
  /// In en, this message translates to:
  /// **'+{amount} rolled over'**
  String budgetsRolledOver(String amount);

  /// Shown for a subcategory without its own limit that draws from its parent category's budget.
  ///
  /// In en, this message translates to:
  /// **'Shared budget'**
  String get budgetsSharedBudget;

  /// Shown for a category with spending but no budgeted amount.
  ///
  /// In en, this message translates to:
  /// **'No budget'**
  String get budgetsNoLimit;

  /// Heading of the per-category budget list.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get budgetsCategoriesTitle;

  /// Filter showing only categories that are over budget, with how many there are.
  ///
  /// In en, this message translates to:
  /// **'Over budget ({count})'**
  String budgetsFilterOverBudget(int count);

  /// Badge on a category that has spent more than its budget.
  ///
  /// In en, this message translates to:
  /// **'Over budget'**
  String get budgetsOverBudget;

  /// Badge on a category that has spent at least 90% of its budget.
  ///
  /// In en, this message translates to:
  /// **'Near limit'**
  String get budgetsNearLimit;

  /// Label for one of several budgets that exist for the same month (household, personal or shared).
  ///
  /// In en, this message translates to:
  /// **'Budget {number}'**
  String budgetsBudgetNumber(int number);

  /// Title shown when the server has no budget for the selected month.
  ///
  /// In en, this message translates to:
  /// **'No budget for {month}'**
  String budgetsNoBudgetTitle(String month);

  /// Explains how to create a budget when none exists for the selected month.
  ///
  /// In en, this message translates to:
  /// **'Budgets are created in Sure on the web. Open Budgets there to set one up for this month.'**
  String get budgetsNoBudgetMessage;

  /// Shown when a budget exists for the month but has no amounts set.
  ///
  /// In en, this message translates to:
  /// **'No spending limits are set for this month yet. Set them up in Sure on the web.'**
  String get budgetsNotSetUpMessage;

  /// Shown when no category line has a budget or spending.
  ///
  /// In en, this message translates to:
  /// **'No budgeted categories or spending this month.'**
  String get budgetsNoCategories;

  /// Title shown when the budget cannot be loaded without a connection.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get budgetsOfflineTitle;

  /// Shown when offline and the selected month has not been loaded yet.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to load this month\'s budget.'**
  String get budgetsOfflineMessage;

  /// Banner shown when offline and the budget shown was loaded earlier in the session.
  ///
  /// In en, this message translates to:
  /// **'Offline. Showing the figures loaded earlier.'**
  String get budgetsOfflineCached;

  /// Banner shown when refreshing a budget fails but the month loaded earlier is still on screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh. Showing the figures loaded earlier.'**
  String get budgetsRefreshFailed;

  /// Title shown when loading budgets fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load budgets'**
  String get budgetsLoadFailed;

  /// Shown when the budgets request is rejected as unauthorized.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get budgetsSessionExpired;

  /// Empty state of a budget category's transaction list.
  ///
  /// In en, this message translates to:
  /// **'No transactions in this category for {month}.'**
  String budgetCategoryTransactionsEmpty(String month);

  /// Button that loads the next page of a budget category's transactions.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get budgetCategoryTransactionsLoadMore;

  /// Shown when a budget category's transactions fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load transactions'**
  String get budgetCategoryTransactionsLoadFailed;

  /// Menu item title for the Cash Flow report in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow'**
  String get moreCashFlow;

  /// Subtitle for the Cash Flow menu item in the More screen.
  ///
  /// In en, this message translates to:
  /// **'Income, spending and savings by category'**
  String get moreCashFlowSubtitle;

  /// App bar title of the Cash Flow report screen.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow'**
  String get cashFlowTitle;

  /// Period chip: the current month (web MTD), or the whole current custom month when the family has a custom month start day.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get cashFlowPeriodCurrentMonth;

  /// Period chip: the previous month (web LM), following the family's custom month start day when set.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get cashFlowPeriodLastMonth;

  /// Period chip: last 30 days (web 30D).
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get cashFlowPeriodLast30Days;

  /// Period chip: last 90 days (web 90D).
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get cashFlowPeriodLast90Days;

  /// Period chip: current year to date (web YTD).
  ///
  /// In en, this message translates to:
  /// **'Year to date'**
  String get cashFlowPeriodCurrentYear;

  /// Period chip: last 365 days (web 365D).
  ///
  /// In en, this message translates to:
  /// **'Last 365 days'**
  String get cashFlowPeriodLast365Days;

  /// Summary label and segment label for income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get cashFlowIncome;

  /// Summary label and segment label for expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get cashFlowExpenses;

  /// Summary label for income minus expenses.
  ///
  /// In en, this message translates to:
  /// **'Net savings'**
  String get cashFlowNetSavings;

  /// Savings rate shown under net savings, e.g. '18.2% savings rate'.
  ///
  /// In en, this message translates to:
  /// **'{rate} savings rate'**
  String cashFlowSavingsRate(String rate);

  /// Section header for the expense category chart and list.
  ///
  /// In en, this message translates to:
  /// **'Expenses by category'**
  String get cashFlowExpensesByCategory;

  /// Section header for the income category chart and list.
  ///
  /// In en, this message translates to:
  /// **'Income by category'**
  String get cashFlowIncomeByCategory;

  /// Category row subtitle with its share of total expenses.
  ///
  /// In en, this message translates to:
  /// **'{percent} of expenses'**
  String cashFlowShareOfExpenses(String percent);

  /// Category row subtitle with its share of total income.
  ///
  /// In en, this message translates to:
  /// **'{percent} of income'**
  String cashFlowShareOfIncome(String percent);

  /// Empty state title when the period has no categorized cash flow.
  ///
  /// In en, this message translates to:
  /// **'No income or expenses in this period'**
  String get cashFlowEmpty;

  /// Empty state subtitle on the Cash Flow screen.
  ///
  /// In en, this message translates to:
  /// **'Try another period or pull to refresh.'**
  String get cashFlowEmptySubtitle;

  /// Shown in the category section when the expense side is empty.
  ///
  /// In en, this message translates to:
  /// **'No expenses in this period'**
  String get cashFlowNoExpenses;

  /// Shown in the category section when the income side is empty.
  ///
  /// In en, this message translates to:
  /// **'No income in this period'**
  String get cashFlowNoIncome;

  /// Error state title when the cash flow request fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load cash flow'**
  String get cashFlowLoadFailed;

  /// Error state message when the device is offline and no report is loaded.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Cash flow is calculated by your Sure server, so it needs a connection.'**
  String get cashFlowOffline;

  /// Badge shown when the displayed report could not be refreshed.
  ///
  /// In en, this message translates to:
  /// **'Outdated'**
  String get cashFlowOutdated;

  /// Empty state of the category transactions screen.
  ///
  /// In en, this message translates to:
  /// **'No transactions in this period'**
  String get cashFlowTransactionsEmpty;

  /// Error state of the category transactions screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load transactions'**
  String get cashFlowTransactionsLoadFailed;

  /// Balance chart range chip: last 7 days.
  ///
  /// In en, this message translates to:
  /// **'1W'**
  String get accountRangeWeek;

  /// Balance chart range chip: last 30 days.
  ///
  /// In en, this message translates to:
  /// **'1M'**
  String get accountRangeMonth;

  /// Balance chart range chip: last 90 days.
  ///
  /// In en, this message translates to:
  /// **'3M'**
  String get accountRangeQuarter;

  /// Balance chart range chip: last 365 days.
  ///
  /// In en, this message translates to:
  /// **'1Y'**
  String get accountRangeYear;

  /// Balance chart range chip: full history.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get accountRangeAll;

  /// Shown in place of the balance chart when the selected range has fewer than two balances.
  ///
  /// In en, this message translates to:
  /// **'No balance history for this period'**
  String get accountChartNoHistory;

  /// Balance change over the selected chart range, e.g. '+$1,204.00 (+1.4%) this period'.
  ///
  /// In en, this message translates to:
  /// **'{change} ({percent}) this period'**
  String accountChartChangeLabel(String change, String percent);

  /// Balance change over the selected range when no percentage applies (the range started at zero).
  ///
  /// In en, this message translates to:
  /// **'{change} this period'**
  String accountChartChangeOnlyLabel(String change);

  /// Investment account section: current positions.
  ///
  /// In en, this message translates to:
  /// **'Holdings'**
  String get accountTabHoldings;

  /// Investment account section: trades and other investment activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get accountTabActivity;

  /// Investment account section: cash transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get accountTabTransactions;

  /// Empty state of the holdings list.
  ///
  /// In en, this message translates to:
  /// **'No holdings synced yet'**
  String get holdingsEmpty;

  /// Error state of the holdings list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load holdings'**
  String get holdingsLoadFailed;

  /// Holding row subtitle: share count and current price.
  ///
  /// In en, this message translates to:
  /// **'{quantity} shares · {price}'**
  String holdingSharesAtPrice(String quantity, String price);

  /// Shown instead of gain/loss when the provider sent no cost basis for a holding.
  ///
  /// In en, this message translates to:
  /// **'No cost basis'**
  String get holdingNoCostBasis;

  /// Empty state of the investment activity list.
  ///
  /// In en, this message translates to:
  /// **'No investment activity yet'**
  String get tradesEmpty;

  /// Error state of the investment activity list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load activity'**
  String get tradesLoadFailed;

  /// Trade row label for a purchase when the server sent no activity label.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get tradeBuy;

  /// Trade row label for a sale when the server sent no activity label.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get tradeSell;

  /// Title of the dashboard investments card and the portfolio screen.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get portfolioTitle;

  /// How many investment accounts the dashboard investments card covers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 account} other{{count} accounts}}'**
  String portfolioAccountCount(int count);

  /// Total unrealized gain or loss across holdings with a cost basis, e.g. 'Unrealized +$9,880.00 (+13.3%)'.
  ///
  /// In en, this message translates to:
  /// **'Unrealized {amount} ({percent})'**
  String portfolioUnrealizedGain(String amount, String percent);

  /// Section heading for the portfolio allocation bar.
  ///
  /// In en, this message translates to:
  /// **'Allocation'**
  String get portfolioAllocation;

  /// Allocation slice grouping every position after the largest few.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get portfolioAllocationOther;

  /// Allocation slice for uninvested cash in the investment accounts.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get portfolioAllocationCash;

  /// Section heading for the latest trades across investment accounts.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get portfolioRecentActivity;

  /// Error state of the portfolio screen.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your investments'**
  String get portfolioLoadFailed;

  /// Trade row subtitle: quantity traded at a price.
  ///
  /// In en, this message translates to:
  /// **'{quantity} @ {price}'**
  String tradeQuantityAtPrice(String quantity, String price);

  /// Bottom navigation label for the Activity (transactions) tab.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get shellNavActivity;

  /// Bottom navigation label for the Plan tab (budget, recurring, goals, bills).
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get shellNavPlan;

  /// Bottom navigation label for the Invest (portfolio) tab.
  ///
  /// In en, this message translates to:
  /// **'Invest'**
  String get shellNavInvest;

  /// Title of the settings screen and tooltip of the header button that opens it.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get shellSettingsTitle;

  /// Settings section for connections, imports, categories, tags, merchants, rules and exports.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get shellSectionData;

  /// Settings section for calendar, cash flow and recent transactions.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get shellSectionTools;

  /// Settings section for the user's profile, preferences and security.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get shellSectionYou;

  /// Settings section for this app's own settings (theme, privacy, sign out).
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get shellSectionApp;

  /// Settings row: bank sync providers and connections (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get shellConnections;

  /// Settings row: import data from a file (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get shellImport;

  /// Settings row: manage categories (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get shellCategories;

  /// Settings row: manage tags (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get shellTags;

  /// Settings row: manage merchants (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Merchants'**
  String get shellMerchants;

  /// Settings row: manage transaction rules (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get shellRules;

  /// Settings row: export your data (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get shellExport;

  /// Settings row: the user's profile (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get shellProfile;

  /// Settings row: account preferences such as currency and locale (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get shellPreferences;

  /// Settings row: password, MFA and sessions (opens the web).
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get shellSecurity;

  /// Settings row label showing the Sure server URL the app talks to.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get shellServer;

  /// Accessibility label of the globe icon on rows that open a web page in the app.
  ///
  /// In en, this message translates to:
  /// **'Opens on the web'**
  String get shellOpensOnWeb;

  /// Plan tab segment: monthly budget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get shellPlanBudget;

  /// Plan tab segment: recurring transactions.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get shellPlanRecurring;

  /// Plan tab segment: savings goals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get shellPlanGoals;

  /// Plan tab segment: upcoming bills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get shellPlanBills;

  /// Placeholder title for a section that isn't in the app yet.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get shellComingSoon;

  /// Placeholder body for a section that isn't in the app yet.
  ///
  /// In en, this message translates to:
  /// **'This part of the app is on its way.'**
  String get shellComingSoonBody;

  /// Plan tab, Goals segment: explains goals aren't in the app yet.
  ///
  /// In en, this message translates to:
  /// **'Goals live on the web for now. Open them here to track your progress.'**
  String get shellGoalsOnWeb;

  /// Plan tab, Bills segment: explains bills aren't in the app yet.
  ///
  /// In en, this message translates to:
  /// **'Bills live on the web for now. Open them here to see what\'s coming up.'**
  String get shellBillsOnWeb;

  /// Button and tooltip that open the current feature in the in-app web view.
  ///
  /// In en, this message translates to:
  /// **'Open on the web'**
  String get shellOpenOnWeb;

  /// Invest tab empty state title.
  ///
  /// In en, this message translates to:
  /// **'No investment accounts'**
  String get shellInvestEmptyTitle;

  /// Invest tab empty state body.
  ///
  /// In en, this message translates to:
  /// **'Investment and crypto accounts you add show up here.'**
  String get shellInvestEmptyBody;

  /// Invest tab error state when accounts failed to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your accounts'**
  String get shellInvestLoadFailed;

  /// Web view toolbar button: go back one page.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get shellWebBack;

  /// Web view toolbar button: go forward one page.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get shellWebForward;

  /// Web view toolbar button on iOS: open the current page in Safari.
  ///
  /// In en, this message translates to:
  /// **'Open in Safari'**
  String get shellWebOpenInSafari;

  /// Web view toolbar button on other platforms: open the current page in the browser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get shellWebOpenInBrowser;

  /// Web view error state title.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this page'**
  String get shellWebLoadFailed;

  /// Snackbar when a link can't be opened outside the app.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link'**
  String get shellWebOpenFailed;

  /// Title of the Activity tab: every transaction across accounts.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// Placeholder of the Activity search field. Searches names, notes and merchants.
  ///
  /// In en, this message translates to:
  /// **'Search transactions'**
  String get activitySearchHint;

  /// Tooltip of the button that empties the Activity search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get activityClearSearch;

  /// Heading of the date filter sheet on the Activity tab.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get activityFilterDate;

  /// Activity date filter: the current calendar month (the default).
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get activityDateThisMonth;

  /// Activity date filter: the previous calendar month.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get activityDateLastMonth;

  /// Activity date filter: today and the 89 days before it.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get activityDateLast90Days;

  /// Activity date filter: the current calendar year.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get activityDateThisYear;

  /// Activity date filter: no date limit.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get activityDateAll;

  /// Activity date filter option that opens a date range picker.
  ///
  /// In en, this message translates to:
  /// **'Custom range…'**
  String get activityDateCustom;

  /// Label of the date filter chip for a custom range, e.g. 'Oct 1 – Oct 15'.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String activityDateRange(String start, String end);

  /// Activity filter chip and sheet title for categories.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get activityFilterCategory;

  /// Activity filter chip and sheet title for accounts.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get activityFilterAccount;

  /// Activity filter chip and sheet title for tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get activityFilterTags;

  /// Activity filter chip and sheet title for income or expense.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get activityFilterType;

  /// Activity type filter option: both income and expenses.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get activityTypeAll;

  /// Activity type filter option: money out only.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get activityTypeExpense;

  /// Activity type filter option: money in only.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get activityTypeIncome;

  /// Filter chip label with how many values are selected, e.g. 'Category · 2'.
  ///
  /// In en, this message translates to:
  /// **'{label} · {count}'**
  String activityFilterCount(String label, int count);

  /// Button that resets the Activity search and every filter.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get activityClearAll;

  /// Button in a filter sheet that deselects every value.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get activityFilterClear;

  /// Button in a filter sheet that applies the selection.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get activityFilterApply;

  /// Placeholder of the search field inside a long filter or category list.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get activityFilterSearchHint;

  /// Shown in a filter or category sheet that has no values.
  ///
  /// In en, this message translates to:
  /// **'Nothing to choose from yet'**
  String get activityFilterNoOptions;

  /// Day header in the Activity list for today's transactions.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get activityToday;

  /// Day header in the Activity list for yesterday's transactions.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get activityYesterday;

  /// Day header for transactions whose date could not be read.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get activityUnknownDate;

  /// Activity empty state with the default view (this month, no filters).
  ///
  /// In en, this message translates to:
  /// **'No transactions this month'**
  String get activityEmpty;

  /// Activity empty state when a search or filter is set.
  ///
  /// In en, this message translates to:
  /// **'No transactions match.'**
  String get activityEmptyFiltered;

  /// Button in the filtered empty state that resets the search and filters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get activityClearFilters;

  /// Error state of the Activity list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load transactions'**
  String get activityLoadFailed;

  /// Tooltip of the Activity app bar button that starts a new transaction.
  ///
  /// In en, this message translates to:
  /// **'Add transaction'**
  String get activityAdd;

  /// Title of the sheet that picks the account for a new transaction.
  ///
  /// In en, this message translates to:
  /// **'Choose an account'**
  String get activityPickAccount;

  /// Shown when adding a transaction but there are no accounts.
  ///
  /// In en, this message translates to:
  /// **'Add an account first.'**
  String get activityNoAccounts;

  /// Accessibility label of the icon on a transaction that is split into parts.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get activitySplit;

  /// Accessibility label of the icon on a transaction that is part of a transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get activityTransfer;

  /// App bar title in Activity multi-select mode.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String activitySelectedCount(int count);

  /// Bottom bar action that sets one category on every selected transaction.
  ///
  /// In en, this message translates to:
  /// **'Categorize'**
  String get activityCategorize;

  /// Title of the sheet that picks the category for bulk categorize.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get activityPickCategory;

  /// Progress while bulk categorizing.
  ///
  /// In en, this message translates to:
  /// **'Categorizing {done} of {total}…'**
  String activityCategorizing(int done, int total);

  /// Result after every selected transaction was categorized.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Categorized 1 transaction} other{Categorized {count} transactions}}'**
  String activityCategorized(int count);

  /// Progress while deleting the selected transactions.
  ///
  /// In en, this message translates to:
  /// **'Deleting {done} of {total}…'**
  String activityDeleting(int done, int total);

  /// Result of a bulk categorize or delete where some items failed.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} done. {failed} failed and are still selected.'**
  String activityBulkPartial(int done, int total, int failed);

  /// Shown when no access token is available for an Activity action.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Sign in again.'**
  String get activitySessionExpired;

  /// Name of the Recurring segment of the Plan tab: bills, subscriptions and income that repeat.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get recurring;

  /// Button that opens the form to add a recurring transaction.
  ///
  /// In en, this message translates to:
  /// **'Add recurring'**
  String get recurringAdd;

  /// Recurring list section: active items due by the end of this month, overdue included.
  ///
  /// In en, this message translates to:
  /// **'Upcoming this month'**
  String get recurringGroupUpcoming;

  /// Recurring list section: active items due after this month.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get recurringGroupLater;

  /// Recurring list section: items Sure detected that the user has not confirmed.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get recurringGroupSuggested;

  /// Recurring list section: paused, inactive and ended items.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get recurringGroupInactive;

  /// Label for the monthly total of active recurring expenses.
  ///
  /// In en, this message translates to:
  /// **'Monthly out'**
  String get recurringMonthlyOut;

  /// Label for the monthly total of active recurring income.
  ///
  /// In en, this message translates to:
  /// **'Monthly in'**
  String get recurringMonthlyIn;

  /// Empty state title of the Recurring list.
  ///
  /// In en, this message translates to:
  /// **'No recurring transactions yet'**
  String get recurringEmptyTitle;

  /// Empty state body of the Recurring list.
  ///
  /// In en, this message translates to:
  /// **'Add bills, subscriptions and income that repeat to see what\'s coming up.'**
  String get recurringEmptyBody;

  /// Error state of the Recurring list.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load recurring transactions'**
  String get recurringLoadFailed;

  /// Button that reloads the Recurring list after an error.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get recurringRetry;

  /// Cadence of a weekly recurring item.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Weekly} other{Every {count} weeks}}'**
  String recurringEveryWeeks(int count);

  /// Cadence of a monthly recurring item.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Monthly} other{Every {count} months}}'**
  String recurringEveryMonths(int count);

  /// Cadence of a yearly recurring item.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Yearly} other{Every {count} years}}'**
  String recurringEveryYears(int count);

  /// Cadence of a recurring item without explicit rules: monthly on a day of the month.
  ///
  /// In en, this message translates to:
  /// **'Monthly on day {day}'**
  String recurringMonthlyOnDay(int day);

  /// Next expected date of a recurring item, e.g. 'Next Nov 15'.
  ///
  /// In en, this message translates to:
  /// **'Next {date}'**
  String recurringNextDate(String date);

  /// Recurring item status.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get recurringStatusActive;

  /// Recurring item status.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringStatusPaused;

  /// Recurring item status.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get recurringStatusInactive;

  /// Recurring item status: detected, not confirmed.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get recurringStatusSuggested;

  /// Recurring item status.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get recurringStatusEnded;

  /// Marks a recurring item as money in; also the income option in the form.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get recurringIncome;

  /// Expense option in the recurring form.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get recurringExpense;

  /// Menu action that edits a recurring item.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get recurringActionEdit;

  /// Menu action that sets a recurring item inactive.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get recurringActionPause;

  /// Menu action that sets a recurring item active.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get recurringActionActivate;

  /// Tooltip of a recurring row's action menu.
  ///
  /// In en, this message translates to:
  /// **'More actions for {name}'**
  String recurringMoreActions(String name);

  /// Title of the confirm dialog for deleting a recurring item.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String recurringDeleteTitle(String name);

  /// Body of the confirm dialog for deleting a recurring item.
  ///
  /// In en, this message translates to:
  /// **'This removes the recurring item. Your past transactions stay as they are.'**
  String get recurringDeleteBody;

  /// Snackbar after deleting a recurring item.
  ///
  /// In en, this message translates to:
  /// **'Recurring item deleted'**
  String get recurringDeleted;

  /// Snackbar after pausing a recurring item.
  ///
  /// In en, this message translates to:
  /// **'{name} paused'**
  String recurringPausedMessage(String name);

  /// Snackbar after activating a recurring item.
  ///
  /// In en, this message translates to:
  /// **'{name} activated'**
  String recurringActivatedMessage(String name);

  /// Snackbar when pausing, activating or deleting a recurring item fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update. Please try again.'**
  String get recurringActionFailed;

  /// Title of the form that adds a recurring item.
  ///
  /// In en, this message translates to:
  /// **'New recurring'**
  String get recurringNewTitle;

  /// Title of the form that edits a recurring item.
  ///
  /// In en, this message translates to:
  /// **'Edit recurring'**
  String get recurringEditTitle;

  /// Recurring form field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get recurringFieldName;

  /// Recurring form field.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get recurringFieldAmount;

  /// Recurring form field: 3-letter currency code.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get recurringFieldCurrency;

  /// Recurring form field: the account it is paid from or into.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get recurringFieldAccount;

  /// Account option meaning the recurring item is not tied to an account.
  ///
  /// In en, this message translates to:
  /// **'No account'**
  String get recurringNoAccount;

  /// Recurring form field.
  ///
  /// In en, this message translates to:
  /// **'Next expected date'**
  String get recurringFieldNextDate;

  /// Recurring form field: when it last happened.
  ///
  /// In en, this message translates to:
  /// **'Last occurrence'**
  String get recurringFieldLastDate;

  /// Recurring form switch: whether the item is expected.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get recurringFieldActive;

  /// Helper under the Active switch in the recurring form.
  ///
  /// In en, this message translates to:
  /// **'Inactive items aren\'t expected or counted in totals'**
  String get recurringFieldActiveHint;

  /// Recurring form switch: the bill is paid automatically.
  ///
  /// In en, this message translates to:
  /// **'Autopay'**
  String get recurringFieldAutopay;

  /// Recurring form field: web address where the bill is paid.
  ///
  /// In en, this message translates to:
  /// **'Payment link'**
  String get recurringFieldPaymentUrl;

  /// Recurring form field.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get recurringFieldNotes;

  /// Note in the add form: the app cannot set a cadence other than monthly.
  ///
  /// In en, this message translates to:
  /// **'New items repeat monthly on the day of the next expected date. Change the schedule on the web.'**
  String get recurringCadenceNote;

  /// Note in the edit form about fields the app cannot change.
  ///
  /// In en, this message translates to:
  /// **'Name, amount, currency, account and schedule can only be changed on the web.'**
  String get recurringLockedNote;

  /// Recurring form validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get recurringErrorNameRequired;

  /// Recurring form validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero'**
  String get recurringErrorAmountInvalid;

  /// Recurring form validation error.
  ///
  /// In en, this message translates to:
  /// **'Use a 3-letter code, like USD'**
  String get recurringErrorCurrencyInvalid;

  /// Recurring form validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter a link starting with http:// or https://'**
  String get recurringErrorUrlInvalid;

  /// Recurring form validation error on the last occurrence date.
  ///
  /// In en, this message translates to:
  /// **'Must be before the next expected date'**
  String get recurringErrorLastAfterNext;

  /// Error when saving a recurring item fails without a server message.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save. Please try again.'**
  String get recurringSaveFailed;

  /// Title of the Home insights card.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insightsTitle;

  /// Button that acknowledges an insight so it stops showing.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get insightsDismiss;

  /// Label on a high-priority insight.
  ///
  /// In en, this message translates to:
  /// **'High priority'**
  String get insightsPriorityHigh;

  /// Accessibility hint for expanding an insight.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get insightsShowDetails;

  /// Accessibility hint for collapsing an insight.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get insightsHideDetails;

  /// Snackbar when acknowledging an insight fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t dismiss the insight'**
  String get insightsDismissFailed;

  /// Title of the Home card comparing this period's spending with normal.
  ///
  /// In en, this message translates to:
  /// **'Spending vs normal'**
  String get spendingVsNormalTitle;

  /// Spending in the unfinished current period.
  ///
  /// In en, this message translates to:
  /// **'{amount} so far'**
  String spendingVsNormalSoFar(String amount);

  /// What is normal to have spent by now.
  ///
  /// In en, this message translates to:
  /// **'Normal {amount}'**
  String spendingVsNormalNormal(String amount);

  /// Overall spending is above normal, e.g. '12% above normal'.
  ///
  /// In en, this message translates to:
  /// **'{percent} above normal'**
  String spendingVsNormalAbove(String percent);

  /// Overall spending is below normal, e.g. '8% below normal'.
  ///
  /// In en, this message translates to:
  /// **'{percent} below normal'**
  String spendingVsNormalBelow(String percent);

  /// A category with spending this period and none normally.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get spendingVsNormalNew;

  /// Expands the spending card to every category.
  ///
  /// In en, this message translates to:
  /// **'Show all categories'**
  String get spendingVsNormalShowAll;

  /// Collapses the spending card.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get spendingVsNormalShowLess;

  /// Category row in the expanded spending card: spent and normal.
  ///
  /// In en, this message translates to:
  /// **'{amount} · normal {normal}'**
  String spendingVsNormalCategoryNormal(String amount, String normal);

  /// Tooltip of the account screen's overflow menu button.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get accountActions;

  /// Menu item and screen title for setting an account's balance on a date.
  ///
  /// In en, this message translates to:
  /// **'Update balance'**
  String get accountActionsUpdateBalance;

  /// Menu item and screen title for recording a buy or sell.
  ///
  /// In en, this message translates to:
  /// **'Add trade'**
  String get accountActionsAddTrade;

  /// Title of the screen that edits an existing buy or sell.
  ///
  /// In en, this message translates to:
  /// **'Edit trade'**
  String get accountActionsEditTrade;

  /// Menu item and dialog title that starts a sync of all accounts.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get accountActionsSyncNow;

  /// Label of a date field in the balance and trade forms.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get accountActionsDate;

  /// Label of the balance field in the Update balance form.
  ///
  /// In en, this message translates to:
  /// **'New balance'**
  String get accountActionsNewBalance;

  /// The account's current balance shown above the Update balance form.
  ///
  /// In en, this message translates to:
  /// **'Current balance: {amount}'**
  String accountActionsCurrentBalance(String amount);

  /// Label of the optional note field in the Update balance form.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get accountActionsNote;

  /// Submit button of the balance and trade forms.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get accountActionsSave;

  /// Validation error for an empty required field.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get accountActionsRequired;

  /// Validation error when the new balance is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the new balance'**
  String get accountActionsBalanceRequired;

  /// Validation error when a number field has no digits.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get accountActionsInvalidNumber;

  /// Validation error for a quantity or price of zero or less.
  ///
  /// In en, this message translates to:
  /// **'Must be greater than zero'**
  String get accountActionsMustBePositive;

  /// Validation error for a negative trade fee.
  ///
  /// In en, this message translates to:
  /// **'Fees can\'t be negative'**
  String get accountActionsFeeInvalid;

  /// Confirmation after the server accepted a new balance.
  ///
  /// In en, this message translates to:
  /// **'Balance updated'**
  String get accountActionsBalanceUpdated;

  /// Trade form segment for a purchase.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get accountActionsBuy;

  /// Trade form segment for a sale.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get accountActionsSell;

  /// Label of the ticker field in the trade form.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get accountActionsSecurity;

  /// Placeholder of the ticker field in the trade form.
  ///
  /// In en, this message translates to:
  /// **'Ticker, e.g. AAPL'**
  String get accountActionsSecurityHint;

  /// Validation error when the trade form's ticker is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a ticker'**
  String get accountActionsSecurityRequired;

  /// Helper under the read-only security field when editing a trade.
  ///
  /// In en, this message translates to:
  /// **'The security and fees can\'t be changed. Delete and re-add the trade instead.'**
  String get accountActionsEditTradeNote;

  /// Label of the share quantity field in the trade form.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get accountActionsQuantity;

  /// Label of the price field in the trade form.
  ///
  /// In en, this message translates to:
  /// **'Price per share'**
  String get accountActionsPrice;

  /// Label of the optional fee field in the trade form.
  ///
  /// In en, this message translates to:
  /// **'Fees (optional)'**
  String get accountActionsFee;

  /// Live total of a buy: quantity times price plus fees.
  ///
  /// In en, this message translates to:
  /// **'Total cost'**
  String get accountActionsTotalCost;

  /// Live total of a sell: quantity times price minus fees.
  ///
  /// In en, this message translates to:
  /// **'Total proceeds'**
  String get accountActionsTotalProceeds;

  /// Confirmation after a trade was created.
  ///
  /// In en, this message translates to:
  /// **'Trade added'**
  String get accountActionsTradeAdded;

  /// Confirmation after a trade was edited.
  ///
  /// In en, this message translates to:
  /// **'Trade updated'**
  String get accountActionsTradeUpdated;

  /// Confirmation after a trade was deleted.
  ///
  /// In en, this message translates to:
  /// **'Trade deleted'**
  String get accountActionsTradeDeleted;

  /// Button tooltip and dialog title for deleting a trade.
  ///
  /// In en, this message translates to:
  /// **'Delete trade'**
  String get accountActionsDeleteTrade;

  /// Confirmation text before deleting a trade.
  ///
  /// In en, this message translates to:
  /// **'Delete this trade? This can\'t be undone.'**
  String get accountActionsDeleteTradeConfirm;

  /// Sync dialog status before the server answered.
  ///
  /// In en, this message translates to:
  /// **'Starting sync...'**
  String get accountActionsSyncStarting;

  /// Sync dialog and status chip text while a sync runs.
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get accountActionsSyncing;

  /// Time since Sync now started, e.g. '0:12 elapsed'.
  ///
  /// In en, this message translates to:
  /// **'{elapsed} elapsed'**
  String accountActionsSyncElapsed(String elapsed);

  /// Sync dialog and status chip text after a successful sync.
  ///
  /// In en, this message translates to:
  /// **'Sync complete'**
  String get accountActionsSyncComplete;

  /// Sync dialog and status chip text after a failed sync.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get accountActionsSyncFailed;

  /// Sync dialog text after a failed sync, with the server's reason.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {message}'**
  String accountActionsSyncFailedDetail(String message);

  /// Sync dialog text when the sync did not finish within two minutes.
  ///
  /// In en, this message translates to:
  /// **'Still syncing after 2 minutes. It will keep running in the background.'**
  String get accountActionsSyncTimeout;

  /// Closes the sync dialog while the sync keeps running.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get accountActionsHide;

  /// Closes the sync dialog after the sync finished.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get accountActionsClose;

  /// Status chip text when the family has never synced.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get accountActionsNeverSynced;

  /// Status chip text for a sync that finished under a minute ago.
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get accountActionsSyncedJustNow;

  /// Status chip text for a sync that finished minutes ago.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}m ago'**
  String accountActionsSyncedMinutesAgo(int count);

  /// Status chip text for a sync that finished hours ago.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}h ago'**
  String accountActionsSyncedHoursAgo(int count);

  /// Status chip text for a sync that finished days ago.
  ///
  /// In en, this message translates to:
  /// **'Synced {count}d ago'**
  String accountActionsSyncedDaysAgo(int count);

  /// Screen reader hint on the sync status chip.
  ///
  /// In en, this message translates to:
  /// **'Starts a sync of all accounts'**
  String get accountActionsSyncChipHint;

  /// Title of the transaction detail and edit screen.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get txnDetail;

  /// Notice on the transaction screen while the device is offline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Changes can be saved once you\'re back online.'**
  String get txnDetailOfflineNote;

  /// Shown under the amount field when the transaction is split.
  ///
  /// In en, this message translates to:
  /// **'Amount, date and type come from the split. Edit the split to change them.'**
  String get txnDetailSplitLockedFields;

  /// Summary of how many tags are selected on the transaction.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tag} other{{count} tags}}'**
  String txnDetailTagCount(int count);

  /// Tooltip for the delete button on a selected tag chip.
  ///
  /// In en, this message translates to:
  /// **'Remove tag'**
  String get txnDetailRemoveTag;

  /// Title of the category picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Choose category'**
  String get txnDetailChooseCategory;

  /// Title of the merchant picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Choose merchant'**
  String get txnDetailChooseMerchant;

  /// Title of the tag picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Choose tags'**
  String get txnDetailChooseTags;

  /// Placeholder of the search field in the picker sheets.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get txnDetailSearchHint;

  /// Picker row that creates a new category, merchant or tag with the searched name.
  ///
  /// In en, this message translates to:
  /// **'Create “{name}”'**
  String txnDetailCreateOption(String name);

  /// Error when creating a category, merchant or tag fails without a server message.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create it. Please try again.'**
  String get txnDetailCreateFailed;

  /// Shown in a picker instead of the create row while offline.
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet to create new items.'**
  String get txnDetailCreateOffline;

  /// Empty state of a picker sheet search.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get txnDetailPickerEmpty;

  /// Button that closes the multi-select tag picker.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get txnDetailDone;

  /// Button that opens the split editor for an unsplit transaction.
  ///
  /// In en, this message translates to:
  /// **'Split transaction'**
  String get txnDetailSplitAction;

  /// Heading of the split section on the transaction screen.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get txnDetailSplitHeading;

  /// Button that opens the split editor for a split transaction.
  ///
  /// In en, this message translates to:
  /// **'Edit split'**
  String get txnDetailEditSplit;

  /// Shown when splitting is unavailable because the device is offline.
  ///
  /// In en, this message translates to:
  /// **'Splits need an internet connection.'**
  String get txnDetailSplitOffline;

  /// Error when the transaction's split could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the split details.'**
  String get txnDetailSplitLoadFailed;

  /// Title of the split editor screen.
  ///
  /// In en, this message translates to:
  /// **'Split transaction'**
  String get txnDetailSplitTitle;

  /// Split editor: the transaction's total that the parts must add up to.
  ///
  /// In en, this message translates to:
  /// **'Total {amount}'**
  String txnDetailSplitTotal(String amount);

  /// Split editor: how much of the total the parts don't cover yet.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {amount}'**
  String txnDetailSplitRemaining(String amount);

  /// Split editor: the parts add up to more than the total.
  ///
  /// In en, this message translates to:
  /// **'Over by {amount}'**
  String txnDetailSplitOver(String amount);

  /// Split editor: the parts match the total exactly.
  ///
  /// In en, this message translates to:
  /// **'The parts add up to the total.'**
  String get txnDetailSplitBalanced;

  /// Split editor: explains the sign of part amounts.
  ///
  /// In en, this message translates to:
  /// **'Positive amounts go the same way as the total; use a negative amount for a part that goes the other way.'**
  String get txnDetailSplitSignHint;

  /// Split editor: heading of one part.
  ///
  /// In en, this message translates to:
  /// **'Part {number}'**
  String txnDetailSplitPartLabel(int number);

  /// Tooltip for the button that removes a part in the split editor.
  ///
  /// In en, this message translates to:
  /// **'Remove part'**
  String get txnDetailSplitRemoveRow;

  /// Label of a split part's name field; empty uses the transaction's name.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get txnDetailSplitRowName;

  /// Validation error for a split part's amount.
  ///
  /// In en, this message translates to:
  /// **'Enter a nonzero amount with at most 4 decimals.'**
  String get txnDetailSplitInvalidAmount;

  /// Tooltip for the button that fills a part with what is left of the total.
  ///
  /// In en, this message translates to:
  /// **'Use remaining amount'**
  String get txnDetailSplitUseRemaining;

  /// Button that adds a part to the split.
  ///
  /// In en, this message translates to:
  /// **'Add part'**
  String get txnDetailSplitAddRow;

  /// Split editor: a split needs two or more parts.
  ///
  /// In en, this message translates to:
  /// **'Add at least two parts.'**
  String get txnDetailSplitNeedTwo;

  /// Button that saves the split.
  ///
  /// In en, this message translates to:
  /// **'Save split'**
  String get txnDetailSplitSave;

  /// Button that removes the split and restores the original transaction.
  ///
  /// In en, this message translates to:
  /// **'Remove split'**
  String get txnDetailSplitRemove;

  /// Title of the confirmation dialog for removing a split.
  ///
  /// In en, this message translates to:
  /// **'Remove split?'**
  String get txnDetailSplitRemoveConfirmTitle;

  /// Body of the confirmation dialog for removing a split.
  ///
  /// In en, this message translates to:
  /// **'The parts are deleted and the original transaction counts again.'**
  String get txnDetailSplitRemoveConfirmBody;

  /// Snackbar after the split was saved.
  ///
  /// In en, this message translates to:
  /// **'Split saved'**
  String get txnDetailSplitSaved;

  /// Snackbar after the split was removed.
  ///
  /// In en, this message translates to:
  /// **'Split removed'**
  String get txnDetailSplitRemoved;

  /// Tags row value on the transaction editor when the transaction has none.
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get txnDetailNoTags;

  /// Feature name for the CSV import and statement upload screens.
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get dataIn;

  /// App bar title of the CSV import screen.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataInImportTitle;

  /// Header of the list of past imports.
  ///
  /// In en, this message translates to:
  /// **'Import history'**
  String get dataInHistoryHeader;

  /// Shown when the import history is empty.
  ///
  /// In en, this message translates to:
  /// **'No imports yet.'**
  String get dataInHistoryEmpty;

  /// Error when the import history fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load import history.'**
  String get dataInHistoryFailed;

  /// Button that retries loading.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get dataInRetry;

  /// Button that reloads an import's status.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get dataInRefresh;

  /// Number of rows in an import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row} other{{count} rows}}'**
  String dataInRowCount(int count);

  /// Number of invalid rows in an import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row has errors} other{{count} rows have errors}}'**
  String dataInInvalidRowCount(int count);

  /// Label before an import's status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get dataInStatusLabel;

  /// Label before an import's creation date.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get dataInCreatedLabel;

  /// Error in the import status sheet.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh the status.'**
  String get dataInStatusLoadFailed;

  /// Import status pending.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get dataInStatusPending;

  /// Import status importing.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get dataInStatusImporting;

  /// Import status complete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get dataInStatusComplete;

  /// Import status failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get dataInStatusFailed;

  /// Import status reverting.
  ///
  /// In en, this message translates to:
  /// **'Reverting…'**
  String get dataInStatusReverting;

  /// Import status revert_failed.
  ///
  /// In en, this message translates to:
  /// **'Revert failed'**
  String get dataInStatusRevertFailed;

  /// Import type TransactionImport.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get dataInTypeTransactions;

  /// Import type TradeImport.
  ///
  /// In en, this message translates to:
  /// **'Trades'**
  String get dataInTypeTrades;

  /// Import type AccountImport.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get dataInTypeAccounts;

  /// Heading of the current import wizard step.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}: {title}'**
  String dataInStepOf(int step, int total, String title);

  /// Import wizard step 1 title.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get dataInStepFile;

  /// Import wizard step 2 title.
  ///
  /// In en, this message translates to:
  /// **'Map columns'**
  String get dataInStepMap;

  /// Import wizard step 3 title.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get dataInStepPreview;

  /// Import wizard step 4 title.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataInStepPublish;

  /// Help text on the choose-file step.
  ///
  /// In en, this message translates to:
  /// **'Import transactions from a CSV file into one account. Files can be up to {size}.'**
  String dataInFileHelp(String size);

  /// Label of the account picker.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get dataInAccountLabel;

  /// Shown when the user has no accounts to import into.
  ///
  /// In en, this message translates to:
  /// **'Add an account first.'**
  String get dataInNoAccounts;

  /// Button that opens the file picker for a CSV.
  ///
  /// In en, this message translates to:
  /// **'Choose CSV file'**
  String get dataInChooseCsv;

  /// Button that opens the file picker for a statement.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get dataInChooseFile;

  /// Button that replaces the picked file.
  ///
  /// In en, this message translates to:
  /// **'Change file'**
  String get dataInChooseAnother;

  /// Error when the picked file is not a CSV.
  ///
  /// In en, this message translates to:
  /// **'Choose a file that ends in .csv.'**
  String get dataInNotCsv;

  /// Error when the picked file has no content.
  ///
  /// In en, this message translates to:
  /// **'This file is empty.'**
  String get dataInFileEmpty;

  /// Error when the picked file is over the server's limit.
  ///
  /// In en, this message translates to:
  /// **'This file is too large. The limit is {size}.'**
  String dataInFileTooLarge(String size);

  /// Error when the picked file can't be read.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read the file.'**
  String get dataInReadFailed;

  /// Button that goes to the next wizard step.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get dataInContinue;

  /// Button that goes to the previous wizard step.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get dataInBack;

  /// What preflight found in the CSV.
  ///
  /// In en, this message translates to:
  /// **'Found {columns, plural, =1{1 column} other{{columns} columns}} and {rows, plural, =1{1 row} other{{rows} rows}}.'**
  String dataInDetected(int columns, int rows);

  /// Label of a required column picker.
  ///
  /// In en, this message translates to:
  /// **'{label} (required)'**
  String dataInRequiredLabel(String label);

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Date column'**
  String get dataInColumnDate;

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Amount column'**
  String get dataInColumnAmount;

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Name column'**
  String get dataInColumnName;

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Category column'**
  String get dataInColumnCategory;

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Tags column'**
  String get dataInColumnTags;

  /// Column picker label.
  ///
  /// In en, this message translates to:
  /// **'Notes column'**
  String get dataInColumnNotes;

  /// Column picker option for not using a column.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dataInColumnNone;

  /// Picker label.
  ///
  /// In en, this message translates to:
  /// **'Date format'**
  String get dataInDateFormat;

  /// Picker label.
  ///
  /// In en, this message translates to:
  /// **'Number format'**
  String get dataInNumberFormat;

  /// Picker label for the signage convention.
  ///
  /// In en, this message translates to:
  /// **'Amount signs'**
  String get dataInSignage;

  /// Signage option inflows_positive.
  ///
  /// In en, this message translates to:
  /// **'Income is positive'**
  String get dataInSignagePositive;

  /// Signage option inflows_negative.
  ///
  /// In en, this message translates to:
  /// **'Income is negative'**
  String get dataInSignageNegative;

  /// Picker label for col_sep.
  ///
  /// In en, this message translates to:
  /// **'Column separator'**
  String get dataInSeparator;

  /// Column separator option.
  ///
  /// In en, this message translates to:
  /// **'Comma (,)'**
  String get dataInSeparatorComma;

  /// Column separator option.
  ///
  /// In en, this message translates to:
  /// **'Semicolon (;)'**
  String get dataInSeparatorSemicolon;

  /// Shown until both required columns are mapped.
  ///
  /// In en, this message translates to:
  /// **'Choose the date and amount columns to continue.'**
  String get dataInNeedDateAndAmount;

  /// Preview step summary.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} rows.'**
  String dataInPreviewSummary(int shown, int total);

  /// Preview warning about invalid rows.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 row doesn\'t match the chosen formats.} other{{count} rows don\'t match the chosen formats.}}'**
  String dataInPreviewInvalid(int count);

  /// Warning on the preview when category or tags columns are mapped.
  ///
  /// In en, this message translates to:
  /// **'Categories and tags from the file may not be applied when importing from the app. You can set them on the web.'**
  String get dataInCategoriesNote;

  /// Preview with no data rows.
  ///
  /// In en, this message translates to:
  /// **'No rows to import.'**
  String get dataInPreviewEmpty;

  /// Preview row without a name.
  ///
  /// In en, this message translates to:
  /// **'(no name)'**
  String get dataInRowUntitled;

  /// Preview row error.
  ///
  /// In en, this message translates to:
  /// **'Date \"{value}\" doesn\'t match the date format.'**
  String dataInRowBadDate(String value);

  /// Preview row error.
  ///
  /// In en, this message translates to:
  /// **'Amount \"{value}\" isn\'t a number.'**
  String dataInRowBadAmount(String value);

  /// Button that starts the import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get dataInPublish;

  /// Shown while the import is created.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get dataInUploading;

  /// Shown when the import finished.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get dataInComplete;

  /// Shown when polling stopped after two minutes.
  ///
  /// In en, this message translates to:
  /// **'The import is still running. Check its status in the import history.'**
  String get dataInStillRunning;

  /// Button that stops watching the import.
  ///
  /// In en, this message translates to:
  /// **'Keep running in background'**
  String get dataInKeepInBackground;

  /// Snackbar after choosing to keep the import running in the background.
  ///
  /// In en, this message translates to:
  /// **'The import keeps running. Its status is in the import history.'**
  String get dataInRunningInBackground;

  /// Header above row errors after a failed import.
  ///
  /// In en, this message translates to:
  /// **'Rows the server rejected'**
  String get dataInRejectedRows;

  /// Button that resets the import wizard.
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get dataInStartOver;

  /// Button after an import finished.
  ///
  /// In en, this message translates to:
  /// **'Import another file'**
  String get dataInImportAnother;

  /// Link to the web import page.
  ///
  /// In en, this message translates to:
  /// **'More import types on the web'**
  String get dataInMoreTypesOnWeb;

  /// App bar title of the statement upload screen.
  ///
  /// In en, this message translates to:
  /// **'Upload statement'**
  String get dataInStatementTitle;

  /// Help text on the statement upload screen.
  ///
  /// In en, this message translates to:
  /// **'Add a PDF, CSV or XLSX statement to the Statement Vault. Files can be up to {size}.'**
  String dataInStatementHelp(String size);

  /// Error when the picked statement has another type.
  ///
  /// In en, this message translates to:
  /// **'Choose a PDF, CSV or XLSX file.'**
  String get dataInStatementWrongType;

  /// Button that uploads the statement.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get dataInUpload;

  /// Shown after a statement upload succeeded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded {name}.'**
  String dataInStatementUploaded(String name);

  /// Link to the web statements page.
  ///
  /// In en, this message translates to:
  /// **'View statements on the web'**
  String get dataInStatementViewOnWeb;

  /// Shown when the statement was uploaded before.
  ///
  /// In en, this message translates to:
  /// **'Already uploaded on {date}.'**
  String dataInStatementDuplicate(String date);

  /// Shown when the statement is a duplicate the user can't see.
  ///
  /// In en, this message translates to:
  /// **'This file is already in the Statement Vault.'**
  String get dataInStatementDuplicateHidden;

  /// Fallback upload error.
  ///
  /// In en, this message translates to:
  /// **'The statement couldn\'t be uploaded.'**
  String get dataInStatementFailed;

  /// Shown before an account is picked.
  ///
  /// In en, this message translates to:
  /// **'Choose an account to see its statements.'**
  String get dataInStatementPickAccount;

  /// Error when the statement list fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load statements.'**
  String get dataInStatementListFailed;

  /// Empty statement list.
  ///
  /// In en, this message translates to:
  /// **'No statements for this account yet.'**
  String get dataInStatementListEmpty;

  /// Header of the statement list.
  ///
  /// In en, this message translates to:
  /// **'Recent statements'**
  String get dataInStatementRecent;

  /// A statement's period.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String dataInStatementPeriod(String start, String end);

  /// When a statement was uploaded.
  ///
  /// In en, this message translates to:
  /// **'Added {date}'**
  String dataInStatementAdded(String date);

  /// Start of the categories, tags, merchants and export block. Generic label for managing data.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// Hint of the search field on the categories, tags and merchants screens.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get manageSearch;

  /// Tooltip of the button that clears the search field.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get manageClearSearch;

  /// Shown when a search finds nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”.'**
  String manageNoMatches(String query);

  /// Label of the name field in the create and edit forms.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get manageNameLabel;

  /// Validation error when the name field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get manageNameRequired;

  /// Heading of the color swatch picker.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get manageColor;

  /// Screen reader label of one color swatch.
  ///
  /// In en, this message translates to:
  /// **'Color {number}'**
  String manageColorOption(int number);

  /// Swatch that lets the server pick a color.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get manageColorAutomatic;

  /// Button that opens the web page where an item can be edited.
  ///
  /// In en, this message translates to:
  /// **'Edit on the web'**
  String get manageEditOnWeb;

  /// Generic error after a failed create, save or delete.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get manageActionFailed;

  /// Title of the categories screen.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get manageCategoriesTitle;

  /// Title of the empty state on the categories screen.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get manageCategoriesEmpty;

  /// Body of the empty state on the categories screen.
  ///
  /// In en, this message translates to:
  /// **'Add one with +. Categories sort your spending and income.'**
  String get manageCategoriesEmptyBody;

  /// Error when the category list can't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load categories.'**
  String get manageCategoriesLoadFailed;

  /// Tooltip of the + button on the categories screen.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get manageCategoryAdd;

  /// Title of the create category form.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get manageCategoryNew;

  /// Label of the optional parent picker in the create category form.
  ///
  /// In en, this message translates to:
  /// **'Parent category'**
  String get manageCategoryParent;

  /// Parent picker option for a top-level category.
  ///
  /// In en, this message translates to:
  /// **'None (top level)'**
  String get manageCategoryNoParent;

  /// Note in the create category form explaining the icon.
  ///
  /// In en, this message translates to:
  /// **'Sure picks an icon that fits the name. You can change it on the web.'**
  String get manageCategoryIconHint;

  /// Snackbar after a category was created.
  ///
  /// In en, this message translates to:
  /// **'Category “{name}” added'**
  String manageCategoryCreated(String name);

  /// Subcategory count in the category info sheet.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No subcategories} =1{1 subcategory} other{{count} subcategories}}'**
  String manageCategorySubcategories(int count);

  /// Category info sheet: the parent of a subcategory.
  ///
  /// In en, this message translates to:
  /// **'Subcategory of {parent}'**
  String manageCategoryInParent(String parent);

  /// Category info sheet: explains that editing happens on the web.
  ///
  /// In en, this message translates to:
  /// **'Rename, recolor, change the icon of, merge or delete categories on the web.'**
  String get manageCategoryInfoBody;

  /// Title of the tags screen.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get manageTagsTitle;

  /// Title of the empty state on the tags screen.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get manageTagsEmpty;

  /// Body of the empty state on the tags screen.
  ///
  /// In en, this message translates to:
  /// **'Tags group transactions across categories, like a trip or a project.'**
  String get manageTagsEmptyBody;

  /// Error when the tag list can't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load tags.'**
  String get manageTagsLoadFailed;

  /// Tooltip of the + button on the tags screen.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get manageTagAdd;

  /// Title of the create tag form.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get manageTagNew;

  /// Title of the edit tag form.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get manageTagEdit;

  /// Snackbar after a tag was created.
  ///
  /// In en, this message translates to:
  /// **'Tag “{name}” added'**
  String manageTagCreated(String name);

  /// Snackbar after a tag was renamed or recolored.
  ///
  /// In en, this message translates to:
  /// **'Tag saved'**
  String get manageTagSaved;

  /// Snackbar after a tag was deleted.
  ///
  /// In en, this message translates to:
  /// **'Tag deleted'**
  String get manageTagDeleted;

  /// Button in the edit tag form that deletes the tag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get manageTagDelete;

  /// Title of the delete tag confirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String manageTagDeleteTitle(String name);

  /// Body of the delete tag confirmation.
  ///
  /// In en, this message translates to:
  /// **'The tag is removed from every transaction that has it. This can\'t be undone.'**
  String get manageTagDeleteBody;

  /// Title of the merchants screen.
  ///
  /// In en, this message translates to:
  /// **'Merchants'**
  String get manageMerchantsTitle;

  /// Title of the empty state on the merchants screen.
  ///
  /// In en, this message translates to:
  /// **'No merchants yet'**
  String get manageMerchantsEmpty;

  /// Body of the empty state on the merchants screen.
  ///
  /// In en, this message translates to:
  /// **'Merchants you add, and the ones your bank connections find, show up here.'**
  String get manageMerchantsEmptyBody;

  /// Error when the merchant list can't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load merchants.'**
  String get manageMerchantsLoadFailed;

  /// Tooltip of the + button on the merchants screen.
  ///
  /// In en, this message translates to:
  /// **'Add merchant'**
  String get manageMerchantAdd;

  /// Title of the create merchant form.
  ///
  /// In en, this message translates to:
  /// **'New merchant'**
  String get manageMerchantNew;

  /// Label of the website field in the create merchant form.
  ///
  /// In en, this message translates to:
  /// **'Website (optional)'**
  String get manageMerchantWebsite;

  /// Validation error for the merchant website field.
  ///
  /// In en, this message translates to:
  /// **'Enter a web address like example.com.'**
  String get manageMerchantWebsiteInvalid;

  /// Snackbar after a merchant was created.
  ///
  /// In en, this message translates to:
  /// **'Merchant “{name}” added'**
  String manageMerchantCreated(String name);

  /// Snackbar when a merchant with that name already exists.
  ///
  /// In en, this message translates to:
  /// **'“{name}” already exists'**
  String manageMerchantExists(String name);

  /// Subtitle of a merchant the family created.
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get manageMerchantFamily;

  /// Subtitle of a merchant that came from a bank connection.
  ///
  /// In en, this message translates to:
  /// **'From a bank connection'**
  String get manageMerchantProvider;

  /// Merchant info sheet: explains that editing happens on the web.
  ///
  /// In en, this message translates to:
  /// **'Rename, recolor, set the website or logo of, merge or delete merchants on the web.'**
  String get manageMerchantInfoBody;

  /// Title of the data export screen.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get manageExportTitle;

  /// Explains what a data export contains.
  ///
  /// In en, this message translates to:
  /// **'An export is a ZIP file with your accounts, transactions, trades, categories, merchants and rules as CSV files, plus all of it in one all.ndjson file. Attachments are listed but their files aren\'t included.'**
  String get manageExportIntro;

  /// Button that starts a new data export.
  ///
  /// In en, this message translates to:
  /// **'Create export'**
  String get manageExportCreate;

  /// Snackbar after an export was started.
  ///
  /// In en, this message translates to:
  /// **'Export started. It can take a few minutes.'**
  String get manageExportStarted;

  /// Heading of the list of past exports.
  ///
  /// In en, this message translates to:
  /// **'Exports'**
  String get manageExportHistory;

  /// Shown when there are no exports.
  ///
  /// In en, this message translates to:
  /// **'No exports yet. Create one to get a copy of your data.'**
  String get manageExportEmpty;

  /// Error when the export list can't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load exports.'**
  String get manageExportLoadFailed;

  /// Shown when a non-admin opens the export screen.
  ///
  /// In en, this message translates to:
  /// **'Only a family admin can export data.'**
  String get manageExportAdminOnly;

  /// Status of an export that hasn't started.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get manageExportStatusPending;

  /// Status of an export being built.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get manageExportStatusProcessing;

  /// Status of a finished export.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get manageExportStatusCompleted;

  /// Status of an export that failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get manageExportStatusFailed;

  /// Button that downloads a finished export and opens the share sheet.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get manageExportDownload;

  /// Snackbar when downloading an export failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the export.'**
  String get manageExportDownloadFailed;

  /// Shown when the app stopped checking an export that is taking long.
  ///
  /// In en, this message translates to:
  /// **'Still preparing. Pull down to check again.'**
  String get manageExportStillPreparing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'sv'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'sv':
      return AppLocalizationsSv();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
