import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/data/remote/backend_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ui_harness.dart';

void main() {
  late UiEnv env;
  late ProviderContainer container;

  setUp(() {
    env = UiEnv();
    container = ProviderContainer(overrides: env.overrides(const SignedIn(testProfile), fakeSync: false));
  });
  tearDown(() {
    container.dispose();
    env.dispose();
  });

  test('un moteur de synchronisation par compte : conservé quand le profil change, remplacé pour un autre compte', () {
    final first = container.read(syncControlProvider);

    // Même compte (nouveau nom de boutique) : même moteur, pas de redémarrage.
    container.read(sessionProvider.notifier).state = const SignedIn(
      Profile(id: 'user-1', phone: '+2290167000001', businessName: 'Autre nom', plan: Plan.free),
    );
    expect(identical(container.read(syncControlProvider), first), isTrue);

    // Autre compte : nouveau moteur (l'ancien est arrêté).
    container.read(sessionProvider.notifier).state = const SignedIn(
      Profile(id: 'user-2', phone: '+2290167000002', businessName: 'B', plan: Plan.free),
    );
    expect(identical(container.read(syncControlProvider), first), isFalse);
  });

  test('Premium : valide seulement jusqu\'à l\'expiration, même hors ligne', () {
    expect(container.read(isPremiumProvider), isFalse);
    container.read(sessionProvider.notifier).state = SignedIn(premiumProfile); // expire le 1er nov. 2026
    expect(container.read(isPremiumProvider), isTrue);

    env.now = DateTime.utc(2026, 11, 2);
    container.invalidate(isPremiumProvider);
    expect(container.read(isPremiumProvider), isFalse);
  });
}
