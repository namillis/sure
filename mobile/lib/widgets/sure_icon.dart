import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Sure design-system icon primitive.
///
/// Renders a bundled Lucide SVG (stroke `currentColor`, 2px) tinted to a single
/// color, mirroring the web `icon` helper / `DS::FilledIcon` semantics: tokenized
/// size, color inherited from the surrounding [IconTheme] by default, and
/// accessibility that distinguishes decorative from meaningful icons.
///
/// Use [SureIcons] for the bundled icon names so call sites stay typo-safe and
/// only reference assets that actually ship in `assets/icons/lucide/`.
///
/// ```dart
/// const SureIcon(SureIcons.wallet, size: SureIconSize.lg)            // decorative
/// const SureIcon(SureIcons.refresh, semanticLabel: 'Refresh')        // meaningful
/// ```
class SureIcon extends StatelessWidget {
  /// Lucide icon name (kebab-case), e.g. `wallet`. Prefer [SureIcons] constants.
  final String name;

  /// Square edge length in logical pixels. Prefer a [SureIconSize] token. When
  /// null, inherits the ambient [IconTheme] size (Material-icon parity), falling
  /// back to 24 — so dropping `SureIcon` in for `Icon` preserves sizing.
  final double? size;

  /// Tint applied to the icon. When null, inherits the ambient [IconTheme]
  /// color (Material-icon parity), falling back to opaque black only if unset.
  final Color? color;

  /// When provided, the icon is exposed to assistive tech with this label
  /// (meaningful icon). When null, the icon is decorative and excluded from the
  /// semantics tree — use this only when an adjacent widget carries the name.
  final String? semanticLabel;

  const SureIcon(
    this.name, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final resolvedSize = size ?? iconTheme.size ?? 24;
    final resolvedColor = color ?? iconTheme.color ?? const Color(0xFF000000);
    // Mirror Material `Icon`: always paint the glyph at `resolvedSize`, even when
    // a parent imposes tight constraints larger than the icon (e.g. a fixed-size
    // Container). The outer SizedBox sets the intrinsic size; the Center loosens
    // the constraints handed to SvgPicture so its width/height aren't stretched.
    return SizedBox(
      width: resolvedSize,
      height: resolvedSize,
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/lucide/$name.svg',
          width: resolvedSize,
          height: resolvedSize,
          colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
          semanticsLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
        ),
      ),
    );
  }
}

/// Canonical icon sizes, mirroring the web `icon` helper scale
/// (xs/sm/md/lg/xl/2xl → 12/16/20/24/28/32).
abstract final class SureIconSize {
  static const double xs = 12;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double xl = 28;
  static const double xxl = 32;
}

/// Names of the Lucide icons bundled under `assets/icons/lucide/`.
///
/// Bundled from the official Lucide 0.562.0 release (the version the server's
/// `lucide-rails` 0.7.3 ships), ISC licensed: see
/// `assets/icons/lucide/LICENSE`. Referencing a name here guarantees the asset
/// ships; add the SVG (and a constant) before using a new icon.
abstract final class SureIcons {
  static const String landmark = 'landmark';
  static const String creditCard = 'credit-card';
  static const String trendingUp = 'trending-up';
  static const String trendingDown = 'trending-down';
  static const String receipt = 'receipt';
  static const String house = 'house';
  static const String car = 'car';
  static const String bitcoin = 'bitcoin';
  static const String shapes = 'shapes';
  static const String handCoins = 'hand-coins';
  static const String wallet = 'wallet';
  static const String circleAlert = 'circle-alert';
  static const String circleCheck = 'circle-check';
  static const String cloudCheck = 'cloud-check';
  static const String refresh = 'refresh-cw';
  static const String chevronUp = 'chevron-up';
  static const String chevronDown = 'chevron-down';
  static const String chevronRight = 'chevron-right';
  static const String chevronLeft = 'chevron-left';
  static const String arrowDown = 'arrow-down';
  static const String arrowUp = 'arrow-up';
  static const String arrowUpRight = 'arrow-up-right';
  static const String arrowLeftRight = 'arrow-left-right';
  static const String calendar = 'calendar';
  static const String chartLine = 'chart-line';
  static const String chartPie = 'chart-pie';
  static const String check = 'check';
  static const String circleDashed = 'circle-dashed';
  static const String circlePlus = 'circle-plus';
  static const String circleQuestionMark = 'circle-question-mark';
  static const String circleX = 'circle-x';
  static const String clock = 'clock';
  static const String cloudOff = 'cloud-off';
  static const String cloudUpload = 'cloud-upload';
  static const String coins = 'coins';
  static const String ellipsis = 'ellipsis';
  static const String externalLink = 'external-link';
  static const String eye = 'eye';
  static const String eyeOff = 'eye-off';
  static const String inbox = 'inbox';
  static const String info = 'info';
  static const String lightbulb = 'lightbulb';
  static const String listChecks = 'list-checks';
  static const String messageCircle = 'message-circle';
  static const String minus = 'minus';
  static const String pencil = 'pencil';
  static const String piggyBank = 'piggy-bank';
  static const String plus = 'plus';
  static const String repeat = 'repeat';
  static const String search = 'search';
  static const String settings = 'settings';
  static const String sparkles = 'sparkles';
  static const String split = 'split';
  static const String squareCheck = 'square-check';
  static const String store = 'store';
  static const String stickyNote = 'sticky-note';
  static const String tag = 'tag';
  static const String trash = 'trash-2';
  static const String triangleAlert = 'triangle-alert';
  static const String x = 'x';

