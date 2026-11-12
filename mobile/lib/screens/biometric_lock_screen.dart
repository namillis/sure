import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../l10n/app_localizations.dart';
import '../services/biometric_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_logo.dart';
import 'auth_fields.dart';

/// The unlock button's label: "Unlock with Face ID" / "Unlock with Touch ID"
/// on iOS when the device reports that biometric, else "Unlock".
@visibleForTesting
String biometricUnlockLabel(
  AppLocalizations l,
  List<BiometricType> types,
  TargetPlatform platform,
) {
  if (platform == TargetPlatform.iOS) {
    if (types.contains(BiometricType.face)) return l.ds4aUnlockFaceId;
    if (types.contains(BiometricType.fingerprint)) return l.ds4aUnlockTouchId;
  }
  return l.biometricUnlock;
}

class BiometricLockScreen extends StatefulWidget {
  const BiometricLockScreen({
    super.key,
    required this.onUnlocked,
    this.onLogout,
    this.authenticate,
    this.loadBiometrics,
  });

  final VoidCallback onUnlocked;
  final VoidCallback? onLogout;

  /// Test seam for the OS prompt; defaults to [BiometricService.authenticate].
  @visibleForTesting
  final Future<bool> Function()? authenticate;

  /// Test seam for the enrolled biometrics; defaults to
  /// [BiometricService.getAvailableBiometrics].
  @visibleForTesting
  final Future<List<BiometricType>> Function()? loadBiometrics;

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen> {
  bool _isAuthenticating = false;
  List<BiometricType> _biometrics = const [];

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
    // Auto-trigger biometric prompt on first show.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _loadBiometrics() async {
    final load = widget.loadBiometrics ??
        BiometricService.instance.getAvailableBiometrics;
    final types = await load();
    if (mounted) setState(() => _biometrics = types);
  }

  Future<void> _authenticate() async {
    if (!mounted || _isAuthenticating) return;
    setState(() => _isAuthenticating = true);

    final authenticate =
        widget.authenticate ?? BiometricService.instance.authenticate;
    final success = await authenticate();

    if (!mounted) return;
    setState(() => _isAuthenticating = false);

    if (success) {
      widget.onUnlocked();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).biometricLockFailedRetry)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final platform = Theme.of(context).platform;
    final face = platform == TargetPlatform.iOS &&
        _biometrics.contains(BiometricType.face);

    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SureLogo(size: 64)),
                  const SizedBox(height: 20),
                  Text(
                    l.ds4aLockedTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.biometricSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SureButton(
                    key: const ValueKey('biometric-unlock'),
                    label: _isAuthenticating
                        ? l.biometricAuthenticating
                        : biometricUnlockLabel(l, _biometrics, platform),
                    size: SureButtonSize.lg,
                    fullWidth: true,
                    loading: _isAuthenticating,
                    leading: SureIcon(
                      face ? AuthIcons.scanFace : AuthIcons.fingerprint,
                      size: 18,
                    ),
                    onPressed: _authenticate,
                  ),
                  if (widget.onLogout != null) ...[
                    const SizedBox(height: 8),
                    AuthQuietLink(
                      key: const ValueKey('biometric-log-out'),
                      label: l.biometricLogOut,
                      onPressed: widget.onLogout,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
