// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swedish (`sv`).
class AppLocalizationsSv extends AppLocalizations {
  AppLocalizationsSv([String locale = 'sv']) : super(locale);

  @override
  String get appTitle => 'Sure Finances';

  @override
  String get commonCancel => 'Avbryt';

  @override
  String get commonSave => 'Spara';

  @override
  String get commonTryAgain => 'Försök igen';

  @override
  String get commonDelete => 'Radera';

  @override
  String get commonAll => 'Alla';

  @override
  String get commonClose => 'Stäng';

  @override
  String get commonUndo => 'Ångra';

  @override
  String get chatSuggestionNetWorth => 'Vad är min nettoförmögenhet just nu?';

  @override
  String get chatSuggestionSpending =>
      'Hur har mina utgifter förändrats den här månaden?';

  @override
  String get chatSuggestionSavings => 'Hur kan jag öka min sparkvot?';

  @override
  String get chatSuggestionExpenses =>
      'Vilka är mina största utgifter på sistone?';

  @override
  String get loginEmailLabel => 'E-post';

  @override
  String get loginEmailRequired => 'E-post krävs';

  @override
  String get loginEmailInvalid => 'Ange en giltig e-postadress';

  @override
  String get loginPasswordLabel => 'Lösenord';

  @override
  String get loginPasswordRequired => 'Lösenord krävs';

  @override
  String get loginSignIn => 'Logga in';

  @override
  String get loginSignInWithGoogle => 'Logga in med Google';

  @override
  String get loginMfaLabel => 'Autentiseringskod';

  @override
  String get loginApiKeyLabel => 'API-nyckel';

  @override
  String get navHome => 'Hem';

  @override
  String get navIntro => 'Intro';

  @override
  String get navAssistant => 'Assistent';

  @override
  String get dashboardSyncError => 'Synkningen misslyckades';

  @override
  String get dashboardSyncFailed => 'Synkningen misslyckades. Försök igen.';

  @override
  String get dashboardRefreshing => 'Uppdaterar konton…';

  @override
  String get dashboardAccountsUpdated => 'Kontona har uppdaterats';

  @override
  String get dashboardSyncing => 'Synkar data från servern…';

  @override
  String get dashboardSynced => 'Synkat';

  @override
  String get dashboardErrorLoadingAccounts =>
      'Det gick inte att läsa in konton';

  @override
  String get dashboardNoAccounts => 'Inga konton än';

  @override
  String get chatListTitle => 'Chattar';

  @override
  String get chatListNewChat => 'Ny chatt';

  @override
  String get chatListEmpty => 'Inga chattar än';

  @override
  String get chatListEmptySubtitle =>
      'Starta en konversation med din AI-assistent';

  @override
  String get chatListDeleteTitle => 'Radera chatt';

  @override
  String get chatConversationNewTitle => 'Ny konversation';

  @override
  String get chatConversationMessageHint =>
      'Fråga vad som helst om din ekonomi…';

  @override
  String chatConversationGreetingWithName(String firstName) {
    return 'Hej $firstName, vad kan jag hjälpa dig med?';
  }

  @override
  String get chatConversationGreetingNoName =>
      'Hej, vad kan jag hjälpa dig med?';

  @override
  String get transactionFormNewTitle => 'Ny transaktion';

  @override
  String get transactionFormTypeLabel => 'Typ';

  @override
  String get transactionFormTypeExpense => 'Utgift';

  @override
  String get transactionFormTypeIncome => 'Inkomst';

  @override
  String get transactionFormAmountLabel => 'Belopp';

  @override
  String get transactionFormDateLabel => 'Datum';

  @override
  String get transactionFormNameLabel => 'Namn';

  @override
  String get transactionFormCategoryLabel => 'Kategori';

  @override
  String get transactionEditNameLabel => 'Namn';

  @override
  String get transactionEditNameRequired => 'Namn krävs';

  @override
  String get transactionEditCategoryLabel => 'Kategori';

  @override
  String get transactionEditMerchantLabel => 'Handlare';

  @override
  String get transactionEditTagsLabel => 'Taggar';

  @override
  String get transactionsListDeleteTitle => 'Radera transaktion';

  @override
  String transactionsListDeleteSingleContent(String name) {
    return 'Vill du verkligen radera \"$name\"?';
  }

  @override
  String get transactionsListDeleteMultiTitle => 'Radera transaktioner';

  @override
  String get transactionsListDeleteMultiContent =>
      'Vill du verkligen radera de valda transaktionerna?';

  @override
  String get transactionsListAuthFailed =>
      'Autentiseringen misslyckades: logga in igen';

  @override
  String get transactionsListNoTransactionsYet => 'Inga transaktioner än';

  @override
  String get transactionsListEmptyAddFirst =>
      'Tryck på + för att lägga till din första transaktion';

  @override
  String get transactionsListNoCategoryMatch =>
      'Inga transaktioner matchar den här kategorin';

  @override
  String get transactionsListRetry => 'Försök igen';

  @override
  String get transactionsListDeletedSuccess => 'Transaktionen har raderats';

  @override
  String get transactionsListSingleDeleteFailed =>
      'Det gick inte att radera transaktionen';

