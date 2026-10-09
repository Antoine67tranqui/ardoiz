import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'data/local/secret_store.dart';
import 'ui/screens/startup_failure_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = Bootstrap(
    secrets: const SecureSecretStore(),
    release: kReleaseMode,
    databasePath: () async => p.join((await getApplicationSupportDirectory()).path, 'carne.db'),
  );
  await _launch(bootstrap, await bootstrap.run());
}

Future<void> _launch(Bootstrap bootstrap, BootstrapResult result) async {
  switch (result) {
    case BootstrapReady(:final container):
      runApp(UncontrolledProviderScope(container: container, child: const CarneApp()));
    case BootstrapFailed():
      runApp(StartupFailureApp(
        failure: result,
        onRetry: () async => _launch(bootstrap, await bootstrap.run()),
        onReset: () async => _launch(bootstrap, await bootstrap.resetLocalDataAndRun()),
      ));
  }
}
