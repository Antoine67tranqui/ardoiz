# Carné (application mobile)

Application Flutter hors ligne d'abord. Voir le `README.md` à la racine du dépôt pour le fonctionnement général, le lancement et la liste de contrôle avant production.

Organisation de `lib/` :

- `core/` : argent (`Money`, centimes), formats, validations, thème et marque, configuration.
- `domain/` : modèles et calculs purs (soldes, retards, tableau de bord, filtres), sans entrées-sorties.
- `data/local/` : base SQLCipher, schéma et migrations, file d'envoi (outbox), coffre de secrets.
- `data/remote/` : client HTTP (renouvellement de jeton sans boucle), API, exceptions typées.
- `data/sync/` : moteur de synchronisation (rejouable, dépendances entre opérations, reprise avec délai croissant).
- `data/repositories/` : écritures locales atomiques (donnée + opération d'envoi dans une transaction).
- `app/` : session, coordination de la synchronisation, démarrage, routeur, fournisseurs Riverpod.
- `ui/` : écrans et composants (accessibles : texte agrandi, lecteur d'écran, états jamais portés par la couleur seule).

Commandes : `flutter analyze` (aucun avertissement toléré), `flutter test`. Le logo (`brand/logo-mark.svg`) est redessiné dans `CarneLogoPainter` ; une image de référence (`test/goldens/logo.png`) signale tout changement involontaire.
