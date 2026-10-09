import 'dart:io';

/// Répertoire temporaire pour les tests qui rouvrent une base sur disque.
class DatabaseDirectory {
  DatabaseDirectory._(this._dir);

  final Directory _dir;

  static DatabaseDirectory create() => DatabaseDirectory._(Directory.systemTemp.createTempSync('carne_test'));

  String get path => _dir.path;

  void dispose() => _dir.deleteSync(recursive: true);
}
