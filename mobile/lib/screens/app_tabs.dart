import 'package:flutter/widgets.dart';

import 'activity_screen.dart';
import 'recurring_screen.dart';

/// Plug-in points for the main shell's tab bodies.
///
/// To swap in a native screen built elsewhere, change the one line that
/// returns its placeholder, e.g. `=> const ActivityScreen();`.
abstract final class AppTabs {
  /// Body of the Activity tab.
  static Widget activity(BuildContext context) => const ActivityScreen();

  /// Body of the Recurring segment on the Plan tab.
  static Widget recurring(BuildContext context) => const RecurringScreen();
}
