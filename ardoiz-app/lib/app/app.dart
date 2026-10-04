import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/brand.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';
import 'session_service.dart';

class CarneApp extends ConsumerWidget {
  const CarneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: Brand.name,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: ref.watch(routerProvider),
        locale: const Locale('fr'),
        supportedLocales: const <Locale>[Locale('fr')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => SessionLifecycle(child: child ?? const SizedBox.shrink()),
      );
}

/// Relie la session à la synchronisation : démarre le moteur quand un
/// commerçant est connecté, rafraîchit au retour au premier plan, et ferme côté
/// serveur une session close hors ligne dès que le réseau le permet.
class SessionLifecycle extends ConsumerStatefulWidget {
  const SessionLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionLifecycle> createState() => _SessionLifecycleState();
}

class _SessionLifecycleState extends ConsumerState<SessionLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSession(ref.read(sessionProvider)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session is SignedIn) {
      unawaited(ref.read(syncControlProvider).syncNow());
      unawaited(ref.read(sessionProvider.notifier).refreshProfile());
    } else {
      unawaited(ref.read(sessionServiceProvider).revokePendingSession());
    }
  }

  void _onSession(SessionState session) {
    if (!mounted) return;
    if (session is SignedIn) {
      unawaited(ref.read(syncControlProvider).start());
      unawaited(ref.read(sessionProvider.notifier).refreshProfile());
    } else {
      unawaited(ref.read(sessionServiceProvider).revokePendingSession());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionProvider, (previous, next) {
      final before = previous is SignedIn ? previous.profile.id : null;
      final after = next is SignedIn ? next.profile.id : null;
      // Connexion, déconnexion ou changement de compte ; une simple mise à jour du profil, non.
      if (before != after) _onSession(next);
    });
    return widget.child;
  }
}
