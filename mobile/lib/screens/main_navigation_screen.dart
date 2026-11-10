import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_logo.dart';
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

  NavigationDestination _destination(ShellTab tab, AppLocalizations l) {
    switch (tab) {
      case ShellTab.home:
        return NavigationDestination(
          icon: const SureIcon(SureIcons.house),
          label: l.navHome,
        );
      case ShellTab.intro:
        return NavigationDestination(
          icon: const Icon(Icons.auto_awesome_outlined),
          selectedIcon: const Icon(Icons.auto_awesome),
          label: l.navIntro,
        );
      case ShellTab.activity:
        return NavigationDestination(
          icon: const SureIcon(SureIcons.receipt),
          label: l.shellNavActivity,
        );
      case ShellTab.plan:
        return NavigationDestination(
          icon: const Icon(Icons.pie_chart_outline),
          selectedIcon: const Icon(Icons.pie_chart),
          label: l.shellNavPlan,
        );
      case ShellTab.invest:
        return NavigationDestination(
          icon: const SureIcon(SureIcons.trendingUp),
          label: l.shellNavInvest,
        );
      case ShellTab.assistant:
        return NavigationDestination(
          icon: const Icon(Icons.chat_bubble_outline),
          selectedIcon: const Icon(Icons.chat_bubble),
          label: l.navAssistant,
        );
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
                  child: Icon(
                    context.watch<PrivacyProvider>().hidden
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    semanticLabel: 'Toggle privacy',
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
                  child: Icon(
                    Icons.settings_outlined,
                    semanticLabel: l.shellSettingsTitle,
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

        return Scaffold(
          appBar: _buildTopBar(l),
          body: IndexedStack(
            index: _currentIndex,
            children: [
              for (final tab in tabs)
                _visited.contains(tab)
                    ? _buildBody(tab, startChat)
                    : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              _handleDestinationSelected(index, authProvider, tabs);
            },
            destinations: [for (final tab in tabs) _destination(tab, l)],
          ),
        );
      },
    );
  }
}
