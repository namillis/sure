import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../widgets/ds/sure_tab_bar.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_logo.dart';
import '../widgets/sync_status_chip.dart';
import 'app_tabs.dart';
import 'chat_list_screen.dart';
import 'dashboard_screen.dart';
import 'intro_screen.dart';
import 'invest_screen.dart';
import 'plan_screen.dart';
import 'settings_screen.dart';
import '../l10n/app_localizations.dart';

/// The bottom tabs of the main shell.
enum ShellTab { home, intro, activity, plan, invest, assistant }

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key, this.tabBodyBuilder});

  /// Replaces every tab body. Injected in tests so the shell can be pumped
  /// without the network-backed screens.
  @visibleForTesting
  final Widget Function(BuildContext context, ShellTab tab)? tabBodyBuilder;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final _dashboardKey = GlobalKey<DashboardScreenState>();
  // Tabs are built on first visit, then kept alive by the IndexedStack, so
  // the Activity, Plan and Invest loads don't all fire at launch.
  final Set<ShellTab> _visited = {};

  List<ShellTab> _tabs(bool introLayout) => introLayout
      ? const [ShellTab.intro, ShellTab.assistant]
      : const [
          ShellTab.home,
          ShellTab.activity,
          ShellTab.plan,
          ShellTab.invest,
          ShellTab.assistant,
        ];

  Widget _buildBody(ShellTab tab, VoidCallback onStartChat) {
    final override = widget.tabBodyBuilder;
    if (override != null) return override(context, tab);
    switch (tab) {
      case ShellTab.home:
        return DashboardScreen(key: _dashboardKey);
      case ShellTab.intro:
        return IntroScreen(onStartChat: onStartChat);
      case ShellTab.activity:
        return AppTabs.activity(context);
      case ShellTab.plan:
        return const PlanScreen();
      case ShellTab.invest:
        return const InvestScreen();
      case ShellTab.assistant:
        return const ChatListScreen();
    }
  }

  SureTabItem _tabItem(ShellTab tab, AppLocalizations l) {
    switch (tab) {
      case ShellTab.home:
        return SureTabItem(icon: SureIcons.house, label: l.navHome);
      case ShellTab.intro:
        return SureTabItem(icon: SureIcons.sparkles, label: l.navIntro);
      case ShellTab.activity:
        return SureTabItem(icon: SureIcons.receipt, label: l.shellNavActivity);
      case ShellTab.plan:
        return SureTabItem(icon: SureIcons.chartPie, label: l.shellNavPlan);
      case ShellTab.invest:
        return SureTabItem(icon: SureIcons.trendingUp, label: l.shellNavInvest);
      case ShellTab.assistant:
        return SureTabItem(
            icon: SureIcons.messageCircle, label: l.navAssistant);
    }
  }

  Future<void> _handleDestinationSelected(
    int index,
    AuthProvider authProvider,
    List<ShellTab> tabs,
  ) async {
    if (index < 0 || index >= tabs.length) return;
    final tab = tabs[index];

    if (tab == ShellTab.assistant && !authProvider.aiEnabled) {
      final enabled = await _showEnableAiPrompt();
      if (!enabled) {
        return;
      }
    }

    if (mounted) {
      setState(() {
        _currentIndex = index;
      });

      if (tab == ShellTab.home) {
        _dashboardKey.currentState?.reloadPreferences();
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    // Settings can change dashboard preferences (e.g. group by type).
    _dashboardKey.currentState?.reloadPreferences();
  }

  PreferredSizeWidget _buildTopBar(AppLocalizations l) {
    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 60,
      elevation: 0,
      titleSpacing: 0,
      centerTitle: false,
      actionsPadding: EdgeInsets.zero,
      title: Container(
        width: 60,
        height: 60,
        alignment: Alignment.topLeft,
        child: const Padding(
          padding: EdgeInsets.only(top: 12, left: 12),
          child: SureLogo(),
        ),
      ),
      actions: [
        // Last sync time; tapping it syncs now and then reloads Home.
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: SyncStatusChip(
              onSynced: () => _dashboardKey.currentState?.reloadData(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Tooltip(
              message: 'Toggle privacy',
              child: InkWell(
                onTap: () => context.read<PrivacyProvider>().toggle(),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SureIcon(
                      context.watch<PrivacyProvider>().hidden
                          ? SureIcons.eyeOff
                          : SureIcons.eye,
                      size: 22,
                      semanticLabel: 'Toggle privacy',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Tooltip(
              message: l.shellSettingsTitle,
              child: InkWell(
                onTap: _openSettings,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SureIcon(
                      SureIcons.settings,
                      size: 22,
                      semanticLabel: l.shellSettingsTitle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _showEnableAiPrompt() async {
    final l = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final shouldEnable = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.navEnableAiChatTitle),
          content: Text(dl.navEnableAiChatContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(dl.navEnableAiChatNotNow),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(dl.navEnableAiChatConfirm),
            ),
          ],
        );
      },
    );

    if (shouldEnable != true) {
      return false;
    }

    final enabled = await authProvider.enableAi();

    if (!enabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? l.navEnableAiChatFailed),
          backgroundColor: Colors.red,
        ),
      );
    }

    return enabled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Consumer<AuthProvider>(
      builder: (context, authProvider, _) {
        final tabs = _tabs(authProvider.isIntroLayout);

        if (_currentIndex >= tabs.length) {
          _currentIndex = 0;
        }
        _visited.add(tabs[_currentIndex]);

        final chatIndex = tabs.indexOf(ShellTab.assistant);
        void startChat() =>
            _handleDestinationSelected(chatIndex, authProvider, tabs);

        // The logo bar (privacy toggle, settings) belongs to Home. Every
        // other tab draws its own titled app bar.
        final onHome = tabs[_currentIndex] == ShellTab.home;
        return Scaffold(
          appBar: onHome ? _buildTopBar(l) : null,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              for (final tab in tabs)
                _visited.contains(tab)
                    ? _buildBody(tab, startChat)
                    : const SizedBox.shrink(),
            ],
          ),
          // shortcut: the bar is translucent but the body does not extend
          // behind it yet (extendBody: false), because several tab roots
          // (Invest, Home) do not pad their scroll views for it. Flip this
          // once every tab root adds the bottom inset.
          bottomNavigationBar: SureTabBar(
            currentIndex: _currentIndex,
            onSelected: (index) {
              _handleDestinationSelected(index, authProvider, tabs);
            },
            items: [for (final tab in tabs) _tabItem(tab, l)],
          ),
        );
      },
    );
  }
}
