import 'dart:io';

import 'package:ardoiz/app/bootstrap.dart';
import 'package:ardoiz/app/providers.dart';
import 'package:ardoiz/app/session_service.dart';
import 'package:ardoiz/data/local/ledger_store.dart';
import 'package:ardoiz/data/local/secret_store.dart';
import 'package:ardoiz/data/repositories/ledger_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late InMemorySecretStore secrets;
  late String dbPath;
  final opened = <ProviderContainerCloser>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('carne_boot_');
    dbPath = p.join(dir.path, 'carne.db');
    secrets = InMemorySecretStore();
  });
  tearDown(() {
    for (final close in opened) {
      close();
    }
    opened.clear();
    dir.deleteSync(recursive: true);
  });

  Bootstrap bootstrap({String url = 'https://api.exemple.com/api/v1', bool release = false}) => Bootstrap(
        secrets: secrets,
        databasePath: () async => dbPath,
        apiBaseUrl: url,
        release: release,
      );

  Future<BootstrapReady> ready(Bootstrap b) async {
    final result = await b.run();
    expect(result, isA<BootstrapReady>(), reason: result is BootstrapFailed ? result.message : null);
    final r = result as BootstrapReady;
    opened.add(() {
      r.container.read(databaseProvider).close();
      r.container.dispose();
    });
    return r;
  }

  test('premier lancement : crée la base chiffrée et la clé, personne n\'est connecté', () async {
    final r = await ready(bootstrap());
    expect(r.container.read(sessionProvider), isA<SignedOut>());
    expect(File(dbPath).existsSync(), isTrue);
    expect(await secrets.read(SecretKeys.databaseKey), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('les données restent après redémarrage, et le fichier ne contient aucun texte en clair', () async {
    final first = await ready(bootstrap());
    final db = first.container.read(databaseProvider);
    LedgerRepository(db: db).addCustomer(name: 'MARQUEUR_CLIENT_SECRET', phone: '+22901670000');
    db.close();
    first.container.dispose();
    opened.clear();

    final raw = File(dbPath).readAsBytesSync();
    final walFile = File('$dbPath-wal');
    final all = <int>[...raw, if (walFile.existsSync()) ...walFile.readAsBytesSync()];
    expect(String.fromCharCodes(all).contains('MARQUEUR_CLIENT_SECRET'), isFalse, reason: 'la base doit être chiffrée');
    expect(String.fromCharCodes(all).contains('SQLite format'), isFalse);

    final second = await ready(bootstrap());
    expect(LedgerStore(second.container.read(databaseProvider)).customers().single.name, 'MARQUEUR_CLIENT_SECRET');
  });

  test('session restaurée hors ligne depuis le cache local au redémarrage', () async {
    final first = await ready(bootstrap());
    final db = first.container.read(databaseProvider);
    LedgerStore(db)
      ..setMeta('user_id', 'u1')
      ..setMeta('profile', '{"id":"u1","phone":"+2290167000001","businessName":"Boutique","plan":"FREE","planExpiresAt":null}');
    await secrets.write(SecretKeys.accessToken, 'a');
    await secrets.write(SecretKeys.refreshToken, 'r');
    db.close();
    first.container.dispose();
    opened.clear();

    final second = await ready(bootstrap());
    final session = second.container.read(sessionProvider);
    expect(session, isA<SignedIn>());
    expect((session as SignedIn).profile.businessName, 'Boutique');
  });

  test('adresse du serveur invalide, ou non HTTPS en version finale : échec explicite sans toucher aux données', () async {
    final bad = await bootstrap(url: 'pas une adresse').run();
    expect(bad, isA<BootstrapFailed>());
    expect((bad as BootstrapFailed).problem, BootstrapProblem.configuration);
    expect(bad.canResetLocalData, isFalse);

    final insecure = await bootstrap(url: 'http://api.exemple.com', release: true).run();
    expect((insecure as BootstrapFailed).problem, BootstrapProblem.configuration);
    expect(File(dbPath).existsSync(), isFalse);

    // En développement, http reste permis (émulateur).
    await ready(bootstrap(url: 'http://10.0.2.2:3000/api/v1'));
  });

  test('clé perdue : signalé (jamais d\'écran blanc), réinitialisation proposée, puis base vierge utilisable', () async {
    final first = await ready(bootstrap());
    LedgerRepository(db: first.container.read(databaseProvider)).addCustomer(name: 'Aïcha', phone: '+22901670000');
    first.container.read(databaseProvider).close();
    first.container.dispose();
    opened.clear();

    await secrets.delete(SecretKeys.databaseKey); // clé perdue : une nouvelle sera générée

    final broken = await bootstrap().run();
    expect(broken, isA<BootstrapFailed>());
    expect((broken as BootstrapFailed).problem, BootstrapProblem.keyMismatch);
    expect(broken.canResetLocalData, isTrue);
    expect(File(dbPath).existsSync(), isTrue, reason: 'rien n\'est supprimé sans décision de l\'utilisateur');

    final fresh = await bootstrap().resetLocalDataAndRun();
    expect(fresh, isA<BootstrapReady>());
    final container = (fresh as BootstrapReady).container;
    opened.add(() {
      container.read(databaseProvider).close();
      container.dispose();
    });
    expect(LedgerStore(container.read(databaseProvider)).customers(), isEmpty);
  });

  test('fichier de base corrompu : échec explicite, réinitialisation possible', () async {
    File(dbPath).writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));
    final broken = await bootstrap().run();
    expect(broken, isA<BootstrapFailed>());
    expect((broken as BootstrapFailed).canResetLocalData, isTrue);

    final fresh = await bootstrap().resetLocalDataAndRun();
    expect(fresh, isA<BootstrapReady>());
    final container = (fresh as BootstrapReady).container;
    opened.add(() {
      container.read(databaseProvider).close();
      container.dispose();
    });
  });

  test('les jetons gardés dans le coffre ne sont jamais mélangés à la base (clé de base dans le coffre uniquement)', () async {
    await ready(bootstrap());
    final key = (await secrets.read(SecretKeys.databaseKey))!;
    expect(String.fromCharCodes(File(dbPath).readAsBytesSync()).contains(key), isFalse);
  });
}

typedef ProviderContainerCloser = void Function();