  @override
  String transactionsListDeletedMulti(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Raderade $count transaktioner',
      one: 'Raderade $count transaktion',
    );
    return '$_temp0';
  }

  @override
  String get transactionsListDeleteFailed =>
      'Det gick inte att radera transaktionerna';

  @override
  String get transactionsListDeleteNoToken =>
      'Det gick inte att radera: ingen åtkomsttoken';

  @override
  String get transactionsListUndoTitle => 'Ångra transaktion';

  @override
  String get transactionsListUndoRemovePending =>
      'Ta bort den här väntande transaktionen?';

  @override
  String get transactionsListUndoRestoreConfirm =>
      'Återställa den här transaktionen?';

  @override
  String get transactionsListUndoPendingRemoved =>
      'Den väntande transaktionen har tagits bort';

  @override
  String get transactionsListUndoRestored => 'Transaktionen har återställts';

  @override
  String get transactionsListUndoFailed =>
      'Det gick inte att ångra transaktionen';

  @override
  String get settingsSectionDisplay => 'Visning';

  @override
  String get settingsSectionSecurity => 'Säkerhet';

  @override
  String get settingsThemeLabel => 'Tema';

  @override
  String get settingsThemeLight => 'Ljust';

  @override
  String get settingsThemeDark => 'Mörkt';

  @override
  String get settingsPrivacyHideAmountsLabel => 'Dölj belopp';

  @override
  String get settingsUpdateAvailableTitle => 'Uppdatering tillgänglig';

  @override
  String settingsUpdateAvailableContent(String version) {
    return 'Version $version finns tillgänglig. Vill du uppdatera nu?';
  }

  @override
  String get settingsUpdateNewerVersionFallback => 'en nyare version';

  @override
  String get settingsUpdateNow => 'Uppdatera nu';

  @override
  String get settingsNoUpdateAvailable => 'Du har den senaste versionen.';

  @override
  String get settingsUpdateError =>
      'Det gick inte att söka efter uppdateringar.';

  @override
  String get settingsClearDataTitle => 'Rensa all data';

  @override
  String get settingsClearDataContent =>
      'Detta tar bort all lokalt cachad data. Din data på servern påverkas inte.';

  @override
  String get settingsClearData => 'Rensa data';

  @override
  String get settingsDeleteAccountTitle => 'Radera användarkonto';

  @override
  String get settingsDeleteAccount => 'Radera användarkonto';

  @override
  String get settingsSignOutTitle => 'Logga ut';

  @override
  String get settingsSignOutContent => 'Vill du verkligen logga ut?';

  @override
  String get settingsSignOut => 'Logga ut';

  @override
  String get ssoOnboardingTitle => 'Koppla ditt användarkonto';

  @override
  String get ssoOnboardingTabLink => 'Koppla befintligt';

  @override
  String get ssoOnboardingTabCreate => 'Skapa nytt';

  @override
  String get ssoOnboardingFirstNameLabel => 'Förnamn';

  @override
  String get ssoOnboardingLastNameLabel => 'Efternamn';

  @override
  String get ssoOnboardingLinkButton => 'Koppla användarkonto';

  @override
  String get ssoOnboardingCreateButton => 'Skapa användarkonto';

  @override
  String get ssoOnboardingAcceptInvitation => 'Acceptera inbjudan';

  @override
  String get calendarTitle => 'Kontokalender';

  @override
  String get calendarAccountTypeSection => 'Kontotyp';

  @override
  String get calendarSegmentAssets => 'Tillgångar';

  @override
  String get calendarSegmentLiabilities => 'Skulder';

  @override
  String get calendarSelectAccount => 'Välj konto';

  @override
  String get calendarMonthlyChange => 'Månadsförändring';

  @override
  String get calendarNoTransactions => 'Inga transaktioner den här dagen';

  @override
  String get moreCalendar => 'Kontokalender';

  @override
  String get moreCalendarSubtitle => 'Se månatliga saldoförändringar per konto';

  @override
  String get moreRecentTransactions => 'Senaste transaktioner';

  @override
  String get moreRecentTransactionsSubtitle =>
      'Se de senaste transaktionerna för alla konton';

  @override
  String get biometricTitle => 'Appen är låst';

  @override
  String get biometricSubtitle => 'Autentisera dig för att fortsätta';

  @override
  String get biometricUnlock => 'Lås upp';

  @override
  String get biometricAuthenticating => 'Autentiserar…';

  @override
  String get biometricLogOut => 'Logga ut';

  @override
  String get backendConfigTitle => 'Konfiguration';

  @override
  String get backendConfigSubtitle => 'Uppdatera adressen till din Sure-server';

  @override
  String get backendConfigExampleUrlsLabel => 'Exempeladresser';

  @override
  String get backendConfigUrlLabel => 'Adress till Sure-servern';

  @override
  String get backendConfigUrlHint => 'https://app.sure.am';

  @override
  String get backendConfigProxyHeadersLabel => 'Anpassade proxyheaders';

  @override
  String get backendConfigProxyHeadersSubtitle =>
      'Valfria headers för en omvänd proxy eller autentiseringsgateway';

  @override
  String backendConfigProxyHeadersCount(int count) {
    return '$count konfigurerade';
  }

  @override
  String get backendConfigTesting => 'Testar…';

  @override
  String get backendConfigTestButton => 'Testa anslutningen';

  @override
  String get backendConfigContinueButton => 'Fortsätt';

  @override
  String get backendConfigChangeHint =>
      'Du kan ändra detta senare i inställningarna.';

  @override
  String get recentTransactionsTitle => 'Senaste transaktioner';

  @override
  String get recentTransactionsEmpty => 'Inga transaktioner';

  @override
  String get recentTransactionsDisplayLimit => 'Visningsgräns';

  @override
  String recentTransactionsShowN(int count) {
    return 'Visa $count';
  }

  @override
  String get recentTransactionsPullToRefresh => 'Dra nedåt för att uppdatera';

  @override
  String get logViewerTitle => 'Felsökningsloggar';

  @override
  String get logViewerFilterAll => 'Alla';

  @override
  String get logViewerFilterInfo => 'Info';

  @override
  String get logViewerFilterWarning => 'Varning';

  @override
  String get logViewerFilterError => 'Fel';

  @override
  String get logViewerFilterDebug => 'Felsökning';

  @override
  String get logViewerAutoScrollEnable => 'Aktivera automatisk rullning';

  @override
  String get logViewerAutoScrollDisable => 'Inaktivera automatisk rullning';

  @override
  String get logViewerCopyLogs => 'Kopiera loggar';

  @override
  String get logViewerClearLogs => 'Rensa loggar';

  @override
  String get logViewerLogsCopied => 'Loggarna har kopierats till urklipp';

  @override
  String get logViewerEmpty => 'Inga loggar än';

  @override
  String connectivityPendingSync(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transaktioner väntar på synkning',
      one: '$count transaktion väntar på synkning',
    );
    return '$_temp0';
  }

  @override
  String get connectivitySyncNow => 'Synka nu';

  @override
  String get proxyHeadersAddHeader => 'Lägg till header';

  @override
  String get proxyHeadersNameLabel => 'Headernamn';

  @override
  String get proxyHeadersNameHint => 'X-Auth-Token';

  @override
  String get proxyHeadersValueLabel => 'Headervärde';

  @override
  String get proxyHeadersRemove => 'Ta bort header';

  @override
  String get accountDetailHoldingFallback => 'Innehav';

  @override
  String accountDetailCashChip(String amount) {
    return 'Kontanter $amount';
  }

  @override
  String get biometricLockFailedRetry =>
      'Autentiseringen misslyckades. Tryck på Lås upp för att försöka igen.';

  @override
  String get settingsBiometricVerifyReason =>
      'Verifiera med biometri för att aktivera applåset';

  @override
  String get settingsBiometricFailed =>
      'Den biometriska autentiseringen misslyckades.';

  @override
  String get settingsUpdateOpenStoreError =>
      'Det gick inte att öppna länken till butiken';

  @override
  String get settingsClearDataFailed => 'Det gick inte att rensa lokal data.';

  @override
  String get settingsClearDataSuccessDetailed =>
      'Lokal data har rensats. Dra nedåt för att synka från servern.';

  @override
  String get settingsContactOpenLinkError => 'Det gick inte att öppna länken';

  @override
  String get settingsResetAccountContent =>
      'Om du återställer ditt användarkonto raderas alla dina konton, kategorier, handlare, taggar och annan data, men själva användarkontot finns kvar.\n\nDet går inte att ångra. Är du säker?';

  @override
  String get settingsResetAccount => 'Återställ användarkonto';

  @override
  String get settingsResetAccountInitiated =>
      'Återställningen har startats. Det kan ta en stund.';

  @override
  String get settingsResetAccountFailed =>
      'Det gick inte att återställa användarkontot';

  @override
  String get settingsDeleteAccountConfirmContent =>
      'Om du raderar ditt användarkonto tas all din data bort permanent. Det går inte att ångra.\n\nVill du verkligen radera ditt användarkonto?';

  @override
  String get settingsDeleteAccountFailed =>
      'Det gick inte att radera användarkontot';

  @override
  String get settingsProxyHeadersNote =>
      'Headers skickas av appen med API-anrop. SSO-sidor i extern webbläsare får dem kanske inte.';

  @override
  String get settingsProxyHeadersSaved => 'Anpassade proxyheaders har sparats';

  @override
  String get settingsProxyHeadersSaveFailed =>
      'Det gick inte att spara anpassade proxyheaders.';

  @override
  String get settingsContactUs => 'Kontakta oss';

  @override
  String get settingsProxyHeadersTileTitle => 'Anpassade proxyheaders';

  @override
  String settingsProxyHeadersTileSubtitleCount(int count) {
    return '$count konfigurerade';
  }

  @override
  String get settingsClearDataTileSubtitle =>
      'Ta bort alla cachade transaktioner och konton';

  @override
  String get settingsResetAccountTileSubtitle =>
      'Radera alla konton, kategorier, handlare och taggar men behåll ditt användarkonto';

  @override
  String get settingsDeleteAccountTileSubtitle =>
      'Ta bort all din data permanent. Det går inte att ångra.';

  @override
  String get settingsUserFallback => 'Användare';

  @override
  String chatListDeleteMultiContent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Radera $count chattar? Det går inte att ångra.',
      one: 'Radera $count chatt? Det går inte att ångra.',
    );
    return '$_temp0';
  }

  @override
  String get chatListDeletedSuccess => 'Chattarna har raderats';

  @override
  String get chatListDeleteFailed => 'Det gick inte att radera chattarna';

  @override
  String get chatListIncomplete =>
      'Vissa chattar kan saknas. Listan lästes inte in helt.';

  @override
  String get chatListError => 'Det gick inte att läsa in chattar';

  @override
  String get chatListJustNow => 'Nyss';

  @override
  String chatListDeleteSingleContent(String title) {
    return 'Vill du verkligen radera \"$title\"?';
  }

  @override
  String get loginSignUpOpenError =>
      'Det gick inte att öppna registreringssidan';

  @override
  String get loginApiKeyDialogTitle => 'Inloggning med API-nyckel';

  @override
  String get loginApiKeyDialogBody => 'Ange din API-nyckel för att logga in.';

  @override
  String get loginApiKeyInvalid => 'Ogiltig API-nyckel';

  @override
  String get loginApiKeySignIn => 'Logga in';

  @override
  String get loginDemoOrSignUpPrefix => 'Demokonto eller ';

  @override
  String get loginSignUpLink => 'Registrera dig';

  @override
  String get loginSignUpSuffix => '!';

  @override
  String get loginMfaInfo =>
      'Tvåfaktorsautentisering är aktiverad. Ange din kod.';

  @override
  String get loginMfaCodeRequired => 'Ange din autentiseringskod';

  @override
  String get loginOrDivider => 'eller';

  @override
  String get loginServerUrlHeading => 'Adress till Sure-servern:';

  @override
  String get loginApiKeyLoginButton => 'Logga in med API-nyckel';

  @override
  String get loginBackendSettingsTooltip => 'Serverinställningar';

  @override
  String get transactionEditSessionExpired =>
      'Sessionen har gått ut. Logga in igen.';

  @override
  String get transactionEditUpdated => 'Transaktionen har uppdaterats';

  @override
  String get transactionEditUpdateFailed =>
      'Det gick inte att uppdatera transaktionen';

  @override
  String transactionEditNameMaxLength(int max) {
    return 'Namnet får vara högst $max tecken';
  }

  @override
  String get transactionEditNameInvalidChars =>
      'Namnet innehåller tecken som inte stöds';

  @override
  String transactionEditNotesMaxLength(int max) {
    return 'Anteckningarna får vara högst $max tecken';
  }

  @override
  String get transactionEditNotesInvalidChars =>
      'Anteckningarna innehåller tecken som inte stöds';

  @override
  String get transactionEditNoCategory => 'Ingen kategori';

  @override
  String get transactionEditCurrentCategory => 'Nuvarande kategori';

  @override
  String get transactionEditNoMerchant => 'Ingen handlare';

  @override
  String get transactionEditCurrentMerchant => 'Nuvarande handlare';

  @override
  String get transactionEditUnknownTag => 'Okänd tagg';

  @override
  String get transactionEditSyncedOnly =>
      'Bara synkade transaktioner kan redigeras i mobilen.';

  @override
  String get transactionFormSessionExpired =>
      'Sessionen har gått ut. Logga in igen.';

  @override
  String get transactionFormAmountRequiredPrompt => 'Ange ett belopp';

  @override
  String get transactionFormAmountInvalidNumber => 'Ange ett giltigt tal';

  @override
  String get transactionFormAmountTooSmall => 'Beloppet måste vara större än 0';

  @override
  String get transactionFormCreateSuccessOnline => 'Transaktionen har skapats';

  @override
  String get transactionFormCreateSuccessOffline =>
      'Transaktionen har sparats (synkas när du är online)';

  @override
  String get transactionFormCreateFailed =>
      'Det gick inte att skapa transaktionen';

  @override
  String transactionFormGenericError(String error) {
    return 'Fel: $error';
  }

  @override
  String get transactionFormLess => 'Mindre';

  @override
  String get transactionFormMore => 'Mer';

  @override
  String get transactionFormDateHelper => 'Valfritt (standard: i dag)';

  @override
  String get transactionFormNameHelper => 'Valfritt (standard: SureApp)';

  @override
  String get transactionFormCategoryLoading => 'Läser in kategorier…';

  @override
  String get transactionFormCategoryHelper => 'Valfritt';

  @override
  String get transactionFormNoCategory => 'Ingen kategori';

  @override
  String get transactionFormCreateButton => 'Skapa transaktion';

  @override
  String get transactionFormAmountHelper => 'Obligatoriskt';

  @override
  String get logViewerClearConfirm => 'Vill du verkligen rensa alla loggar?';

  @override
  String get logViewerClear => 'Rensa';

  @override
  String get chatConversationEditTitle => 'Redigera titel';

  @override
  String get chatConversationTitleLabel => 'Chattitel';

  @override
  String get chatConversationRefreshTooltip => 'Uppdatera';

  @override
  String get chatConversationLoadError => 'Det gick inte att läsa in chatten';

  @override
  String get navEnableAiChatTitle => 'Aktivera AI-chatt?';

  @override
  String get navEnableAiChatContent =>
      'AI-chatt är för närvarande avstängd i dina kontoinställningar. Vill du aktivera den nu?';

  @override
  String get navEnableAiChatNotNow => 'Inte nu';

  @override
  String get navEnableAiChatConfirm => 'Aktivera AI';

  @override
  String get navEnableAiChatFailed => 'Det gick inte att aktivera AI just nu.';

  @override
  String get connectivitySignInToSync => 'Logga in för att synka transaktioner';

  @override
  String get connectivitySyncSuccess => 'Transaktionerna har synkats';

  @override
  String get connectivitySyncFailed =>
      'Det gick inte att synka transaktionerna. Försök igen.';

  @override
  String get connectivityAuthFailed =>
      'Det gick inte att autentisera. Försök igen.';

  @override
  String ssoOnboardingSignedInAs(String email) {
    return 'Inloggad som $email';
  }

  @override
  String get ssoOnboardingGoogleVerified => 'Google-kontot har verifierats';

  @override
  String get ssoOnboardingLinkCredentialsNote =>
      'Ange uppgifterna för ditt befintliga användarkonto för att koppla det till Google-inloggning.';

  @override
  String get ssoOnboardingPendingInvitationNote =>
      'Du har en väntande inbjudan. Acceptera den för att gå med i ett befintligt hushåll.';

  @override
  String get ssoOnboardingCreateIdentityNote =>
      'Skapa ett nytt användarkonto med din Google-identitet.';

  @override
  String get ssoOnboardingFirstNameRequired => 'Förnamn krävs';

  @override
  String get ssoOnboardingLastNameRequired => 'Efternamn krävs';

  @override
  String get backendConfigTimeout =>
      'Anslutningen tog för lång tid. Kontrollera adressen och försök igen.';

  @override
  String get backendConfigSuccess => 'Anslutningen lyckades!';

  @override
  String backendConfigServerError(int code) {
    return 'Servern svarade med status $code. Kontrollera att det är en Sure-server.';
  }

  @override
  String backendConfigConnectionFailed(String error) {
    return 'Anslutningen misslyckades: $error';
  }

  @override
  String backendConfigSaveFailed(String error) {
    return 'Det gick inte att spara adressen: $error';
  }

  @override
  String get backendConfigUrlRequired => 'Ange en serveradress';

  @override
  String get backendConfigUrlScheme =>
      'Adressen måste börja med http:// eller https://';

  @override
  String get backendConfigUrlInvalid => 'Ange en giltig adress';

  @override
  String get backendConfigHeadersHelp =>
      'Headers skickas av appen med API-anrop. SSO-sidor i extern webbläsare får dem kanske inte.';

  @override
  String get recentTransactionsUnknownAccount => 'Okänt konto';

  @override
  String get accountDetailUnavailable =>
      'Kontouppgifterna är tillfälligt otillgängliga';

  @override
  String chatListMinutesAgo(int minutes) {
    return 'för $minutes min sedan';
  }

  @override
  String chatListHoursAgo(int hours) {
    return 'för $hours tim sedan';
  }

  @override
  String chatListDaysAgo(int days) {
    return 'för $days d sedan';
  }

  @override
  String get chatConversationStartFailed =>
      'Det gick inte att starta konversationen. Försök igen.';

  @override
  String get budgetsTitle => 'Budgetar';

  @override
  String get budgetsPreviousMonth => 'Föregående månad';

  @override
  String get budgetsNextMonth => 'Nästa månad';

  @override
  String get budgetsIncome => 'Inkomster';

  @override
  String budgetsRolledOver(String amount) {
    return '+$amount överfört';
  }

  @override
  String get budgetsSharedBudget => 'Delad budget';

  @override
  String get budgetsCategoriesTitle => 'Kategorier';

  @override
  String budgetsFilterOverBudget(int count) {
    return 'Över budget ($count)';
  }

  @override
  String budgetsBudgetNumber(int number) {
    return 'Budget $number';
  }

  @override
  String budgetsNoBudgetTitle(String month) {
    return 'Ingen budget för $month';
  }

  @override
  String get budgetsNotSetUpMessage =>
      'Inga utgiftsgränser är satta för den här månaden än. Ställ in dem i Sure på webben.';

  @override
  String get budgetsNoCategories =>
      'Inga budgeterade kategorier eller utgifter den här månaden.';

  @override
  String get budgetsOfflineTitle => 'Du är offline';

  @override
  String get budgetsOfflineMessage =>
      'Anslut till internet för att läsa in den här månadens budget.';

  @override
  String get budgetsOfflineCached =>
      'Offline. Visar siffrorna som lästes in tidigare.';

  @override
  String get budgetsRefreshFailed =>
      'Kunde inte uppdatera. Visar siffrorna som lästes in tidigare.';

  @override
  String get budgetsLoadFailed => 'Kunde inte läsa in budgetar';

  @override
  String get budgetsSessionExpired => 'Din session har gått ut. Logga in igen.';

  @override
  String budgetCategoryTransactionsEmpty(String month) {
    return 'Inga transaktioner i den här kategorin för $month.';
  }

  @override
  String get budgetCategoryTransactionsLoadMore => 'Visa fler';

  @override
  String get budgetCategoryTransactionsLoadFailed =>
      'Kunde inte läsa in transaktioner';

  @override
  String get cashFlowTitle => 'Kassaflöde';

  @override
  String get cashFlowPeriodCurrentMonth => 'Den här månaden';

  @override
  String get cashFlowPeriodLastMonth => 'Förra månaden';

  @override
  String get cashFlowPeriodLast30Days => 'Senaste 30 dagarna';

  @override
  String get cashFlowPeriodLast90Days => 'Senaste 90 dagarna';

  @override
  String get cashFlowPeriodCurrentYear => 'Hittills i år';

  @override
  String get cashFlowPeriodLast365Days => 'Senaste 365 dagarna';

  @override
  String get cashFlowIncome => 'Inkomster';

  @override
  String get cashFlowExpenses => 'Utgifter';

  @override
  String get cashFlowNetSavings => 'Nettosparande';

  @override
  String cashFlowSavingsRate(String rate) {
    return 'Sparkvot: $rate';
  }

  @override
  String get cashFlowExpensesByCategory => 'Utgifter per kategori';

  @override
  String get cashFlowIncomeByCategory => 'Inkomster per kategori';

  @override
  String cashFlowShareOfExpenses(String percent) {
    return '$percent av utgifterna';
  }

  @override
  String cashFlowShareOfIncome(String percent) {
    return '$percent av inkomsterna';
  }

  @override
  String get cashFlowEmpty => 'Inga inkomster eller utgifter under perioden';

  @override
  String get cashFlowEmptySubtitle =>
      'Prova en annan period eller dra för att uppdatera.';

  @override
  String get cashFlowNoExpenses => 'Inga utgifter under perioden';

  @override
  String get cashFlowNoIncome => 'Inga inkomster under perioden';

  @override
  String get cashFlowLoadFailed => 'Kunde inte läsa in kassaflödet';

  @override
  String get cashFlowOffline =>
      'Du är offline. Kassaflödet beräknas av din Sure-server och kräver en anslutning.';

  @override
  String get cashFlowOutdated => 'Inaktuell';

  @override
  String get cashFlowTransactionsEmpty => 'Inga transaktioner under perioden';

  @override
  String get cashFlowTransactionsLoadFailed =>
      'Kunde inte läsa in transaktioner';

  @override
  String get accountRangeWeek => '1V';

  @override
  String get accountRangeMonth => '1M';

  @override
  String get accountRangeQuarter => '3M';

  @override
  String get accountRangeYear => '1Å';

  @override
  String get accountRangeAll => 'Alla';

  @override
  String get accountChartNoHistory => 'Ingen saldohistorik för perioden';

  @override
  String get accountTabHoldings => 'Innehav';

  @override
  String get accountTabActivity => 'Aktivitet';

  @override
  String get accountTabTransactions => 'Transaktioner';

  @override
  String get holdingsEmpty => 'Inga innehav synkade än';

  @override
  String get holdingsLoadFailed => 'Kunde inte läsa in innehav';

  @override
  String get holdingNoCostBasis => 'Inget anskaffningsvärde';

  @override
  String get tradesEmpty => 'Ingen investeringsaktivitet än';

  @override
  String get tradesLoadFailed => 'Kunde inte läsa in aktivitet';

  @override
  String get tradeBuy => 'Köp';

  @override
  String get tradeSell => 'Sälj';

  @override
  String portfolioAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count konton',
      one: '1 konto',
    );
    return '$_temp0';
  }

  @override
  String portfolioUnrealizedGain(String amount, String percent) {
    return 'Orealiserat $amount ($percent)';
  }

  @override
  String get portfolioAllocation => 'Fördelning';

  @override
  String get portfolioAllocationOther => 'Övrigt';

  @override
  String get portfolioAllocationCash => 'Kontanter';

  @override
  String get portfolioLoadFailed => 'Kunde inte läsa in dina investeringar';

  @override
  String tradeQuantityAtPrice(String quantity, String price) {
    return '$quantity à $price';
  }

  @override
  String get shellNavActivity => 'Aktivitet';

  @override
  String get shellNavPlan => 'Planera';

  @override
  String get shellNavInvest => 'Investera';

  @override
  String get shellSettingsTitle => 'Inställningar';

  @override
  String get shellSectionData => 'Data';

  @override
  String get shellSectionTools => 'Verktyg';

  @override
  String get shellSectionApp => 'App';

  @override
  String get shellConnections => 'Kopplingar';

  @override
  String get shellImport => 'Importera';

  @override
  String get shellCategories => 'Kategorier';

  @override
  String get shellTags => 'Taggar';

  @override
  String get shellMerchants => 'Handlare';

  @override
  String get shellRules => 'Regler';

  @override
  String get shellExport => 'Exportera';

  @override
  String get shellProfile => 'Profil';

  @override
  String get shellPreferences => 'Inställningar för kontot';

  @override
  String get shellServer => 'Server';

  @override
  String get shellOpensOnWeb => 'Öppnas på webben';

  @override
  String get shellPlanBudget => 'Budget';

  @override
  String get shellPlanRecurring => 'Återkommande';

  @override
  String get shellPlanGoals => 'Mål';

  @override
  String get shellPlanBills => 'Räkningar';

  @override
  String get shellComingSoon => 'Kommer snart';

  @override
  String get shellComingSoonBody => 'Den här delen av appen är på väg.';

  @override
  String get shellGoalsOnWeb =>
      'Mål finns på webben än så länge. Öppna dem här för att följa hur det går.';

  @override
  String get shellBillsOnWeb =>
      'Räkningar finns på webben än så länge. Öppna dem här för att se vad som är på väg.';

  @override
  String get shellOpenOnWeb => 'Öppna på webben';

  @override
  String get shellInvestLoadFailed => 'Kunde inte läsa in dina konton';

  @override
  String get shellWebBack => 'Bakåt';

  @override
  String get shellWebForward => 'Framåt';

  @override
  String get shellWebOpenInSafari => 'Öppna i Safari';

  @override
  String get shellWebOpenInBrowser => 'Öppna i webbläsaren';

  @override
  String get shellWebLoadFailed => 'Kunde inte läsa in sidan';

  @override
  String get shellWebOpenFailed => 'Kunde inte öppna länken';

  @override
  String get activity => 'Aktivitet';

  @override
  String get activitySearchHint => 'Sök transaktioner';

  @override
  String get activityClearSearch => 'Rensa sökningen';

  @override
  String get activityFilterDate => 'Datum';

  @override
  String get activityDateThisMonth => 'Den här månaden';

  @override
  String get activityDateLastMonth => 'Förra månaden';

  @override
  String get activityDateLast90Days => 'Senaste 90 dagarna';

  @override
  String get activityDateThisYear => 'I år';

  @override
  String get activityDateAll => 'All tid';

  @override
  String get activityDateCustom => 'Eget intervall…';

  @override
  String get activityFilterCategory => 'Kategori';

  @override
  String get activityFilterAccount => 'Konto';

  @override
  String get activityFilterTags => 'Taggar';

  @override
  String get activityFilterType => 'Typ';

  @override
  String get activityTypeAll => 'Alla typer';

  @override
  String get activityTypeExpense => 'Utgifter';

  @override
  String get activityTypeIncome => 'Inkomster';

  @override
  String activityFilterCount(String label, int count) {
    return '$label · $count';
  }

  @override
  String get activityClearAll => 'Rensa alla';

  @override
  String get activityFilterClear => 'Rensa';

  @override
  String get activityFilterSearchHint => 'Hitta';

  @override
  String get activityFilterNoOptions => 'Det finns inget att välja än';

  @override
  String get activityUnknownDate => 'Inget datum';

  @override
  String get activityEmpty => 'Inga transaktioner den här månaden';

  @override
  String get activityClearFilters => 'Rensa filter';

  @override
  String get activityLoadFailed => 'Kunde inte läsa in transaktioner';

  @override
  String get activityAdd => 'Lägg till transaktion';

  @override
  String get activityPickAccount => 'Välj ett konto';

  @override
  String get activityNoAccounts => 'Lägg till ett konto först.';

  @override
  String activitySelectedCount(int count) {
    return '$count valda';
  }

  @override
  String get activityCategorize => 'Kategorisera';

  @override
  String get activityPickCategory => 'Välj en kategori';

  @override
  String activityCategorizing(int done, int total) {
    return 'Kategoriserar $done av $total…';
  }

  @override
  String activityCategorized(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transaktioner kategoriserade',
      one: '1 transaktion kategoriserad',
    );
    return '$_temp0';
  }

  @override
  String activityDeleting(int done, int total) {
    return 'Raderar $done av $total…';
  }

  @override
  String activityBulkPartial(int done, int total, int failed) {
    return '$done av $total klara. $failed misslyckades och är fortfarande valda.';
  }

  @override
  String get activitySessionExpired =>
      'Din session har gått ut. Logga in igen.';

  @override
  String get recurring => 'Återkommande';

  @override
  String get recurringAdd => 'Lägg till återkommande';

  @override
  String get recurringGroupUpcoming => 'Kommande denna månad';

  @override
  String get recurringGroupLater => 'Senare';

  @override
  String get recurringGroupSuggested => 'Förslag';

  @override
  String get recurringGroupInactive => 'Inaktiva';

  @override
  String get recurringEmptyTitle => 'Inga återkommande transaktioner än';

  @override
  String get recurringEmptyBody =>
      'Lägg till räkningar, prenumerationer och inkomster som upprepas för att se vad som väntar.';

  @override
  String get recurringLoadFailed =>
      'Kunde inte läsa in återkommande transaktioner';

  @override
  String get recurringRetry => 'Försök igen';

  @override
  String recurringEveryWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Var $count:e vecka',
      one: 'Varje vecka',
    );
    return '$_temp0';
  }

  @override
  String recurringEveryMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Var $count:e månad',
      one: 'Varje månad',
    );
    return '$_temp0';
  }

  @override
  String recurringEveryYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vart $count:e år',
      one: 'Varje år',
    );
    return '$_temp0';
  }

  @override
  String get recurringStatusActive => 'Aktiv';

  @override
  String get recurringStatusPaused => 'Pausad';

  @override
  String get recurringStatusInactive => 'Inaktiv';

  @override
  String get recurringStatusSuggested => 'Förslag';

  @override
  String get recurringStatusEnded => 'Avslutad';

  @override
  String get recurringIncome => 'Inkomst';

  @override
  String get recurringExpense => 'Utgift';

  @override
  String get recurringActionPause => 'Pausa';

  @override
  String recurringDeleteTitle(String name) {
    return 'Ta bort $name?';
  }

  @override
  String get recurringDeleteBody =>
      'Det återkommande objektet tas bort. Dina tidigare transaktioner påverkas inte.';

  @override
  String get recurringDeleted => 'Återkommande objekt borttaget';

  @override
  String recurringPausedMessage(String name) {
    return '$name pausad';
  }

  @override
  String recurringActivatedMessage(String name) {
    return '$name aktiverad';
  }

  @override
  String get recurringActionFailed => 'Kunde inte uppdatera. Försök igen.';

  @override
  String get recurringNewTitle => 'Ny återkommande';

  @override
  String get recurringEditTitle => 'Redigera återkommande';

  @override
  String get recurringFieldName => 'Namn';

  @override
  String get recurringFieldAmount => 'Belopp';

  @override
  String get recurringFieldCurrency => 'Valuta';

  @override
  String get recurringFieldAccount => 'Konto';

  @override
  String get recurringNoAccount => 'Inget konto';

  @override
  String get recurringFieldNextDate => 'Nästa förväntade datum';

  @override
  String get recurringFieldLastDate => 'Senaste tillfälle';

  @override
  String get recurringFieldActive => 'Aktiv';

  @override
  String get recurringFieldActiveHint =>
      'Inaktiva objekt förväntas inte och räknas inte med i summorna';

  @override
  String get recurringFieldAutopay => 'Autogiro';

  @override
  String get recurringFieldPaymentUrl => 'Betalningslänk';

  @override
  String get recurringFieldNotes => 'Anteckningar';

  @override
  String get recurringCadenceNote =>
      'Nya objekt upprepas varje månad på samma dag som nästa förväntade datum. Ändra schemat på webben.';

  @override
  String get recurringLockedNote =>
      'Namn, belopp, valuta, konto och schema kan bara ändras på webben.';

  @override
  String get recurringErrorNameRequired => 'Ange ett namn';

  @override
  String get recurringErrorAmountInvalid => 'Ange ett belopp större än noll';

  @override
  String get recurringErrorCurrencyInvalid =>
      'Använd en kod med tre bokstäver, som SEK';

  @override
  String get recurringErrorUrlInvalid =>
      'Ange en länk som börjar med http:// eller https://';

  @override
  String get recurringErrorLastAfterNext =>
      'Måste vara före nästa förväntade datum';

  @override
  String get recurringSaveFailed => 'Kunde inte spara. Försök igen.';

  @override
  String get insightsTitle => 'Insikter';

  @override
  String get insightsDismiss => 'Avfärda';

  @override
  String get insightsPriorityHigh => 'Hög prioritet';

  @override
  String get insightsDismissFailed => 'Kunde inte avfärda insikten';

  @override
  String get spendingVsNormalTitle => 'Utgifter mot normalt';

  @override
  String get accountActions => 'Fler åtgärder';

  @override
  String get accountActionsUpdateBalance => 'Uppdatera saldo';

  @override
  String get accountActionsAddTrade => 'Lägg till affär';

  @override
  String get accountActionsEditTrade => 'Redigera affär';

  @override
  String get accountActionsSyncNow => 'Synka nu';

  @override
  String get accountActionsDate => 'Datum';

  @override
  String get accountActionsNewBalance => 'Nytt saldo';

  @override
  String accountActionsCurrentBalance(String amount) {
    return 'Nuvarande saldo: $amount';
  }

  @override
  String get accountActionsNote => 'Anteckning (valfritt)';

  @override
  String get accountActionsSave => 'Spara';

  @override
  String get accountActionsRequired => 'Obligatoriskt';

  @override
  String get accountActionsBalanceRequired => 'Ange det nya saldot';

  @override
  String get accountActionsInvalidNumber => 'Ange ett giltigt tal';

  @override
  String get accountActionsMustBePositive => 'Måste vara större än noll';

  @override
  String get accountActionsFeeInvalid => 'Avgifter kan inte vara negativa';

  @override
  String get accountActionsBalanceUpdated => 'Saldot har uppdaterats';

  @override
  String get accountActionsBuy => 'Köp';

  @override
  String get accountActionsSell => 'Sälj';

  @override
  String get accountActionsSecurity => 'Värdepapper';

  @override
  String get accountActionsSecurityHint => 'Ticker, t.ex. AAPL';

  @override
  String get accountActionsSecurityRequired => 'Ange en ticker';

  @override
  String get accountActionsEditTradeNote =>
      'Värdepapper och avgifter kan inte ändras. Ta bort affären och lägg till den igen i stället.';

  @override
  String get accountActionsQuantity => 'Antal';

  @override
  String get accountActionsPrice => 'Pris per andel';

  @override
  String get accountActionsFee => 'Avgifter (valfritt)';

  @override
  String get accountActionsTotalCost => 'Total kostnad';

  @override
  String get accountActionsTotalProceeds => 'Totalt belopp';

  @override
  String get accountActionsTradeAdded => 'Affären har lagts till';

  @override
  String get accountActionsTradeUpdated => 'Affären har uppdaterats';

  @override
  String get accountActionsTradeDeleted => 'Affären har tagits bort';

  @override
  String get accountActionsDeleteTrade => 'Ta bort affär';

  @override
  String get accountActionsDeleteTradeConfirm =>
      'Ta bort den här affären? Det går inte att ångra.';

  @override
  String get accountActionsSyncStarting => 'Startar synk...';

  @override
  String get accountActionsSyncing => 'Synkar...';

  @override
  String accountActionsSyncElapsed(String elapsed) {
    return '$elapsed har gått';
  }

  @override
  String get accountActionsSyncComplete => 'Synken är klar';

  @override
  String get accountActionsSyncFailed => 'Synken misslyckades';

  @override
  String accountActionsSyncFailedDetail(String message) {
    return 'Synken misslyckades: $message';
  }

  @override
  String get accountActionsSyncTimeout =>
      'Synkar fortfarande efter 2 minuter. Den fortsätter i bakgrunden.';

  @override
  String get accountActionsHide => 'Dölj';

  @override
  String get accountActionsClose => 'Stäng';

  @override
  String get accountActionsNeverSynced => 'Inte synkad än';

  @override
  String get accountActionsSyncedJustNow => 'Synkad nyss';

  @override
  String accountActionsSyncedMinutesAgo(int count) {
    return 'Synkad för $count min sedan';
  }

  @override
  String accountActionsSyncedHoursAgo(int count) {
    return 'Synkad för $count tim sedan';
  }

  @override
  String accountActionsSyncedDaysAgo(int count) {
    return 'Synkad för $count d sedan';
  }

  @override
  String get accountActionsSyncChipHint => 'Startar en synk av alla konton';

  @override
  String get txnDetail => 'Transaktion';

  @override
  String get txnDetailOfflineNote =>
      'Du är offline. Ändringar kan sparas när du är online igen.';

  @override
  String get txnDetailSplitLockedFields =>
      'Belopp, datum och typ kommer från uppdelningen. Ändra uppdelningen för att ändra dem.';

  @override
  String get txnDetailChooseMerchant => 'Välj handlare';

  @override
  String get txnDetailChooseTags => 'Välj taggar';

  @override
  String get txnDetailSearchHint => 'Sök';

  @override
  String txnDetailCreateOption(String name) {
    return 'Skapa ”$name”';
  }

  @override
  String get txnDetailCreateFailed => 'Kunde inte skapa den. Försök igen.';

  @override
  String get txnDetailCreateOffline =>
      'Anslut till internet för att skapa nya poster.';

  @override
  String get txnDetailPickerEmpty => 'Inga träffar';

  @override
  String get txnDetailDone => 'Klar';

  @override
  String get txnDetailSplitAction => 'Dela upp transaktion';

  @override
  String get txnDetailSplitOffline =>
      'Uppdelningar kräver en internetanslutning.';

  @override
  String get txnDetailSplitLoadFailed => 'Kunde inte läsa in uppdelningen.';

  @override
  String get txnDetailSplitTitle => 'Dela upp transaktion';

  @override
  String txnDetailSplitTotal(String amount) {
    return 'Totalt $amount';
  }

  @override
  String txnDetailSplitRemaining(String amount) {
    return 'Kvar: $amount';
  }

  @override
  String txnDetailSplitOver(String amount) {
    return '$amount för mycket';
  }

  @override
  String get txnDetailSplitBalanced => 'Delarna summerar till totalen.';

  @override
  String get txnDetailSplitSignHint =>
      'Positiva belopp går åt samma håll som totalen; använd ett negativt belopp för en del som går åt andra hållet.';

  @override
  String txnDetailSplitPartLabel(int number) {
    return 'Del $number';
  }

  @override
  String get txnDetailSplitRemoveRow => 'Ta bort del';

  @override
  String get txnDetailSplitRowName => 'Namn (valfritt)';

  @override
  String get txnDetailSplitInvalidAmount =>
      'Ange ett belopp som inte är noll, med högst 4 decimaler.';

  @override
  String get txnDetailSplitUseRemaining => 'Använd återstående belopp';

  @override
  String get txnDetailSplitAddRow => 'Lägg till del';

  @override
  String get txnDetailSplitNeedTwo => 'Lägg till minst två delar.';

  @override
  String get txnDetailSplitSave => 'Spara uppdelning';

  @override
  String get txnDetailSplitRemove => 'Ta bort uppdelning';

  @override
  String get txnDetailSplitRemoveConfirmTitle => 'Ta bort uppdelningen?';

  @override
  String get txnDetailSplitRemoveConfirmBody =>
      'Delarna tas bort och den ursprungliga transaktionen räknas igen.';

  @override
  String get txnDetailSplitSaved => 'Uppdelningen sparades';

  @override
  String get txnDetailSplitRemoved => 'Uppdelningen togs bort';

  @override
  String get dataInImportTitle => 'Importera';

  @override
  String get dataInHistoryHeader => 'Importhistorik';

  @override
  String get dataInHistoryEmpty => 'Inga importer än.';

  @override
  String get dataInHistoryFailed =>
      'Det gick inte att läsa in importhistoriken.';

  @override
  String get dataInRetry => 'Försök igen';

  @override
  String get dataInRefresh => 'Uppdatera';

  @override
  String dataInRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rader',
      one: '1 rad',
    );
    return '$_temp0';
  }

  @override
  String dataInInvalidRowCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rader har fel',
      one: '1 rad har fel',
    );
    return '$_temp0';
  }

  @override
  String get dataInStatusLabel => 'Status';

  @override
  String get dataInCreatedLabel => 'Skapad';

  @override
  String get dataInStatusLoadFailed => 'Det gick inte att uppdatera statusen.';

  @override
  String get dataInStatusPending => 'Inte startad';

  @override
  String get dataInStatusImporting => 'Importerar …';

  @override
  String get dataInStatusComplete => 'Klar';

  @override
  String get dataInStatusFailed => 'Misslyckades';

  @override
  String get dataInStatusReverting => 'Återställer …';

  @override
  String get dataInStatusRevertFailed => 'Återställningen misslyckades';

  @override
  String get dataInTypeTransactions => 'Transaktioner';

  @override
  String get dataInTypeTrades => 'Affärer';

  @override
  String get dataInTypeAccounts => 'Konton';

  @override
  String dataInStepOf(int step, int total, String title) {
    return 'Steg $step av $total: $title';
  }

  @override
  String get dataInStepFile => 'Välj fil';

  @override
  String get dataInStepMap => 'Koppla kolumner';

  @override
  String get dataInStepPreview => 'Förhandsgranska';

  @override
  String get dataInStepPublish => 'Importera';

  @override
  String dataInFileHelp(String size) {
    return 'Importera transaktioner från en CSV-fil till ett konto. Filer får vara högst $size.';
  }

  @override
  String get dataInAccountLabel => 'Konto';

  @override
  String get dataInNoAccounts => 'Lägg till ett konto först.';

  @override
  String get dataInChooseCsv => 'Välj CSV-fil';

  @override
  String get dataInChooseFile => 'Välj fil';

  @override
  String get dataInChooseAnother => 'Byt fil';

  @override
  String get dataInNotCsv => 'Välj en fil som slutar på .csv.';

  @override
  String get dataInFileEmpty => 'Filen är tom.';

  @override
  String dataInFileTooLarge(String size) {
    return 'Filen är för stor. Gränsen är $size.';
  }

  @override
  String get dataInReadFailed => 'Det gick inte att läsa filen.';

  @override
  String get dataInContinue => 'Fortsätt';

  @override
  String get dataInBack => 'Tillbaka';

  @override
  String dataInDetected(int columns, int rows) {
    String _temp0 = intl.Intl.pluralLogic(
      columns,
      locale: localeName,
      other: '$columns kolumner',
      one: '1 kolumn',
    );
    String _temp1 = intl.Intl.pluralLogic(
      rows,
      locale: localeName,
      other: '$rows rader',
      one: '1 rad',
    );
    return 'Hittade $_temp0 och $_temp1.';
  }

  @override
  String dataInRequiredLabel(String label) {
    return '$label (krävs)';
  }

  @override
  String get dataInColumnDate => 'Datumkolumn';

  @override
  String get dataInColumnAmount => 'Beloppskolumn';

  @override
  String get dataInColumnName => 'Namnkolumn';

  @override
  String get dataInColumnCategory => 'Kategorikolumn';

  @override
  String get dataInColumnTags => 'Taggkolumn';

  @override
  String get dataInColumnNotes => 'Anteckningskolumn';

  @override
  String get dataInColumnNone => 'Ingen';

  @override
  String get dataInDateFormat => 'Datumformat';

  @override
  String get dataInNumberFormat => 'Talformat';

  @override
  String get dataInSignage => 'Beloppstecken';

  @override
  String get dataInSignagePositive => 'Inkomster är positiva';

  @override
  String get dataInSignageNegative => 'Inkomster är negativa';

  @override
  String get dataInSeparator => 'Kolumnavgränsare';

  @override
  String get dataInSeparatorComma => 'Komma (,)';

  @override
  String get dataInSeparatorSemicolon => 'Semikolon (;)';

  @override
  String get dataInNeedDateAndAmount =>
      'Välj datum- och beloppskolumn för att fortsätta.';

  @override
  String dataInPreviewSummary(int shown, int total) {
    return 'Visar $shown av $total rader.';
  }

  @override
  String dataInPreviewInvalid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count rader matchar inte de valda formaten.',
      one: '1 rad matchar inte de valda formaten.',
    );
    return '$_temp0';
  }

  @override
  String get dataInCategoriesNote =>
      'Kategorier och taggar från filen kanske inte används vid import från appen. Du kan ange dem på webben.';

  @override
  String get dataInPreviewEmpty => 'Inga rader att importera.';

  @override
  String get dataInRowUntitled => '(inget namn)';

  @override
  String dataInRowBadDate(String value) {
    return 'Datumet \"$value\" matchar inte datumformatet.';
  }

  @override
  String dataInRowBadAmount(String value) {
    return 'Beloppet \"$value\" är inte ett tal.';
  }

  @override
  String get dataInPublish => 'Importera';

  @override
  String get dataInUploading => 'Laddar upp …';

  @override
  String get dataInComplete => 'Importen är klar';

  @override
  String get dataInStillRunning =>
      'Importen pågår fortfarande. Se statusen i importhistoriken.';

  @override
  String get dataInKeepInBackground => 'Fortsätt i bakgrunden';

  @override
  String get dataInRunningInBackground =>
      'Importen fortsätter. Statusen finns i importhistoriken.';

  @override
  String get dataInRejectedRows => 'Rader som servern avvisade';

  @override
  String get dataInStartOver => 'Börja om';

  @override
  String get dataInImportAnother => 'Importera en fil till';

  @override
  String get dataInMoreTypesOnWeb => 'Fler importtyper på webben';

  @override
  String get dataInStatementTitle => 'Ladda upp kontoutdrag';

  @override
  String dataInStatementHelp(String size) {
    return 'Lägg till ett kontoutdrag som PDF, CSV eller XLSX i dokumentvalvet. Filer får vara högst $size.';
  }

  @override
  String get dataInStatementWrongType => 'Välj en PDF-, CSV- eller XLSX-fil.';

  @override
  String get dataInUpload => 'Ladda upp';

  @override
  String dataInStatementUploaded(String name) {
    return '$name laddades upp.';
  }

  @override
  String get dataInStatementViewOnWeb => 'Visa kontoutdrag på webben';

  @override
  String dataInStatementDuplicate(String date) {
    return 'Redan uppladdad $date.';
  }

  @override
  String get dataInStatementDuplicateHidden =>
      'Filen finns redan i dokumentvalvet.';

  @override
  String get dataInStatementFailed => 'Kontoutdraget kunde inte laddas upp.';

  @override
  String get dataInStatementPickAccount =>
      'Välj ett konto för att se dess kontoutdrag.';

  @override
  String get dataInStatementListFailed =>
      'Det gick inte att läsa in kontoutdragen.';

  @override
  String get dataInStatementListEmpty =>
      'Inga kontoutdrag för det här kontot än.';

  @override
  String get dataInStatementRecent => 'Senaste kontoutdragen';

  @override
  String dataInStatementPeriod(String start, String end) {
    return '$start–$end';
  }

  @override
  String dataInStatementAdded(String date) {
    return 'Tillagd $date';
  }

  @override
  String get manageSearch => 'Sök';

  @override
  String get manageClearSearch => 'Rensa sökningen';

  @override
  String manageNoMatches(String query) {
    return 'Inget matchar ”$query”.';
  }

  @override
  String get manageNameLabel => 'Namn';

  @override
  String get manageNameRequired => 'Ange ett namn.';

  @override
  String get manageColor => 'Färg';

  @override
  String manageColorOption(int number) {
    return 'Färg $number';
  }

  @override
  String get manageColorAutomatic => 'Automatisk';

  @override
  String get manageEditOnWeb => 'Redigera på webben';

  @override
  String get manageActionFailed => 'Något gick fel. Försök igen.';

  @override
  String get manageCategoriesTitle => 'Kategorier';

  @override
  String get manageCategoriesEmpty => 'Inga kategorier än';

  @override
  String get manageCategoriesEmptyBody =>
      'Lägg till en med +. Kategorier sorterar dina utgifter och inkomster.';

  @override
  String get manageCategoriesLoadFailed =>
      'Det gick inte att läsa in kategorierna.';

  @override
  String get manageCategoryAdd => 'Lägg till kategori';

  @override
  String get manageCategoryNew => 'Ny kategori';

  @override
  String get manageCategoryParent => 'Överordnad kategori';

  @override
  String get manageCategoryNoParent => 'Ingen (översta nivån)';

  @override
  String get manageCategoryIconHint =>
      'Sure väljer en ikon som passar namnet. Du kan ändra den på webben.';

  @override
  String manageCategoryCreated(String name) {
    return 'Kategorin ”$name” lades till';
  }

  @override
  String manageCategorySubcategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count underkategorier',
      one: '1 underkategori',
      zero: 'Inga underkategorier',
    );
    return '$_temp0';
  }

  @override
  String manageCategoryInParent(String parent) {
    return 'Underkategori till $parent';
  }

  @override
  String get manageCategoryInfoBody =>
      'Byt namn, färg eller ikon på, slå ihop eller ta bort kategorier på webben.';

  @override
  String get manageTagsTitle => 'Taggar';

  @override
  String get manageTagsEmpty => 'Inga taggar än';

  @override
  String get manageTagsEmptyBody =>
      'Taggar grupperar transaktioner över kategorier, till exempel en resa eller ett projekt.';

  @override
  String get manageTagsLoadFailed => 'Det gick inte att läsa in taggarna.';

  @override
  String get manageTagAdd => 'Lägg till tagg';

  @override
  String get manageTagNew => 'Ny tagg';

  @override
  String get manageTagEdit => 'Redigera tagg';

  @override
  String manageTagCreated(String name) {
    return 'Taggen ”$name” lades till';
  }

  @override
  String get manageTagSaved => 'Taggen sparades';

  @override
  String get manageTagDeleted => 'Taggen togs bort';

  @override
  String get manageTagDelete => 'Ta bort tagg';

  @override
  String manageTagDeleteTitle(String name) {
    return 'Ta bort ”$name”?';
  }

  @override
  String get manageTagDeleteBody =>
      'Taggen tas bort från alla transaktioner som har den. Det går inte att ångra.';

  @override
  String get manageMerchantsTitle => 'Handlare';

  @override
  String get manageMerchantsEmpty => 'Inga handlare än';

  @override
  String get manageMerchantsEmptyBody =>
      'Handlare du lägger till, och de som dina bankkopplingar hittar, visas här.';

  @override
  String get manageMerchantsLoadFailed =>
      'Det gick inte att läsa in handlarna.';

  @override
  String get manageMerchantAdd => 'Lägg till handlare';

  @override
  String get manageMerchantNew => 'Ny handlare';

  @override
  String get manageMerchantWebsite => 'Webbplats (valfritt)';

  @override
  String get manageMerchantWebsiteInvalid =>
      'Ange en webbadress som example.com.';

  @override
  String manageMerchantCreated(String name) {
    return 'Handlaren ”$name” lades till';
  }

  @override
  String manageMerchantExists(String name) {
    return '”$name” finns redan';
  }

  @override
  String get manageMerchantFamily => 'Tillagd av dig';

  @override
  String get manageMerchantProvider => 'Från en bankkoppling';

  @override
  String get manageMerchantInfoBody =>
      'Byt namn, färg, webbplats eller logotyp på, slå ihop eller ta bort handlare på webben.';

  @override
  String get manageExportTitle => 'Exportera data';

  @override
  String get manageExportIntro =>
      'En export är en ZIP-fil med dina konton, transaktioner, affärer, kategorier, handlare och regler som CSV-filer, plus allt i en fil, all.ndjson. Bilagor listas men själva filerna ingår inte.';

  @override
  String get manageExportCreate => 'Skapa export';

  @override
  String get manageExportStarted =>
      'Exporten har startat. Det kan ta några minuter.';

  @override
  String get manageExportHistory => 'Exporter';

  @override
  String get manageExportEmpty =>
      'Inga exporter än. Skapa en för att få en kopia av din data.';

  @override
  String get manageExportLoadFailed => 'Det gick inte att läsa in exporterna.';

  @override
  String get manageExportAdminOnly =>
      'Bara en familjeadministratör kan exportera data.';

  @override
  String get manageExportStatusPending => 'I kö';

  @override
  String get manageExportStatusProcessing => 'Förbereds';

  @override
  String get manageExportStatusCompleted => 'Klar';

  @override
  String get manageExportStatusFailed => 'Misslyckades';

  @override
  String get manageExportDownload => 'Ladda ned';

  @override
  String get manageExportDownloadFailed =>
      'Det gick inte att ladda ned exporten.';

  @override
  String get manageExportStillPreparing =>
      'Förbereds fortfarande. Dra nedåt för att kontrollera igen.';

  @override
  String get p3roInsightsEmpty => 'Inga insikter just nu';

  @override
  String get p3roInsightsEmptyBody =>
      'Nya insikter om dina utgifter visas här.';

  @override
  String get p3roInsightsUnavailable => 'Insikter är inte aktiverade';

  @override
  String get p3roInsightsUnavailableBody =>
      'Insikter är en förhandsfunktion. Aktivera förhandsfunktioner i dina inställningar på webben för att se dem här.';

  @override
  String get p3roInsightsLoadFailed => 'Det gick inte att läsa in insikter.';

  @override
  String get p3roInsightsDismissHint => 'Svep för att avfärda';

  @override
  String get p3roConnectionsManageOnWeb => 'Hantera kopplingar på webben';

  @override
  String get p3roConnectionsEmpty => 'Inga kopplingar än';

  @override
  String get p3roConnectionsEmptyBody =>
      'Koppla en bank eller mäklare på webben för att synka konton automatiskt.';

  @override
  String get p3roConnectionsLoadFailed =>
      'Det gick inte att läsa in kopplingar.';

  @override
  String get p3roConnectionStatusConnected => 'Ansluten';

  @override
  String get p3roConnectionStatusSyncing => 'Synkar';

  @override
  String get p3roConnectionStatusNeedsAttention => 'Behöver åtgärdas';

  @override
  String get p3roConnectionStatusDeleting => 'Tas bort';

  @override
  String get p3roConnectionReconnect => 'Banken behöver att du loggar in igen.';

  @override
  String p3roConnectionAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count konton',
      one: '$count konto',
      zero: 'Inga konton',
    );
    return '$_temp0';
  }

  @override
  String p3roConnectionAccountsNeedSetup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count konton behöver konfigureras',
      one: '$count konto behöver konfigureras',
    );
    return '$_temp0';
  }

  @override
  String get p3roConnectionPendingSetup => 'Konton väntar på att konfigureras.';

  @override
  String get p3roConnectionFixOnWeb => 'Åtgärda på webben';

  @override
  String get p3roRulesManageOnWeb => 'Skapa eller ordna om regler på webben';

  @override
  String get p3roRulesEmpty => 'Inga regler än';

  @override
  String get p3roRulesEmptyBody =>
      'Regler kategoriserar, taggar och byter namn på transaktioner automatiskt. Skapa dem på webben.';

  @override
  String get p3roRulesLoadFailed => 'Det gick inte att läsa in regler.';

  @override
  String get p3roRuleActive => 'Aktiv';

  @override
  String get p3roRuleInactive => 'Inaktiv';

  @override
  String get p3roRuleResourceTransaction => 'Transaktioner';

  @override
  String get p3roRuleTitle => 'Regel';

  @override
  String get p3roRuleLoadFailed => 'Det gick inte att läsa in regeln.';

  @override
  String get p3roRuleNotFound => 'Den här regeln finns inte längre.';

  @override
  String get p3roRuleConditions => 'Villkor';

  @override
  String get p3roRuleActions => 'Åtgärder';

  @override
  String get p3roRuleRecentRuns => 'Senaste körningar';

  @override
  String get p3roRuleNoRuns => 'Regeln har inte körts än.';

  @override
  String get p3roRuleRunsLoadFailed =>
      'Det gick inte att läsa in senaste körningar.';

  @override
  String p3roRuleEffectiveFrom(String date) {
    return 'Gäller transaktioner från $date';
  }

  @override
  String get p3roRuleAllTransactions => 'Alla transaktioner';

  @override
  String p3roRuleIf(String condition) {
    return 'Om $condition';
  }

  @override
  String get p3roRuleMatchAll => 'Alla dessa stämmer';

  @override
  String get p3roRuleMatchAny => 'Något av dessa stämmer';

  @override
  String p3roRuleQuoted(String value) {
    return '”$value”';
  }

  @override
  String get p3roRuleFieldName => 'Namn';

  @override
  String get p3roRuleFieldAmount => 'Belopp';

  @override
  String get p3roRuleFieldMerchant => 'Handlare';

  @override
  String get p3roRuleFieldCategory => 'Kategori';

  @override
  String get p3roRuleFieldTag => 'Tagg';

  @override
  String get p3roRuleFieldAccount => 'Konto';

  @override
  String get p3roRuleFieldType => 'Typ';

  @override
  String get p3roRuleFieldDetails => 'Detaljer';

  @override
  String get p3roRuleFieldNotes => 'Anteckningar';

  @override
  String p3roRuleOpContains(String field, String value) {
    return '$field innehåller $value';
  }

  @override
  String p3roRuleOpNotContains(String field, String value) {
    return '$field innehåller inte $value';
  }

  @override
  String p3roRuleOpStartsWith(String field, String value) {
    return '$field börjar med $value';
  }

  @override
  String p3roRuleOpEndsWith(String field, String value) {
    return '$field slutar med $value';
  }

  @override
  String p3roRuleOpRegex(String field, String value) {
    return '$field matchar mönstret $value';
  }

  @override
  String p3roRuleOpEquals(String field, String value) {
    return '$field är $value';
  }

  @override
  String p3roRuleOpNotEquals(String field, String value) {
    return '$field är inte $value';
  }

  @override
  String p3roRuleOpEmpty(String field) {
    return '$field är tomt';
  }

  @override
  String p3roRuleOpNotEmpty(String field) {
    return '$field är inte tomt';
  }

  @override
  String p3roRuleOpGreater(String field, String value) {
    return '$field är mer än $value';
  }

  @override
  String p3roRuleOpAtLeast(String field, String value) {
    return '$field är minst $value';
  }

  @override
  String p3roRuleOpLess(String field, String value) {
    return '$field är mindre än $value';
  }

  @override
  String p3roRuleOpAtMost(String field, String value) {
    return '$field är högst $value';
  }

  @override
  String get p3roRuleTypeIncome => 'inkomst';

  @override
  String get p3roRuleTypeExpense => 'utgift';

  @override
  String get p3roRuleTypeTransfer => 'överföring';

  @override
  String get p3roRuleSomeCategory => 'en kategori';

  @override
  String get p3roRuleSomeTag => 'en tagg';

  @override
  String get p3roRuleSomeMerchant => 'en handlare';

  @override
  String get p3roRuleSomeAccount => 'ett konto';

  @override
  String p3roRuleActionSetCategory(String value) {
    return 'Sätt kategori till $value';
  }

  @override
  String p3roRuleActionAddTag(String value) {
    return 'Lägg till taggen $value';
  }

  @override
  String p3roRuleActionSetMerchant(String value) {
    return 'Sätt handlare till $value';
  }

  @override
  String p3roRuleActionRename(String value) {
    return 'Byt namn till $value';
  }

  @override
  String p3roRuleActionTransfer(String value) {
    return 'Markera som överföring eller betalning till $value';
  }

  @override
  String p3roRuleActionActivityLabel(String value) {
    return 'Sätt investeringsaktivitet till $value';
  }

  @override
  String get p3roRuleActionExclude => 'Exkludera från budgetar och rapporter';

  @override
  String get p3roRuleActionAutoCategorize => 'Kategorisera med AI';

  @override
  String get p3roRuleActionAutoMerchants => 'Identifiera handlare med AI';

  @override
  String get p3roRuleActionClassifier =>
      'Kategorisera med klassificeraren (utan AI)';

  @override
  String get p3roRuleActionFillMerchants =>
      'Fyll i saknade handlare från liknande transaktioner';

  @override
  String get p3roRuleActionEmail => 'Skicka ett e-postmeddelande';

  @override
  String get p3roRuleActionSplit => 'Dela upp transaktionen';

  @override
  String get p3roRuleRunSuccess => 'Lyckades';

  @override
  String get p3roRuleRunFailed => 'Misslyckades';

  @override
  String get p3roRuleRunPending => 'Körs';

  @override
  String get p3roRuleRunManual => 'Körd manuellt';

  @override
  String get p3roRuleRunScheduled => 'Automatisk';

  @override
  String p3roRuleRunCounts(int modified, int processed) {
    return '$modified av $processed transaktioner ändrades';
  }

  @override
  String p3roRuleRunQueued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transaktioner i kö',
      one: '$count transaktion i kö',
    );
    return '$_temp0';
  }

  @override
  String p3apZeroHoldingsHidden(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count innehav värda $amount dolda',
      one: '1 innehav värt $amount dolt',
    );
    return '$_temp0';
  }

  @override
  String p3apZeroHoldingsShown(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count innehav värda $amount visas',
      one: '1 innehav värt $amount visas',
    );
    return '$_temp0';
  }

  @override
  String get p3apShow => 'Visa';

  @override
  String get p3apHide => 'Dölj';

  @override
  String p3apAllHoldingsZero(String amount) {
    return 'Alla innehav är värda $amount';
  }

  @override
  String get p3apSetPriceTitle => 'Ange kurs';

  @override
  String get p3apSetPriceIntro =>
      'Sparar en stängningskurs för ett värdepapper som ingen kursleverantör följer. Värdena uppdateras när kontot har synkats.';

  @override
  String p3apCurrentPrice(String price) {
    return 'Nuvarande kurs: $price';
  }

  @override
  String get p3apPriceLabel => 'Kurs per andel';

  @override
  String get p3apPriceRequired => 'Ange en kurs';

  @override
  String get p3apPriceInvalid => 'Ange en kurs större än 0';

  @override
  String get p3apPriceSaved =>
      'Kursen har sparats. Värdena uppdateras när kontot har synkats.';

  @override
  String get p3apPriceSelfHostedOnly =>
      'Kurser kan bara anges på en egen server, eftersom de delas av alla på servern.';

  @override
  String get p3apPriceNotAllowed =>
      'Det här värdepapperet kan inte prissättas från dina konton. Du behöver en affär i det, eller ha det i ett kopplat konto som du kan redigera.';

  @override
  String get p3ocUpdatedJustNow => 'Uppdaterad nyss';

  @override
  String p3ocUpdatedMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Uppdaterad för $count minuter sedan',
      one: 'Uppdaterad för $count minut sedan',
    );
    return '$_temp0';
  }

  @override
  String p3ocUpdatedHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Uppdaterad för $count timmar sedan',
      one: 'Uppdaterad för $count timme sedan',
    );
    return '$_temp0';
  }

  @override
  String p3ocUpdatedDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Uppdaterad för $count dagar sedan',
      one: 'Uppdaterad för $count dag sedan',
    );
    return '$_temp0';
  }

  @override
  String get p3ocOfflineMayBeOutdated =>
      'Du är offline. Uppgifterna som visas kan vara inaktuella.';

  @override
  String get p3rpTitle => 'Rapporter';

  @override
  String get p3rpPeriodMonth => 'Månad';

  @override
  String get p3rpPeriodThreeMonths => '3 mån';

  @override
  String get p3rpPeriodYearToDate => 'Hittills i år';

  @override
  String get p3rpPeriodYear => '1 år';

  @override
  String get p3rpNetWorth => 'Nettoförmögenhet';

  @override
  String get p3rpNetWorthChartLabel => 'Nettoförmögenhet under vald period';

  @override
  String get p3rpNetWorthNoHistory =>
      'Ingen saldohistorik för den här perioden.';

  @override
  String get p3rpNetWorthFailed =>
      'Det gick inte att läsa in historiken för nettoförmögenheten.';

  @override
  String get p3rpCashFlow => 'Kassaflöde';

  @override
  String get p3rpIn => 'In';

  @override
  String get p3rpOut => 'Ut';

  @override
  String get p3rpSaved => 'Sparat';

  @override
  String p3rpSavedShare(String percent) {
    return '$percent av In';
  }

  @override
  String get p3rpCashFlowFailed => 'Det gick inte att läsa in kassaflödet.';

  @override
  String get p3rpSpending => 'Utgifter per kategori';

  @override
  String get p3rpNoSpending => 'Inga utgifter under den här perioden.';

  @override
  String p3rpShowAll(int count) {
    return 'Visa alla ($count)';
  }

  @override
  String get p3rpShowLess => 'Visa färre';

  @override
  String p3rpAboveNormal(String percent) {
    return '$percent över det normala';
  }

  @override
  String get dsToday => 'I dag';

  @override
  String get dsYesterday => 'I går';

  @override
  String get dsCancel => 'Avbryt';

  @override
  String get dsSave => 'Spara';

  @override
  String get dsDone => 'Klar';

  @override
  String get dsSplit => 'Delad';

  @override
  String get dsTransfer => 'Överföring';

  @override
  String get dsUncategorized => 'Okategoriserad';

  @override
  String get dsCategorize => 'Kategorisera';

  @override
  String get dsDelete => 'Radera';

  @override
  String get dsPending => 'Väntar';

  @override
  String get dsFailed => 'Misslyckades';

  @override
  String get dsaSelect => 'Välj';

  @override
  String dsaNoMatchesFor(String query) {
    return 'Inga träffar för ”$query”';
  }

  @override
  String get dsaNoMatches => 'Inga träffar';

  @override
  String get dsaNoMatchesBody =>
      'Prova färre filter eller ett längre datumintervall.';

  @override
  String get dsaEmptyTitle => 'Inga transaktioner än';

  @override
  String get dsaEmptyBody =>
      'Lägg till en med + eller koppla ett konto på webben.';

  @override
  String get dsaEmptyMonthBody =>
      'Transaktioner du lägger till eller synkar den här månaden visas här.';

  @override
  String dsaSummary(String range, String inflow, String outflow) {
    return '$range · In $inflow · Ut $outflow';
  }

  @override
  String dsaSummaryPartial(int loaded, int total) {
    return 'Summor för de $loaded av $total som har laddats';
  }

  @override
  String get dsaCategorizeFailed =>
      'Det gick inte att kategorisera transaktionen.';

  @override
  String get dspSyncedJustNow => 'synkat nyss';

  @override
  String dspSyncedMinutesAgo(int count) {
    return 'synkat för $count min sedan';
  }

  @override
  String dspSyncedHoursAgo(int count) {
    return 'synkat för $count h sedan';
  }

  @override
  String dspSyncedDaysAgo(int count) {
    return 'synkat för $count d sedan';
  }

  @override
  String dspSharesAtPrice(String quantity, String price) {
    return '$quantity st · $price';
  }

  @override
  String get dspClearFilter => 'Rensa filter';

  @override
  String get dspSelect => 'Markera transaktioner';

  @override
  String get dspDoneSelecting => 'Klar med markering';

  @override
  String get dspDeleteSelected => 'Radera markerade';

  @override
  String get dspNewTransaction => 'Ny transaktion';

  @override
  String dstSplitValue(int count) {
    return 'Delad ($count)';
  }

  @override
  String get dstAddNote => 'Lägg till en anteckning';

  @override
  String get dstAddTag => 'Lägg till tagg';

  @override
  String get dstRecurring => 'Återkommande';

  @override
  String get dstRecurringSetUp => 'Ställ in';

  @override
  String get dstOpenOnWeb => 'Öppna på webben';

  @override
  String get dstDeleteTransaction => 'Radera transaktion';

  @override
  String get dstEditAmount => 'Ändra belopp';

  @override
  String get dstSearchCategories => 'Sök kategorier';

  @override
  String get dstNoCategoryMatches => 'Inga kategorier matchar';

  @override
  String get dstNoCategoryMatchesBody => 'Prova en annan sökning.';

  @override
  String get dstNoCategories => 'Inga kategorier än';

  @override
  String get dshOutdated => 'Inaktuell';

  @override
  String get dshShowAmounts => 'Visa belopp';

  @override
  String get dshHideAmounts => 'Dölj belopp';

  @override
  String dshSpendingAbove(String percent) {
    return 'Utgifter $percent över det normala';
  }

  @override
  String dshSpendingBelow(String percent) {
    return 'Utgifter $percent under det normala';
  }

  @override
  String get dshSpendingAboutNormal => 'Utgifter ungefär som vanligt';

  @override
  String get dshRecent => 'Senaste';

  @override
  String get dshSeeAll => 'Visa alla';

  @override
  String get dshAccounts => 'Konton';

  @override
  String get dshAddAccount => 'Lägg till konto';

  @override
  String dshGroupTitle(String type, int count) {
    return '$type · $count';
  }

  @override
  String dshEmptyAccounts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tomma konton',
      one: '1 tomt konto',
    );
    return '$_temp0';
  }

  @override
  String get dshShow => 'Visa';

  @override
  String get dshHide => 'Dölj';

  @override
  String get dshGroupNoAccounts => 'Inga konton av den här typen';

  @override
  String get dshTypeDepository => 'Kontanter';

  @override
  String get dshTypeCreditCard => 'Kreditkort';

  @override
  String get dshTypeInvestment => 'Investeringar';

  @override
  String get dshTypeCrypto => 'Krypto';

  @override
  String get dshTypeProperty => 'Fastigheter';

  @override
  String get dshTypeVehicle => 'Fordon';

  @override
  String get dshTypeOtherAsset => 'Övriga tillgångar';

  @override
  String get dshTypeLoan => 'Lån';

  @override
  String get dshTypeOtherLiability => 'Övriga skulder';

  @override
  String get dshEmptyBody =>
      'Anslut en bank på webben, eller lägg till ett manuellt konto som ett hus eller en bil.';

  @override
  String get dshConnectOnWeb => 'Anslut på webben';

  @override
  String get dshAddManualAccount => 'Lägg till ett manuellt konto';

  @override
  String dshOfflineShowing(String age) {
    return 'Offline · visar data från för $age sedan';
  }

  @override
  String get dshOfflineShowingJustNow =>
      'Offline · visar data från alldeles nyss';

  @override
  String dshAgoMinutes(int count) {
    return '$count min';
  }

  @override
  String dshAgoHours(int count) {
    return '$count h';
  }

  @override
  String dshAgoDays(int count) {
    return '$count d';
  }

  @override
  String get dshAgoNow => 'nu';

  @override
  String get dshSyncShort => 'Synka';

  @override
  String get dshSyncFailedShort => 'Misslyckades';

  @override
  String get dshAddTransaction => 'Lägg till';

  @override
  String get ds2iEmptyTitle => 'Inga investeringar ännu';

  @override
  String get ds2iEmptyBody =>
      'Koppla en mäklare eller lägg till ett investeringskonto på webben.';

  @override
  String get ds2iCurrency => 'Valuta';

  @override
  String get ds2pNoLimit => 'ingen gräns';

  @override
  String ds2pOverBy(String amount) {
    return '$amount över';
  }

  @override
  String get ds2pLeft => 'kvar';

  @override
  String get ds2pOver => 'över';

  @override
  String ds2pSpentOf(String spent, String budgeted) {
    return '$spent av $budgeted använt';
  }

  @override
  String ds2pDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagar kvar',
      one: '1 dag kvar',
    );
    return '$_temp0';
  }

  @override
  String get ds2pNoBudgetBody =>
      'Budgetar skapas på webben. De visas här när de finns.';

  @override
  String get ds2pSetUpOnWeb => 'Skapa på webben';

  @override
  String get ds2pEditOnWeb => 'Redigera på webben';

  @override
  String ds2pMonthlySummary(String outflow, String inflow) {
    return 'Per månad ut $outflow · in $inflow';
  }

  @override
  String get ds2pResume => 'Återuppta';

  @override
  String get ds2sProfileOnWeb => 'Profil på webben';

  @override
  String get ds2sImportUpload => 'Importera · Ladda upp kontoutdrag';

  @override
  String get ds2sImportCsv => 'Importera CSV';

  @override
  String get ds2sMetadata => 'Kategorier, taggar, handlare';

  @override
  String get ds2sThemeAuto => 'Auto';

  @override
  String get ds2sFaceIdLock => 'Face ID-lås';

  @override
  String get ds2sTouchIdLock => 'Touch ID-lås';

  @override
  String get ds2sBiometricLock => 'Biometriskt lås';

  @override
  String get ds2sPasswordPasskeys => 'Lösenord och passkeys';

  @override
  String get ds2sVersion => 'Version';

  @override
  String get ds2sCheckForUpdates => 'Sök efter uppdateringar';

  @override
  String get ds2sDebugLogs => 'Felsökningsloggar';

  @override
  String get ds2sSignOut => 'Logga ut';

  @override
  String get ds2sAccountActionsLink =>
      'Rensa lokal data · Återställ · Radera konto';

  @override
  String get ds2sAccountActions => 'Kontoåtgärder';

  @override
  String get ds2sClearLocalData => 'Rensa lokal data';

  @override
  String get ds2sResetAccount => 'Återställ användarkonto';

  @override
  String get ds2sDeleteAccount => 'Radera användarkonto';

  @override
  String ds3rSince(String date) {
    return 'sedan $date';
  }

  @override
  String ds3rOtherCurrency(String amount, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Även $amount på $count konton',
      one: 'Även $amount på 1 konto',
    );
    return '$_temp0';
  }

  @override
  String get ds3rEmptyBody => 'Prova en längre period.';

  @override
  String get ds3fNewTransaction => 'Ny transaktion';

  @override
  String get ds3fAdd => 'Lägg till';

  @override
  String get ds3fClearCategory => 'Ta bort kategori';

  @override
  String get ds3fOptional => 'Valfritt';

  @override
  String ds3fWasBalance(String amount) {
    return 'Var $amount';
  }

  @override
  String get ds3fAsOf => 'Per datum';

  @override
  String get ds3fNote => 'Anteckning';

  @override
  String get ds3fFee => 'Avgifter';

  @override
  String get ds3fPrice => 'Pris';

  @override
  String get ds3aTitle => 'Assistent';

  @override
  String get ds3aNewChat => 'Ny chatt';

  @override
  String get ds3aSearchHint => 'Sök i chattar';

  @override
  String get ds3aClearSearch => 'Rensa sökning';

  @override
  String get ds3aEmptyTitle => 'Fråga om din ekonomi';

  @override
  String get ds3aEmptyBody => '”Hur mycket lade jag på mat förra månaden?”';

  @override
  String ds3aNoMatches(String query) {
    return 'Inga chattar matchar ”$query”';
  }

  @override
  String get ds3aNoMatchesBody => 'Prova ett annat ord.';

  @override
  String ds3aSelectedCount(int count) {
    return '$count markerade';
  }

  @override
  String get ds3aSelectAll => 'Markera alla';

  @override
  String get ds3aDeleteSelected => 'Radera markerade';

  @override
  String get ds3aDeleteFailed => 'Det gick inte att radera chatten.';

  @override
  String get ds3aNow => 'nu';

  @override
  String ds3aMinutesShort(int minutes) {
    return '$minutes min';
  }

  @override
  String ds3aHoursShort(int hours) {
    return '$hours tim';
  }

  @override
  String get ds3aBack => 'Chattar';

  @override
  String get ds3aMenu => 'Chattåtgärder';

  @override
  String get ds3aRename => 'Byt namn';

  @override
  String get ds3aRefresh => 'Uppdatera';

  @override
  String get ds3aComposerHint => 'Fråga vad som helst…';

  @override
  String get ds3aSend => 'Skicka';

  @override
  String get ds3aDisclaimer => 'AI-svar är endast informativa.';

  @override
  String get ds3aThinking => 'Tänker';

  @override
  String get ds3aReplyFailed => 'Det gick inte att få ett svar.';

  @override
  String get ds3aRetry => 'Försök igen';

  @override
  String get ds3aSendFailed => 'Det gick inte att skicka meddelandet.';

  @override
  String get ds4aServerRow => 'Server';

  @override
  String get ds4aApiKeyLink => 'Logga in med en API-nyckel';

  @override
  String get ds4aShowPassword => 'Visa lösenord';

  @override
  String get ds4aHidePassword => 'Dölj lösenord';

  @override
  String get ds4aDismissError => 'Stäng';

  @override
  String get ds4aCodeLabel => 'Kod';

  @override
  String get ds4aCodeHint => '6-siffrig kod';

  @override
  String get ds4aLockedTitle => 'Sure+ är låst';

  @override
  String get ds4aUnlockFaceId => 'Lås upp med Face ID';

  @override
  String get ds4aUnlockTouchId => 'Lås upp med Touch ID';

  @override
  String get ds4aIntroTitle => 'Introduktionen kommer snart';

  @override
  String get ds4aIntroBody =>
      'Vi bygger en mer genomarbetad introduktion för att lära oss om dina mål, milstolpar och vardagsbehov. Börja under tiden en konversation med Sure på fliken Assistent och berätta var du befinner dig i din ekonomiska resa.';

  @override
  String get ds4tLogShare => 'Dela loggar';

  @override
  String get ds4tLogAutoScroll => 'Rulla automatiskt';

  @override
  String get ds4tCalendarMonthlyChange => 'Förändring under månaden';

  @override
  String get ds4tCalendarNoAccounts => 'Inga konton av den här typen';

  @override
  String get ds4dExportEmptyTitle => 'Inga exporter än';

  @override
  String get ds4dExportEmptyBody =>
      'Skapa en för att få en kopia av dina data.';

  @override
  String get ds4dFormatsHeader => 'Format';

  @override
  String get ds4dChoose => 'Välj';

  @override
  String txnParityTransferTo(String account) {
    return 'Till $account';
  }

  @override
  String txnParityTransferFrom(String account) {
    return 'Från $account';
  }

  @override
  String get txnParityTransferOtherAccount => 'ett annat konto';

  @override
  String get txnParityBudgetsTitle => 'Budgetar och rapporter';

  @override
  String get txnParityBudgetsExcluded => 'Exkluderad';

  @override
  String get txnParityBudgetsOneTime => 'Engångs';

  @override
  String get txnParityBudgetsFundsMovement => 'Överföring, räknas inte';

  @override
  String get txnParityBudgetsCcPayment => 'Kortbetalning, räknas inte';

  @override
  String get txnParityBudgetsCountedExpense => 'Räknas som utgift';

  @override
  String get txnParityBudgetsIncluded => 'Inkluderad';

  @override
  String get txnParityChangeOnWeb => 'Ändra på webben';

  @override
  String get txnParityMarkRecurring => 'Markera som återkommande';

  @override
  String get txnParityRecurringOffline =>
      'Återkommande kräver en internetanslutning.';

  @override
  String get txnParityOpenOnWebSubtitle =>
      'Bilagor, matchning av överföringar och mer';

  @override
  String get billsSectionOverdue => 'Försenade';

  @override
  String get billsSectionDue => 'Förfaller denna månad';

  @override
  String billsSectionPaid(int count) {
    return 'Betalda denna månad · $count';
  }

  @override
  String get billsSectionLater => 'Senare';

  @override
  String billsSectionPaused(int count) {
    return 'Pausade · $count';
  }

  @override
  String get billsShow => 'Visa';

  @override
  String get billsHide => 'Dölj';

  @override
  String get billsLeftToPay => 'kvar att betala';

  @override
  String billsPaidOf(String paid, String total, int paidCount, int billCount) {
    String _temp0 = intl.Intl.pluralLogic(
      billCount,
      locale: localeName,
      other: '$billCount räkningar',
      one: '1 räkning',
    );
    return '$paid betalt av $total · $paidCount av $_temp0';
  }

  @override
  String billsOtherCurrencies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count räkningar',
      one: '1 räkning',
    );
    return 'Även $_temp0 i andra valutor';
  }

  @override
  String billsDueOn(String date) {
    return 'Förföll $date';
  }

  @override
  String billsPaidOn(String date) {
    return 'Betald $date';
  }

  @override
  String get billsAutopay => 'Autobetalning';

  @override
  String get billsTypeSubscription => 'Prenumeration';

  @override
  String get billsTypeInstallment => 'Avbetalning';

  @override
  String billsTrialEnds(String date) {
    return 'Provperiod slutar $date';
  }

  @override
  String billsRenews(String date) {
    return 'Förnyas $date';
  }

  @override
  String get billsPay => 'Betala';

  @override
  String billsPaySemantics(String name) {
    return 'Öppna betalsidan för $name';
  }

  @override
  String get billsEmptyTitle => 'Inga räkningar än';

  @override
  String get billsEmptyBody =>
      'Markera en transaktion som återkommande, eller hitta räkningar i din historik på webben.';

  @override
  String get billsFindOnWeb => 'Hitta räkningar på webben';

  @override
  String get billsLoadFailed => 'Kunde inte läsa in räkningar';

  @override
  String get billsRefreshFailed => 'Kunde inte uppdatera räkningar.';

  @override
  String get billsOfflineTitle => 'Du är offline';

  @override
  String get billsOfflineBody => 'Räkningar kräver en internetanslutning.';

  @override
  String get spdConnectionSyncNow => 'Synka nu';

  @override
  String get spdConnectionDisconnect => 'Koppla från';

  @override
  String spdConnectionDisconnectTitle(String name) {
    return 'Koppla från $name?';
  }

  @override
  String get spdConnectionDisconnectBody =>
      'Dess konton slutar synkas. Du kan ansluta igen på webben.';

  @override
  String get spdConnectionStatusScheduled => 'Schemalagd för borttagning';

  @override
  String get spdConnectionErrorSyncNotSupported =>
      'Den här anslutningen uppdateras från din enhet, inte från servern. Hantera den på webben.';

  @override
  String get spdConnectionErrorDisconnectNotSupported =>
      'Den här anslutningen kan inte kopplas från här. Koppla från den på webben.';

  @override
  String get spdConnectionErrorManualSync =>
      'Den här anslutningen behöver en säkerhetskod för att synkas. Synka den på webben.';

  @override
  String get spdConnectionErrorNotConnected =>
      'Den här anslutningen är inte auktoriserad. Anslut den igen på webben.';

  @override
  String get spdConnectionErrorReconnect =>
      'Den här anslutningen behöver en ny inloggning. Logga in igen på webben.';

  @override
  String get spdConnectionErrorUnlinkFailed =>
      'Några konton kunde inte kopplas loss, så anslutningen är fortfarande ansluten. Försök igen på webben.';

  @override
  String get spdConnectionErrorForbidden =>
      'Bara en administratör i hushållet, eller för Plaid den som anslöt den, kan hantera den här anslutningen.';

  @override
  String get spdConnectionErrorScope =>
      'Den här inloggningen kan bara läsa data. Hantera anslutningen på webben.';

  @override
  String get spdConnectionActionFailed => 'Kunde inte uppdatera anslutningen.';

  @override
  String get spmReadOnlyAccess =>
      'Den här inloggningen kan bara visa data. Logga in igen med full åtkomst för att göra ändringar.';

  @override
  String get spmCategoryEdit => 'Redigera kategori';

  @override
  String get spmCategoryIconHintEdit => 'Ändra ikonen på webben.';

  @override
  String get spmCategorySaved => 'Kategorin har sparats';

  @override
  String get spmCategoryDeleted => 'Kategorin har tagits bort';

  @override
  String get spmCategoryDelete => 'Ta bort kategori';

  @override
  String spmCategoryDeleteTitle(String name) {
    return 'Ta bort ”$name”?';
  }

  @override
  String get spmCategoryDeleteBody =>
      'Transaktionerna flyttas till kategorin du väljer nedan, eller blir okategoriserade. Det går inte att ångra.';

  @override
  String spmCategoryDeleteSubcategories(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dess $count underkategorier blir huvudkategorier.',
      one: 'Dess underkategori blir en huvudkategori.',
    );
    return '$_temp0';
  }

  @override
  String get spmCategoryDeleteMoveTo => 'Flytta transaktioner till';

  @override
  String get spmCategoryDeleteUncategorized => 'Lämna okategoriserade';

  @override
  String get spmMerchantEdit => 'Redigera handlare';

  @override
  String get spmMerchantSaved => 'Handlaren har sparats';

  @override
  String get spmMerchantDeleted => 'Handlaren har tagits bort';

  @override
  String get spmMerchantDelete => 'Ta bort handlare';

  @override
  String spmMerchantDeleteTitle(String name) {
    return 'Ta bort ”$name”?';
  }

  @override
  String get spmMerchantDeleteBody =>
      'Transaktionerna behåller sina uppgifter men förlorar handlaren, och dess återkommande transaktioner tas bort. Det går inte att ångra.';

  @override
  String get spmProfileYou => 'Du';

  @override
  String get spmProfileFirstName => 'Förnamn';

  @override
  String get spmProfileLastName => 'Efternamn';

  @override
  String get spmProfileEmail => 'E-post';

  @override
  String get spmProfileChangeOnWeb => 'Ändra på webben';

  @override
  String get spmProfileChangeOnWebSubtitle => 'E-post, lösenord och MFA';

  @override
  String get spmProfileLanguage => 'Språk';

  @override
  String get spmProfileLanguageAuto => 'Automatiskt';

  @override
  String get spmProfileDefaultPeriod => 'Standardperiod';

  @override
  String get spmProfileHousehold => 'Hushåll';

  @override
  String get spmProfileHouseholdName => 'Namn';

  @override
  String get spmProfileCurrency => 'Valuta';

  @override
  String get spmProfileCountry => 'Land';

  @override
  String get spmProfileTimezone => 'Tidszon';

  @override
  String get spmProfileDateFormat => 'Datumformat';

  @override
  String get spmProfileHouseholdFooter =>
      'Hushållets inställningar gäller för alla i hushållet.';

  @override
  String get spmProfileNotSet => 'Inte angivet';

  @override
  String get spmProfileSaved => 'Profilen har sparats';

  @override
  String get spmProfileLoadFailed => 'Det gick inte att läsa in din profil.';

  @override
  String get spmPeriodLastDay => 'Senaste dygnet';

  @override
  String get spmPeriodCurrentWeek => 'Denna vecka';

  @override
  String get spmPeriodLast7Days => 'Senaste 7 dagarna';

  @override
  String get spmPeriodCurrentMonth => 'Denna månad';

  @override
  String get spmPeriodLastMonth => 'Förra månaden';

  @override
  String get spmPeriodLast30Days => 'Senaste 30 dagarna';

  @override
  String get spmPeriodLast90Days => 'Senaste 90 dagarna';

  @override
  String get spmPeriodCurrentYear => 'Detta år';

  @override
  String get spmPeriodLast365Days => 'Senaste 365 dagarna';

  @override
  String get spmPeriodLast5Years => 'Senaste 5 åren';

  @override
  String get spmPeriodLast10Years => 'Senaste 10 åren';

  @override
  String get spmPeriodAllTime => 'All tid';

  @override
  String spgSectionActive(int count) {
    return 'Aktiva · $count';
  }

  @override
  String spgSectionPaused(int count) {
    return 'Pausade · $count';
  }

  @override
  String spgSectionCompleted(int count) {
    return 'Avklarade · $count';
  }

  @override
  String spgSectionArchived(int count) {
    return 'Arkiverade · $count';
  }

  @override
  String get spgNewGoal => 'Nytt mål';

  @override
  String get spgEditGoal => 'Redigera mål';

  @override
  String get spgCreate => 'Skapa';

  @override
  String get spgEmptyTitle => 'Inga mål än';

  @override
  String get spgEmptyBody =>
      'Sätt ett mål, koppla kontona du sparar på och se hur det växer.';

  @override
  String get spgCreateFirst => 'Skapa ditt första mål';

  @override
  String get spgPreviewTitle => 'Mål är en förhandsfunktion';

  @override
  String get spgPreviewBody =>
      'Mål kräver förhandsfunktioner, och de är avstängda för ditt konto.';

  @override
  String get spgPreviewAction => 'Slå på förhandsfunktioner på webben';

  @override
  String get spgLoadFailed => 'Det gick inte att läsa in dina mål';

  @override
  String spgDue(String date) {
    return 'Klart $date';
  }

  @override
  String get spgNoDate => 'Inget datum';

  @override
  String get spgReserve => 'Buffert';

  @override
  String get spgPastDue => 'Försenat';

  @override
  String spgDaysLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dagar kvar',
      one: '1 dag kvar',
    );
    return '$_temp0';
  }

  @override
  String spgMonthsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count månader kvar',
      one: '1 månad kvar',
    );
    return '$_temp0';
  }

  @override
  String spgAmountOf(String current, String target) {
    return '$current av $target';
  }

  @override
  String spgCatchUp(String amount) {
    return 'Spara $amount/mån för att komma ikapp';
  }

  @override
  String spgPendingPledges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count väntande insättningar',
      one: '1 väntande insättning',
    );
    return '$_temp0';
  }

  @override
  String get spgStatusOnTrack => 'I fas';

  @override
  String get spgStatusBehind => 'Efter';

  @override
  String get spgStatusReached => 'Uppnått';

  @override
  String get spgStatusOpen => 'Öppet';

  @override
  String get spgStatusFunded => 'Bufferten är full';

  @override
  String get spgStatusDepleted => 'Behöver fyllas på';

  @override
  String get spgStatusPaused => 'Pausat';

  @override
  String get spgStatusCompleted => 'Avklarat';

  @override
  String get spgStatusArchived => 'Arkiverat';

  @override
  String spgOfTarget(String target) {
    return 'av $target';
  }

  @override
  String spgOfTargetDue(String target, String date) {
    return 'av $target · klart $date';
  }

  @override
  String get spgSavedToward => 'Jag har sparat till det här';

  @override
  String get spgPledgeRecord => 'Spara';

  @override
  String get spgPledgeFrom => 'Från';

  @override
  String get spgPledgeHint => 'Sure bekräftar det när pengarna syns på kontot.';

  @override
  String get spgPendingHeader => 'Väntande insättningar';

  @override
  String spgPledgeFromAccount(String amount, String account) {
    return '$amount från $account';
  }

  @override
  String spgPledgeAmount(String amount) {
    return '$amount utlovat';
  }

  @override
  String get spgPledgeConfirmsTransfer => 'Bekräftas när den syns';

  @override
  String get spgPledgeConfirmsManual => 'Bekräftas vid nästa saldouppdatering';

  @override
  String spgPledgeExpires(String confirm, String date) {
    return '$confirm · går ut $date';
  }

  @override
  String get spgPledgeExtend => 'Förläng';

  @override
  String get spgPledgeExtended => 'Insättningen förlängdes med 7 dagar';

  @override
  String get spgPledgeCancelTitle => 'Avbryta insättningen?';

  @override
  String spgPledgeCancelBody(String amount) {
    return 'Insättningen på $amount tas bort. Du kan registrera en ny när du vill.';
  }

  @override
  String get spgPledgeCancelConfirm => 'Avbryt insättning';

  @override
  String get spgPledgeKeep => 'Behåll';

  @override
  String get spgPledgeCancelled => 'Insättningen avbröts';

  @override
  String get spgPledgeSaved => 'Insättningen registrerades';

  @override
  String get spgFundingHeader => 'Konton som finansierar';

  @override
  String get spgWholeBalance => 'Hela saldot';

  @override
  String get spgPlanHeader => 'Plan';

  @override
  String get spgMonthlyTarget => 'Månadsmål';

  @override
  String get spgPace => 'Takt';

  @override
  String spgPerMonth(String amount) {
    return '$amount/mån';
  }

  @override
  String get spgProjected => 'Beräknat klart';

  @override
  String get spgTimeLeft => 'Tid kvar';

  @override
  String get spgNotes => 'Anteckningar';

  @override
  String get spgEdit => 'Redigera';

  @override
  String get spgLifecycleOnWeb => 'Pausa eller arkivera på webben';

  @override
  String get spgDelete => 'Ta bort mål';

  @override
  String get spgDeleteTitle => 'Ta bort mål?';

  @override
  String spgDeleteBody(String name) {
    return 'Ta bort \"$name\"? Dess insättningar tas också bort. Det går inte att ångra.';
  }

  @override
  String get spgDeleted => 'Målet togs bort';

  @override
  String get spgSaved => 'Målet sparades';

  @override
  String get spgCreated => 'Målet skapades';

  @override
  String get spgIconAndColor => 'Ikon och färg';

  @override
  String get spgIcon => 'Ikon';

  @override
  String get spgKindOneOff => 'Engångsmål';

  @override
  String get spgKindOneOffHint =>
      'Spara till något och stäng målet när du använder pengarna.';

  @override
  String get spgKindReserve => 'Buffert';

  @override
  String get spgKindReserveHint =>
      'Ett saldo att behålla, till exempel en buffert för oväntade utgifter. Den har inget slutdatum.';

  @override
  String get spgName => 'Namn';

  @override
  String get spgNameHint => 'Buffert';

  @override
  String get spgNameRequired => 'Ange ett namn';

  @override
  String get spgTarget => 'Mål';

  @override
  String get spgTargetInvalid => 'Ange ett belopp över noll';

  @override
  String get spgBy => 'Senast';

  @override
  String get spgFundFrom => 'Finansiera från';

  @override
  String get spgFundFromHint =>
      'Lämna beloppet tomt för att använda kontots hela saldo.';

  @override
  String get spgNoFundable =>
      'Lägg till ett kontant-, investerings- eller kryptokonto för att finansiera ett mål.';

  @override
  String get spgAccountsRequired =>
      'Välj minst ett konto som finansierar målet.';

  @override
  String get spbEditTotals => 'Ändra totaler';

  @override
  String get spbTotalBudget => 'Total budget';

  @override
  String get spbExpectedIncome => 'Förväntad inkomst';

  @override
  String spbSpentThisMonth(String amount) {
    return '$amount spenderat den här månaden';
  }

  @override
  String spbSpentInPeriod(String amount) {
    return '$amount spenderat';
  }

  @override
  String get spbRollover => 'För över det som blir kvar';

  @override
  String get spbTransactions => 'Transaktioner';

  @override
  String get spbSharedReadOnly =>
      'Den här budgeten är delad med dig med läsbehörighet.';

  @override
  String get spbInvalidAmount => 'Ange ett belopp på 0 eller mer.';

  @override
  String get spbSaveFailed => 'Det gick inte att spara budgeten.';

  @override
  String get spbSaved => 'Budgeten har sparats';

  @override
  String get sprRulesReorderOnWeb => 'Ordna om regler på webben';

  @override
  String get sprRulesEmptyBody =>
      'Regler kategoriserar, taggar och byter namn på transaktioner automatiskt. Tryck på + för att skapa en.';

  @override
  String get sprRuleNew => 'Ny regel';

  @override
  String get sprRuleEdit => 'Redigera regel';

  @override
  String get sprRuleName => 'Namn';

  @override
  String get sprRuleNameHint => 'Valfritt';

  @override
  String get sprRuleIfHeader => 'Om en transaktion';

  @override
  String get sprRuleThenHeader => 'Då';

  @override
  String get sprRuleAddCondition => 'Lägg till villkor';

  @override
  String get sprRuleAddGroup => 'Lägg till villkorsgrupp';

  @override
  String get sprRuleAddAction => 'Lägg till åtgärd';

  @override
  String get sprRuleNoConditions =>
      'Inga villkor: regeln gäller alla transaktioner.';

  @override
  String get sprRuleRemove => 'Ta bort';

  @override
  String get sprRulePickField => 'Fält';

  @override
  String get sprRulePickOperator => 'Jämförelse';

  @override
  String get sprRulePickValue => 'Värde';

  @override
  String get sprRulePickAction => 'Åtgärd';

  @override
  String get sprRulePickGroup => 'Matcha';

  @override
  String get sprRuleChooseValue => 'Välj…';

  @override
  String get sprRuleEnterValue => 'Ange ett värde';

  @override
  String sprRuleTagsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count taggar',
      one: '1 tagg',
    );
    return '$_temp0';
  }

  @override
  String get sprOpLike => 'innehåller';

  @override
  String get sprOpNotLike => 'innehåller inte';

  @override
  String get sprOpStartsWith => 'börjar med';

  @override
  String get sprOpEndsWith => 'slutar med';

  @override
  String get sprOpRegex => 'matchar mönstret';

  @override
  String get sprOpEquals => 'är';

  @override
  String get sprOpNotEquals => 'är inte';

  @override
  String get sprOpEmpty => 'är tomt';

  @override
  String get sprOpNotEmpty => 'är inte tomt';

  @override
  String get sprOpGreater => 'är mer än';

  @override
  String get sprOpAtLeast => 'är minst';

  @override
  String get sprOpLess => 'är mindre än';

  @override
  String get sprOpAtMost => 'är högst';

  @override
  String get sprActSetCategory => 'Sätt kategori';

  @override
  String get sprActAddTags => 'Lägg till taggar';

  @override
  String get sprActSetMerchant => 'Sätt handlare';

  @override
  String get sprActRename => 'Byt namn till';

  @override
  String get sprActActivity => 'Sätt investeringsaktivitet';

  @override
  String get sprActTransfer => 'Markera som överföring eller betalning till';

  @override
  String get sprRuleSplitOnWeb => 'Redigera uppdelningen på webben';

  @override
  String get sprRuleNeedsAction => 'Lägg till minst en åtgärd.';

  @override
  String get sprRuleMissingValue => 'Fyll i alla värden eller ta bort raden.';

  @override
  String get sprRuleEmptyGroup =>
      'Lägg till ett villkor i varje grupp eller ta bort gruppen.';

  @override
  String get sprRuleAmountInvalid => 'Ange ett tal.';

  @override
  String get sprRuleSaved => 'Regeln sparades';

  @override
  String get sprRuleDeleted => 'Regeln togs bort';

  @override
  String get sprRuleApply => 'Tillämpa på tidigare transaktioner';

  @override
  String get sprRuleApplying => 'Tillämpar… det kan ta några sekunder.';

  @override
  String get sprRuleApplyTitle => 'Tillämpa den här regeln?';

  @override
  String sprRuleApplyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Den ändrar $count transaktioner.',
      one: 'Den ändrar 1 transaktion.',
    );
    return '$_temp0';
  }

  @override
  String sprRuleApplyAbove(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aktiva regler körs före den.',
      one: '1 aktiv regel körs före den.',
    );
    return '$_temp0';
  }

  @override
  String sprRuleApplyAiCost(String cost) {
    return 'Använder AI-kategorisering · cirka $cost';
  }

  @override
  String get sprRuleApplyAiNoCost =>
      'Använder AI-kategorisering · okänd kostnad';

  @override
  String get sprRuleApplyConfirm => 'Tillämpa';

  @override
  String sprRuleApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ändrade $count transaktioner',
      one: 'Ändrade 1 transaktion',
    );
    return '$_temp0';
  }

  @override
  String get sprRuleApplyRunning =>
      'En annan regel körs. Försök igen om en stund.';

  @override
  String get sprRuleEditLink => 'Redigera';

  @override
  String get sprRuleDuplicate => 'Duplicera';

  @override
  String get sprRuleDelete => 'Ta bort';

  @override
  String get sprRuleDeleteTitle => 'Ta bort den här regeln?';

  @override
  String get sprRuleDeleteBody =>
      'Transaktioner som den redan har ändrat förblir som de är.';

  @override
  String sprRuleCopyName(String name) {
    return '$name (kopia)';
  }

  @override
  String get spaAddAccount => 'Lägg till konto';

  @override
  String get spaEditAccount => 'Redigera konto';

  @override
  String get spaConnectBank => 'Anslut en bank';

  @override
  String get spaConnectBankSub => 'Länka konton på webben';

  @override
  String get spaOrByHand => 'Eller lägg till ett manuellt';

  @override
  String get spaTypeDepository => 'Kontanter eller bank';

  @override
  String get spaTypeInvestment => 'Investering';

  @override
  String get spaTypeCrypto => 'Krypto';

  @override
  String get spaTypeProperty => 'Fastighet';

  @override
  String get spaTypeVehicle => 'Fordon';

  @override
  String get spaTypeCreditCard => 'Kreditkort';

  @override
  String get spaTypeLoan => 'Lån';

  @override
  String get spaTypeOtherAsset => 'Annan tillgång';

  @override
  String get spaTypeOtherLiability => 'Annan skuld';

  @override
  String get spaBackToType => '‹ Typ';

  @override
  String get spaAdd => 'Lägg till';

  @override
  String get spaCurrentBalance => 'Nuvarande saldo';

  @override
  String get spaCurrentValue => 'Nuvarande värde';

  @override
  String get spaAmountOwed => 'Skuldbelopp';

  @override
  String get spaSyncedFromBank => 'Synkas från din bank';

  @override
  String get spaName => 'Namn';

  @override
  String get spaNameHint => 'Obligatoriskt';

  @override
  String get spaNameRequired => 'Ange ett namn';

  @override
  String get spaBalanceRequired => 'Ange ett belopp';

  @override
  String get spaInvalidNumber => 'Ange ett tal';

  @override
  String get spaInvalidWholeNumber => 'Ange ett heltal';

  @override
  String get spaCurrency => 'Valuta';

  @override
  String get spaSubtype => 'Undertyp';

  @override
  String get spaPropertyType => 'Fastighetstyp';

  @override
  String get spaPropertyTypeRequired => 'Välj en fastighetstyp';

  @override
  String get spaNone => 'Ingen';

  @override
  String get spaOptional => 'Valfritt';

  @override
  String get spaUnchanged => 'Oförändrat';

  @override
  String get spaAvailableCredit => 'Tillgänglig kredit';

  @override
  String get spaApr => 'Årsränta';

  @override
  String get spaMinimumPayment => 'Minsta betalning';

  @override
  String get spaAnnualFee => 'Årsavgift';

  @override
  String get spaExpirationDate => 'Utgångsdatum';

  @override
  String get spaStatementCloseDay => 'Fakturan stängs';

  @override
  String get spaDueDay => 'Förfallodag';

  @override
  String spaDayOfMonth(int day) {
    return 'Dag $day';
  }

  @override
  String get spaInterestRate => 'Ränta';

  @override
  String get spaRateType => 'Räntetyp';

  @override
  String get spaRateFixed => 'Fast';

  @override
  String get spaRateVariable => 'Rörlig';

  @override
  String get spaRateAdjustable => 'Justerbar';

  @override
  String get spaTerm => 'Löptid';

  @override
  String get spaMonthsSuffix => 'månader';

  @override
  String get spaStartDate => 'Startdatum';

  @override
  String get spaOriginalAmount => 'Ursprungligt belopp';

  @override
  String get spaDownPayment => 'Kontantinsats';

  @override
  String get spaMake => 'Märke';

  @override
  String get spaModel => 'Modell';

  @override
  String get spaYear => 'År';

  @override
  String get spaMileage => 'Mätarställning';

  @override
  String get spaMileageUnit => 'Enhet för mätarställning';

  @override
  String get spaMiles => 'Miles';

  @override
  String get spaKilometers => 'Kilometer';

  @override
  String get spaPurchasePrice => 'Inköpspris';

  @override
  String get spaPurchaseDate => 'Inköpsdatum';

  @override
  String get spaYearBuilt => 'Byggår';

  @override
  String get spaArea => 'Yta';

  @override
  String get spaAreaUnit => 'Enhet för yta';

  @override
  String get spaSquareFeet => 'Kvadratfot';

  @override
  String get spaSquareMeters => 'Kvadratmeter';

  @override
  String get spaAddress => 'Adress';

  @override
  String get spaStreet => 'Gata';

  @override
  String get spaStreet2 => 'Lägenhet, våning';

  @override
  String get spaCity => 'Ort';

  @override
  String get spaRegion => 'Delstat eller region';

  @override
  String get spaPostalCode => 'Postnummer';

  @override
  String get spaCountry => 'Land';

  @override
  String get spaTaxTreatment => 'Skattebehandling';

  @override
  String get spaTaxable => 'Skattepliktig';

  @override
  String get spaTaxDeferred => 'Skatteuppskjuten';

  @override
  String get spaTaxExempt => 'Skattefri';

  @override
  String get spaMore => 'Mer';

  @override
  String get spaInstitution => 'Institution';

  @override
  String get spaNotes => 'Anteckningar';

  @override
  String get spaOpeningDate => 'Datum för startsaldo';

  @override
  String get spaExcludeFromReports => 'Exkludera från rapporter';

  @override
  String get spaSubCash => 'Kontanter';

  @override
  String get spaSubChecking => 'Lönekonto';

  @override
  String get spaSubSavings => 'Sparkonto';

  @override
  String get spaSubHsa => 'Hälsosparkonto (HSA)';

  @override
  String get spaSubCd => 'Bunden insättning';

  @override
  String get spaSubMoneyMarket => 'Penningmarknadskonto';

  @override
  String get spaSubMortgage => 'Bolån';

  @override
  String get spaSubStudentLoan => 'Studielån';

  @override
  String get spaSubAutoLoan => 'Billån';

  @override
  String get spaSubHomeEquity => 'Lån mot bostaden';

  @override
  String get spaSubLineOfCredit => 'Kreditlina';

  @override
  String get spaSubBusinessLoan => 'Företagslån';

  @override
  String get spaSubOtherLoan => 'Annat lån';

  @override
  String get spaSubWallet => 'Kryptoplånbok';

  @override
  String get spaSubExchange => 'Kryptobörs';

  @override
  String get spaSubSingleFamily => 'Villa';

  @override
  String get spaSubMultiFamily => 'Flerfamiljshus';

  @override
  String get spaSubCondo => 'Bostadsrätt';

  @override
  String get spaSubTownhouse => 'Radhus';

  @override
  String get spaSubInvestmentProperty => 'Investeringsfastighet';

  @override
  String get spaSubSecondHome => 'Fritidshus';

  @override
  String get spaSubApartment => 'Lägenhet';

  @override
  String get spaSubPlot => 'Tomt / mark';

  @override
  String get spaSubCommercial => 'Kommersiell fastighet';

  @override
  String get spaSubAgriLand => 'Jordbruksmark';

  @override
  String get spaCreated => 'Kontot har lagts till';

  @override
  String get spaSaved => 'Kontot har sparats';

  @override
  String get spaSaveFailed => 'Det gick inte att spara kontot';

  @override
  String get spaDeleteAccount => 'Radera konto';

  @override
  String spaDeleteConfirmTitle(String name) {
    return 'Radera $name?';
  }

  @override
  String get spaDeleteConfirmBody =>
      'Dess transaktioner och historik tas bort. Det går inte att ångra.';

  @override
  String get spaDeleted => 'Kontot har raderats';

  @override
  String get spaReadOnlyAccess =>
      'Den här inloggningen kan bara visa data. Logga in igen med full åtkomst för att ändra konton.';

  @override
  String get spaInvestEmptyBody =>
      'Lägg till ett investerings- eller kryptokonto, eller anslut en mäklare.';

  @override
  String get sb2Move => 'Flytta';

  @override
  String get sb2MoveTitle => 'Flytta budget';

  @override
  String get sb2From => 'Från';

  @override
  String get sb2To => 'Till';

  @override
  String get sb2Choose => 'Välj';

  @override
  String sb2AmountLeft(String amount) {
    return '$amount kvar';
  }

  @override
  String get sb2Moved => 'Budgeten flyttades';

  @override
  String get sb2MoveFailed => 'Det gick inte att flytta budgeten. Försök igen.';

  @override
  String get sb2ErrInsufficientFunds =>
      'Kategorin har inte så mycket budget att flytta.';

  @override
  String get sb2ErrDifferentBudgets =>
      'Båda kategorierna måste finnas i samma budget.';

  @override
  String get sb2ErrNonPositive => 'Ange ett belopp större än 0.';

  @override
  String get sb2ErrSameCategory => 'Välj en annan kategori att flytta till.';

  @override
  String get sb2ErrParentChild =>
      'Du kan inte flytta budget mellan en kategori och dess egen underkategori.';

  @override
  String get sb2ErrUncategorized => 'Okategoriserat kan inte ha någon budget.';

  @override
  String sb2AvgSuffix(String amount) {
    return ' · snitt $amount';
  }

  @override
  String get sb2NoBudgetBody =>
      'Kopiera beloppen från en tidigare månad eller börja med en tom budget.';

  @override
  String sb2CopyMonth(String month) {
    return 'Kopiera $month';
  }

  @override
  String get sb2StartFromScratch => 'Börja från noll';

  @override
  String get sb2NothingToCopy => 'Det finns ingen tidigare budget att kopiera.';

  @override
  String get sb2SetupFailed => 'Det gick inte att skapa budgeten. Försök igen.';
}
