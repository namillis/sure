import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/ds/ds.dart';

class IntroScreenPlatform extends StatelessWidget {
  const IntroScreenPlatform({super.key, this.onStartChat});

  final VoidCallback? onStartChat;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SureLargeTitleScaffold(
      title: l.navIntro,
      automaticallyImplyLeading: false,
      slivers: [
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SurePanel(
                key: const ValueKey('intro-panel'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SureEmptyState(
                  icon: SureIcons.sparkles,
                  title: l.ds4aIntroTitle,
                  body: l.ds4aIntroBody,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
