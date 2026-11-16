import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/services/connectivity_service.dart';

void main() {
  test('only "none" is offline; "other" (VPN, Simulator) is online', () {
    expect(ConnectivityService.isOnlineFor([ConnectivityResult.none]), isFalse);
    expect(ConnectivityService.isOnlineFor(const []), isFalse);
    expect(ConnectivityService.isOnlineFor([ConnectivityResult.other]), isTrue);
    expect(ConnectivityService.isOnlineFor([ConnectivityResult.wifi]), isTrue);
    expect(
        ConnectivityService.isOnlineFor(
            [ConnectivityResult.none, ConnectivityResult.vpn]),
        isTrue);
  });
}
