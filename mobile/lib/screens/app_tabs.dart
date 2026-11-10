import 'package:flutter/widgets.dart';

import 'plan_screen.dart';
import 'recent_transactions_screen.dart';

/// Plug-in points for the main shell's tab bodies.
///
/// To swap in a native screen built elsewhere, change the one line that
/// returns its placeholder, e.g. `=> const ActivityScreen();`.
abstract final class AppTabs {
  /// Body of the Activity tab.
  static Widget activity(BuildContext context) =>
      const RecentTransactionsScreen();

  /// Body of the Recurring segment on the Plan tab.
  static Widget recurring(BuildContext context) => const ComingSoonView();
}