  /// Older Lucide names the server can store (`Category.icon_codes`, the
  /// default categories) mapped to the 0.562.0 icon they now alias, so only
  /// the canonical SVG ships.
  static const Map<String, String> aliases = <String, String>{
    'bar-chart-3': 'chart-column',
    'home': 'house',
    'pie-chart': 'chart-pie',
    'train': 'tram-front',
  };

  /// Every bundled icon a server category can name: `Category.icon_codes`,
  /// the `ICON_KEYWORDS` suggestions, the default categories and the
  /// synthetic ones, after [aliases] are applied.
  static const Set<String> category = <String>{
    'ambulance', 'apple', 'award', 'baby', 'badge-dollar-sign', 'banknote',
    'barcode', 'bath', 'battery', 'bed-single', 'beer', 'bike', 'bluetooth',
    'bone', 'book', 'book-open', 'briefcase', 'building', 'bus', 'cake',
    'calculator', 'calendar-heart', 'calendar-range', 'camera', 'car', 'cat',
    'chart-column', 'chart-line', 'chart-pie', 'circle-dashed',
    'circle-dollar-sign', 'circle-parking', 'coffee', 'coins', 'compass',
    'cookie', 'cooking-pot', 'credit-card', 'dices', 'dog', 'drama', 'drill',
    'droplet', 'drum', 'dumbbell', 'film', 'flame', 'flower', 'flower-2',
    'fuel', 'gamepad-2', 'gem', 'gift', 'glasses', 'globe', 'graduation-cap',
    'hammer', 'hand-heart', 'hand-helping', 'handshake', 'headphones', 'heart',
    'heart-handshake', 'heart-pulse', 'hotel', 'house', 'ice-cream-cone',
    'key', 'landmark', 'laptop', 'leaf', 'lightbulb', 'luggage', 'mail',
    'map-pin', 'martini', 'mic', 'monitor', 'moon', 'music', 'package',
    'palette', 'party-popper', 'paw-print', 'pen', 'pencil', 'percent',
    'phone', 'piggy-bank', 'pill', 'pizza', 'plane', 'plug', 'popcorn',
    'power', 'printer', 'puzzle', 'receipt', 'receipt-text', 'ribbon', 'scale',
    'scissors', 'settings', 'shapes', 'shield', 'shield-plus', 'shirt',
    'shopping-bag', 'shopping-basket', 'shopping-cart', 'smartphone',
    'sparkles', 'sprout', 'stethoscope', 'store', 'sun', 'tablet-smartphone',
    'tag', 'target', 'tent', 'thermometer', 'ticket', 'tram-front',
    'tree-palm', 'trees', 'trending-up', 'trophy', 'truck', 'tv', 'umbrella',
    'undo-2', 'unplug', 'users', 'utensils', 'video', 'wallet', 'wallet-cards',
    'waves', 'wifi', 'wine', 'wrench', 'zap',
  };

  /// The bundled asset name for a server category [icon], or null when the
  /// name is empty or not bundled (the caller then falls back, e.g. to the
  /// category's first letter).
  static String? forCategory(String? icon) {
    final name = icon?.trim().toLowerCase();
    if (name == null || name.isEmpty) return null;
    final canonical = aliases[name] ?? name;
    return category.contains(canonical) ? canonical : null;
  }
}
