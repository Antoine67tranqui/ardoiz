# Guide de déploiement de Carné, pas à pas

Pour : CIVORA CONSEIL ET SOLUTIONS. Objectif : passer du code livré à un service en ligne, une application Android installable et un test sur le terrain, sans surprise.

## 0. Où en est le projet, honnêtement

| Élément | État | Comment c'est vérifié |
|---|---|---|
| API (NestJS, PostgreSQL) | Prête | 34 tests unitaires et 149 tests de bout en bout sur une vraie base |
| Client web en ligne | Prêt | tests statiques (site et client) et 13 scénarios dans un vrai navigateur (Chromium) contre l'API réelle |
| Site vitrine et pages légales | Prêts, **textes à compléter** | Tests automatiques ; les passages [à compléter] sont volontairement visibles |
| Application Android (Flutter) | Code prêt | Plus de 350 tests (widgets, base chiffrée, synchronisation) et 12 tests contre l'API réelle. **L'application n'a pas été compilée en APK dans l'environnement de développement** : la première compilation aura lieu sur GitHub (étape 10) |
| Sauvegarde chiffrée et restauration | Prêtes | Testées de bout en bout sur une vraie base (script `deploy/test/backup-restore.sh`) |
| Docker, Caddy (HTTPS), compose | Écrits, **non exécutés ici** | Il n'y a pas de moteur Docker dans l'environnement de développement. Les tâches d'intégration continue construisent les images, valident le Caddyfile et démarrent l'API en mode production à chaque modification (voir les onglets "Actions" de GitHub). Le premier déploiement réel est donc le premier vrai essai complet |
| Envoi de SMS réel | Non testé | Aucun compte Africa's Talking n'a été utilisé. Tant que ses clés sont absentes, les SMS sont simulés |
| Paiement Mobile Money (FedaPay) | **Fermé volontairement** | Le réseau de l'environnement de développement bloque FedaPay : rien n'a pu être testé. L'application affiche franchement "paiement pas encore disponible" |
| Textes juridiques, déclaration APDP | À faire | Voir `docs/conformite/` |

Principe : rien n'est affiché comme fonctionnel s'il n'a pas été vérifié.

## 1. Vue d'ensemble et ordre conseillé

2. Décisions de départ (domaine, hébergeur, adresse e-mail, personne chargée des données)
3. Nom de domaine
4. Serveur et sécurisation
5. Configuration et premier lancement
6. Contrôles après lancement
7. SMS (Africa's Talking)
8. Premiers comptes et Premium manuel
9. Paiement FedaPay (en dernier, quand le reste fonctionne)
10. Application Android : signature, compilation, test, Google Play
11. Textes juridiques et déclaration à l'APDP
12. Pilote sur le terrain
13. Exploitation courante
14. Liste de contrôle avant l'ouverture au public

(Les numéros correspondent aux titres de ce document.)

Les étapes 7, 9, 10 et 11 ont des délais d'attente administratifs (validation de l'identifiant d'expéditeur SMS, validation du compte de paiement, validation du compte Google Play, réponse de l'APDP) : **lancez-les en parallèle dès le début**, elles ne dépendent pas du serveur.

## 2. Décisions de départ

| Décision | Conseil |
|---|---|
| Domaine | Un seul domaine suffit (site, client web et API partagent la même origine). Exemple : `carne.example`. |
| Hébergeur | Voir l'étape 4. La question à poser : où sont stockées les données ? C'est un point à déclarer à l'APDP et à publier dans la politique de confidentialité. |
| Adresse e-mail dédiée | Créez `donnees@votre-domaine` (ou équivalent) pour les demandes de droits : elle apparaît dans les textes juridiques. |
| Personne chargée de la protection des données | Vous-même ou un prestataire ; son nom ou sa fonction figure dans la politique. |

## 3. Nom de domaine

1. Choisissez un registraire reconnu et achetez le nom de domaine (frais annuels variables selon l'extension ; demandez le prix avant de payer).
2. Gardez l'accès au compte du registraire sécurisé : mot de passe unique, double authentification.
3. Vous créerez un enregistrement **A** vers l'adresse IP du serveur (étape 4) une fois celui-ci acheté. Prévoyez aussi, si vous l'utilisez, un enregistrement **AAAA** pour l'IPv6.

Ne pas vérifié ici : les conditions d'enregistrement d'une extension nationale `.bj`. Renseignez-vous directement auprès du registre ou d'un registraire accrédité.

## 4. Serveur et sécurisation

### 4.1 Choisir l'hébergeur

Critères, par ordre d'importance :

1. **Localisation des données.** Un hébergement au Bénin simplifie la conformité (pas de transfert international à justifier). Un hébergement hors du Bénin est possible, mais il faut l'indiquer à l'APDP et dans la politique, et vérifier avec elle les conditions du transfert [point non vérifié, voir docs/conformite/].
2. **Sauvegardes et reprise** : possibilité de snapshots, accès console si SSH échoue.
3. **Fiabilité de la connexion vers le Bénin** : testez avec un ping et un chargement de page depuis les téléphones de vos futurs utilisateurs avant de vous engager.
4. **Support en français ou en anglais**, facturation claire, résiliation sans frais cachés.

Demandez des devis à au moins deux fournisseurs, dont un fournisseur béninois si possible. Je n'ai pas pu vérifier ici les offres actuelles ni les prix : ne vous fiez pas à un chiffre que je pourrais donner de mémoire.

Taille minimale raisonnable pour un pilote (estimation d'ingénierie, à ajuster après mesure) : 2 processeurs virtuels, 2 Go de mémoire, 40 Go de disque, Ubuntu LTS.

### 4.2 Sécuriser le serveur (à faire avant tout le reste)

Sur le serveur, en tant qu'administrateur :

```sh
# 1. Mises à jour
sudo apt update && sudo apt -y upgrade
# 2. Utilisateur non-root avec votre clé SSH, puis désactiver le mot de passe SSH
sudo adduser deploy && sudo usermod -aG sudo deploy
#    (copiez votre clé publique dans /home/deploy/.ssh/authorized_keys)
#    puis dans /etc/ssh/sshd_config : PasswordAuthentication no et PermitRootLogin no
sudo systemctl restart ssh
# 3. Pare-feu : seulement SSH, HTTP, HTTPS
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 443/udp && sudo ufw enable
# 4. Mises à jour de sécurité automatiques
sudo apt -y install unattended-upgrades
# 5. Docker (suivre la procédure officielle : https://docs.docker.com/engine/install/ubuntu/)
sudo usermod -aG docker deploy
```

Testez la connexion SSH avec l'utilisateur `deploy` **avant** de fermer votre session root.

Attention : Docker contourne parfois les règles de `ufw` pour les ports publiés. Notre configuration ne publie que les ports 80 et 443 (les seuls voulus) ; ne publiez jamais le port de la base de données.

### 4.3 Enregistrement DNS

Créez l'enregistrement A de votre domaine vers l'adresse IP du serveur. Attendez la propagation (quelques minutes à quelques heures) : `dig +short carne.example` doit renvoyer l'adresse du serveur. **Caddy a besoin de cette résolution pour obtenir son certificat HTTPS.**

## 5. Configuration et premier lancement

```sh
# Sur le serveur, utilisateur deploy
git clone https://github.com/antoine67tranqui/ardoiz.git carne && cd carne
git checkout claude/trusting-lovelace-2wopl4    # ou la branche principale une fois fusionnée
cd deploy
cp .env.production.example .env && chmod 600 .env
sh generate-secrets.sh     # copiez les valeurs dans .env : DB_PASSWORD, trois JWT, MOMO_WEBHOOK_SECRET
```

Renseignez dans `.env` : `DOMAIN`, `ACME_EMAIL` (adresse qui recevra les alertes de renouvellement de certificat), les secrets générés.

### 5.1 Clé de sauvegarde (sur VOTRE poste, pas sur le serveur)

```sh
age-keygen -o age-key-carne.txt      # affiche la clé publique "age1..."
```

- Copiez la clé **publique** (`age1...`) dans `BACKUP_AGE_RECIPIENT`.
- Conservez `age-key-carne.txt` (clé **privée**) dans un coffre-fort de mots de passe **et** sur un support hors ligne. **Sans elle, les sauvegardes sont illisibles. Avec elle, quiconque lit vos sauvegardes lit vos données : ne la mettez jamais sur le serveur ni dans le dépôt.**

### 5.2 Lancer

```sh
docker compose up -d --build
docker compose ps          # tous les services "running", migrate "exited (0)"
docker compose logs -f api # doit afficher le démarrage sans erreur
```

Si l'API refuse de démarrer, le message dit pourquoi (secret d'exemple, trop court, identique à un autre). C'est voulu : elle refuse plutôt que de tourner avec une configuration dangereuse.

## 6. Contrôles après lancement

```sh
SMOKE_ALLOW_PLACEHOLDERS=1 sh smoke.sh https://carne.example
```

Le script vérifie : API en ligne, en-têtes de sécurité (HTTPS strict, politique de contenu), client web servi avec sa politique, pages légales présentes, fichiers de test inaccessibles, routes protégées, redirection de HTTP vers HTTPS. **Sans** `SMOKE_ALLOW_PLACEHOLDERS=1`, il échoue tant que des passages [à compléter] restent dans les textes : c'est le contrôle final avant la publication (étape 11).

Ensuite, ouvrez `https://carne.example/app/index.html` dans un navigateur, créez un compte avec votre numéro. **Tant que les SMS réels ne sont pas branchés (étape 7), le code de vérification n'est pas envoyé** : en production il n'est jamais affiché non plus (sécurité). Passez donc à l'étape 7 avant de tester l'inscription.

Sauvegarde : lancez-en une tout de suite pour vérifier : `docker compose exec backup /usr/local/bin/backup.sh` puis `docker compose exec backup ls -l /backups`.

## 7. SMS avec Africa's Talking

1. Créez un compte sur le site d'Africa's Talking, créez une application, notez le **nom d'utilisateur** et générez une **clé API**.
2. Pour tester gratuitement sans envoyer de vrais SMS, le nom d'utilisateur `sandbox` existe (voir `.env.example`).
3. **Identifiant d'expéditeur (nom affiché à la place du numéro).** Au Bénin, l'identifiant alphanumérique (11 caractères maximum) doit être enregistré à l'avance ; d'après les sources consultées, il se demande dans le tableau de bord du fournisseur, avec une lettre sur papier à en-tête de l'entreprise et des exemples de messages, pour une approbation en général de 2 à 5 jours ouvrables. Préparez : la lettre de CIVORA, des exemples de vos SMS (code de vérification, relance). **Faites cette demande dès le premier jour.** Tant qu'elle n'est pas approuvée, les SMS peuvent partir avec un autre expéditeur ou être filtrés selon l'opérateur : testez sur des numéros MTN et Moov.
4. Renseignez dans `.env` : `SMS_USERNAME`, `SMS_API_KEY`, `SMS_SENDER_ID`, puis `docker compose up -d` (redémarre l'API avec la nouvelle configuration).
5. Testez : inscription avec votre numéro, vérifiez la réception du code et mesurez le délai. Faites-le sur plusieurs opérateurs.
6. Mettez à jour le prestataire cité dans `confidentialite.html` si vous changez d'agrégateur.

Non vérifié ici : les tarifs, la couverture réelle de chaque opérateur béninois, la nécessité d'une démarche auprès du régulateur pour des SMS applicatifs. Demandez-le au fournisseur par écrit.

## 8. Premiers comptes et Premium manuel

Tant que le paiement en ligne est fermé, vous accordez Premium à la main, aux commerçants pilotes :

```sh
docker compose exec api node dist/admin/cli.js grant-premium +2290167070027 90   # 90 jours
docker compose exec api node dist/admin/cli.js show +2290167070027               # état du compte, sans le contenu du carnet
docker compose exec api node dist/admin/cli.js revoke-premium +2290167070027
```

Il n'existe aucune route d'administration sur internet : ces commandes ne s'exécutent que sur le serveur.

## 9. Paiement Mobile Money avec FedaPay (en dernier)

**Important, sécurité.** Les clés de test que vous m'avez transmises dans la conversation sont à considérer comme exposées. Elles ne sont dans aucun fichier du dépôt (un test automatique le vérifie). Pour un environnement de test c'est un risque faible, mais **régénérez-les** dans le tableau de bord FedaPay avant de les utiliser sérieusement, et ne mettez jamais de clé de production dans une conversation, un e-mail ou le dépôt : uniquement dans `deploy/.env` sur le serveur (`chmod 600`).

État du code : l'intégration réelle **n'est pas écrite**, parce que je n'ai pas pu joindre FedaPay depuis l'environnement de développement (accès bloqué) et que je ne veux pas écrire une intégration financière "de mémoire". Ce qui est prêt :

- l'application et l'API refusent franchement le paiement tant qu'il est fermé (aucune simulation trompeuse en production) ;
- un script de vérification en bac à sable : `ardoiz-backend/scripts/fedapay-sandbox-check.mjs`. Il crée une transaction de test de 100 XOF, demande le lien de paiement, relit le statut, et n'affiche que la **forme** des réponses (jamais la clé ni les jetons). Il refuse toute clé de production.

Procédure :

1. Sur votre poste (avec accès internet normal) : `FEDAPAY_SECRET_KEY=sk_sandbox_... node ardoiz-backend/scripts/fedapay-sandbox-check.mjs`.
2. Copiez la sortie dans la conversation de développement : l'intégration sera écrite d'après les réponses réelles (champs, statuts, vérification de la signature des notifications), puis testée.
3. Créez le compte **réel** (live) sur FedaPay et soumettez-le à validation. D'après la documentation consultée, pour une entreprise : RCCM, IFU, pièce d'identité du représentant légal et signature, en scans lisibles des originaux. Préparez ces pièces maintenant : la validation prend du temps.
4. Renseignez le compte Mobile Money (MTN ou Moov) qui recevra les fonds ; il est vérifié par un code SMS.
5. Quand l'intégration est vérifiée en bac à sable, passez en production : clés réelles dans `.env`, mise à jour de la politique de confidentialité (nommer FedaPay, version des textes changée), test avec de vrais petits montants.
6. Avant l'ouverture, vérifiez auprès de FedaPay ses frais et ses conditions d'usage pour l'encaissement d'abonnements : je n'ai pas pu les consulter.

## 10. Application Android

### 10.1 Créer la clé de signature (une seule fois, à conserver toute la vie de l'application)

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Gardez le fichier et les mots de passe dans un coffre-fort, avec une copie hors ligne. Si vous utilisez Google Play App Signing (recommandé, activé par défaut pour les nouvelles applications), cette clé est une "clé d'importation" que Google peut réinitialiser en cas de perte ; sans cela, sa perte est définitive.

### 10.2 Secrets et variables GitHub

Dépôt GitHub, Settings, Secrets and variables, Actions :

| Type | Nom | Valeur |
|---|---|---|
| Secret | `ANDROID_KEYSTORE_BASE64` | résultat de `base64 -w0 upload-keystore.jks` |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | mot de passe du fichier de clé |
| Secret | `ANDROID_KEY_ALIAS` | `upload` |
| Secret | `ANDROID_KEY_PASSWORD` | mot de passe de la clé |
| Variable | `CARNE_API_BASE_URL` | `https://carne.example/api/v1` |
| Variable | `CARNE_WEB_URL` | `https://carne.example/` |

### 10.3 Compiler

1. Vérifiez la version dans `ardoiz-app/pubspec.yaml` (`version: 0.2.0+2` : le nombre après `+` est le numéro de build, il doit augmenter à chaque envoi sur Google Play).
2. `git tag app-v0.2.0 && git push origin app-v0.2.0` : la tâche "Release Android" analyse, teste, compile l'app bundle (`.aab`, pour Google Play) et l'APK (installation directe), **refuse un APK signé avec la clé de débogage**, puis dépose les fichiers dans les "artefacts" de l'exécution (téléchargeables 30 jours).
3. **Si cette première compilation échoue** (c'est possible : c'est le premier vrai build Android), envoyez le journal d'erreur : c'est exactement ce qu'il faut pour corriger.

### 10.4 Tester l'APK sur de vrais téléphones, avant Google Play

Installez l'APK sur 2 ou 3 téléphones Android de modèles et de versions différents (dont un modèle d'entrée de gamme). Parcours à dérouler : inscription par SMS, ajout d'un client, ardoise, remboursement, mode avion (saisie hors connexion puis retour du réseau), fournisseur, caisse, export, suppression de compte, texte agrandi dans les réglages du téléphone.

### 10.5 Google Play

D'après les sources consultées :

- Frais d'inscription unique de 25 USD, pour un compte personnel comme pour un compte organisation.
- Un **compte organisation** exige un numéro D-U-N-S (identifiant à neuf chiffres délivré par Dun & Bradstreet, gratuit mais pouvant prendre jusqu'à environ 30 jours). Les comptes organisation ne sont en général pas soumis à l'obligation de test fermé ci-dessous.
- Un **compte personnel** créé après le 13 novembre 2023 doit mener un **test fermé** avec au moins 12 testeurs inscrits en continu pendant 14 jours avant de demander l'accès à la production. Le test interne ne compte pas.

Recommandation : si CIVORA peut obtenir son numéro D-U-N-S, créez un compte **organisation** au nom de CIVORA CONSEIL ET SOLUTIONS : cela évite la contrainte des 12 testeurs, et l'éditeur affiché dans la boutique est votre structure. Lancez la demande de D-U-N-S tout de suite. Sinon, recrutez dès maintenant 12 commerçants ou proches comme testeurs (c'est de toute façon utile pour le pilote).

Dans la console :

1. Créez l'application "Carné", langue par défaut français.
2. Politique de confidentialité : `https://carne.example/confidentialite.html` (obligatoire).
3. Section "Sécurité des données" : remplissez-la en cohérence avec `docs/conformite/registre-des-traitements.md` (données collectées : numéro de téléphone, contacts saisis par l'utilisateur, informations financières saisies ; chiffrées en transit ; suppression possible depuis l'application et via l'adresse indiquée).
4. Public cible : adultes, commerçants. Pas d'annonces.
5. Importez le `.aab`, lancez le test fermé (ou interne puis production selon votre type de compte), ajoutez les captures d'écran (à faire sur de vrais appareils) et l'icône (déjà dans `brand/`).
6. Les délais de revue de Google ne sont pas garantis : prévoyez plusieurs jours.

Non vérifié ici : les exigences de la fiche (captures d'écran, classification du contenu, déclarations "services financiers" éventuelles pour une application de suivi de dettes). Lisez les écrans de la console : ils listent ce qui manque.

## 11. Textes juridiques et déclaration à l'APDP

1. Ouvrez `docs/conformite/points-a-completer.md` : tout ce que seul vous pouvez renseigner (adresse, RCCM, IFU, e-mail, hébergeur, durées).
2. Faites relire les trois pages (`confidentialite.html`, `conditions.html`, `mentions-legales.html`) par un juriste béninois.
3. Déposez la formalité auprès de l'APDP (`docs/conformite/dossier-apdp.md`). Notez la référence du récépissé dans la politique.
4. Quand c'est terminé, supprimez les passages [à compléter], adaptez le test `ardoiz-web/test/site.test.mjs` qui les exige (il est là pour empêcher une publication accidentelle), puis lancez `sh deploy/smoke.sh https://carne.example` **sans** l'exception : il doit passer.
5. Si le texte change, changez la version (`ardoiz-backend/src/common/legal.ts`, `ardoiz-app/lib/core/legal.dart`, `ardoiz-web/app/config.js` : un test vérifie qu'elles sont identiques). Tous les utilisateurs devront alors accepter de nouveau.

Identité CIVORA : le logo n'est pas intégré, car le dossier "Logo" de votre Drive ne contenait aucun fichier lisible pour moi. Déposez le fichier (SVG de préférence) dans `ardoiz-web/assets/civora-logo.svg` et demandez l'intégration. Le nom "CIVORA CONSEIL ET SOLUTIONS" figure déjà dans l'application (réglages, écran d'accueil), le site, le client web et les textes légaux.

## 12. Pilote sur le terrain

Avant de lancer largement, testez avec 5 à 10 commerçants réels pendant 3 à 4 semaines.

| À mesurer | Comment |
|---|---|
| Arrivée du code SMS | Délai ressenti, échecs, par opérateur |
| Compréhension | Observez 3 commerçants utiliser l'application sans explication : où hésitent-ils ? |
| Utilisation réelle | Nombre d'ardoises saisies par semaine par commerçant (via les comptes, avec leur accord) |
| Hors connexion | Y a-t-il des synchronisations bloquées ? (écran "Modifications à vérifier") |
| Relances | Un client a-t-il mal réagi ? Combien d'oppositions ? |
| Support | Quelles questions reviennent ? Les noter dans un tableau |

Prévenez les commerçants que Carné est en phase de test, faites-leur accepter les conditions, et donnez-leur un numéro d'appel. Les clients des commerçants doivent être informés : voir `docs/conformite/information-des-clients-du-commercant.md`.

## 13. Exploitation courante

| Tâche | Fréquence | Commande ou action |
|---|---|---|
| Mise à jour du code | À chaque version | `cd carne && git pull && cd deploy && docker compose up -d --build` (les migrations de base de données s'appliquent automatiquement avant le redémarrage de l'API) |
| Sauvegarde hors du serveur | Chaque jour | Les sauvegardes sont chiffrées : copiez le dossier vers un autre lieu (autre fournisseur ou autre pays) avec `rclone` ou `scp`. Une copie sur le même serveur ne protège pas d'un incendie ou d'une suppression du serveur |
| Test de restauration | Chaque trimestre | `deploy/backup/restore.sh` sur votre poste vers une base vide ; vérifier que les comptes et les ardoises sont là |
| Surveillance | Continue | Un service de surveillance externe qui sonde `https://carne.example/api/v1/health` et vous prévient par SMS ou e-mail (je n'ai pas évalué de service précis) |
| Journaux | Chaque semaine au début | `docker compose logs --since 24h api` : erreurs inhabituelles ; le journal d'accès du serveur web ne contient ni adresse IP ni en-têtes, et est conservé 30 jours |
| Espace disque | Chaque mois | `df -h` ; `docker system df` |
| Secrets | À chaque départ d'une personne ayant eu accès, ou en cas de doute | Régénérer (`generate-secrets.sh`), mettre à jour `.env`, `docker compose up -d` : toutes les sessions sont fermées, les utilisateurs se reconnectent |
| Mises à jour de sécurité du serveur | Automatiques | Redémarrer si le système l'exige |
| Demandes de droits | À la réception | `docs/conformite/droits-des-personnes.md` |
| Incident | Quand il survient | `docs/conformite/violation-de-donnees.md` |

## 14. Liste de contrôle "on ouvre au public"

- [ ] Serveur sécurisé (SSH par clé, pare-feu, mises à jour automatiques)
- [ ] HTTPS valide, `smoke.sh` passe **sans** exception
- [ ] SMS réels testés sur MTN et Moov, identifiant d'expéditeur approuvé
- [ ] Sauvegarde automatique vérifiée, copie hors serveur en place, restauration testée
- [ ] Clé privée de sauvegarde conservée hors du serveur, avec une copie
- [ ] Textes juridiques complétés et relus par un juriste, aucun [à compléter] restant
- [ ] Déclaration APDP déposée, référence inscrite
- [ ] Adresse e-mail des demandes de droits active, procédures lues
- [ ] APK testé sur au moins 3 téléphones, tous les parcours déroulés
- [ ] Compte Google Play validé, fiche complète, test fermé terminé si requis
- [ ] Pilote terminé, problèmes majeurs corrigés
- [ ] Paiement : soit fermé et annoncé comme tel, soit intégration vérifiée en bac à sable, clés réelles, texte mis à jour

## Sources consultées pour ce guide

- Google, Play Console Help, exigences de test pour les nouveaux comptes personnels : https://support.google.com/googleplay/android-developer/answer/14151465?hl=en
- Frais d'inscription de 25 USD et numéro D-U-N-S pour les comptes organisation (articles tiers, à recouper avec la console) : https://www.testerscommunity.com/blog/google-play-developer-account-guide et https://consolemint.com/google-play-console-price/
- Enregistrement de l'identifiant d'expéditeur au Bénin, Africa's Talking (articles tiers, à confirmer auprès du fournisseur) : https://www.sent.dm/en/resources/sms-compliance/bj-sms-guidance et https://bird.com/sms-api/features/destinations/benin
- FedaPay, activation du compte et pièces demandées : https://docs-v1.fedapay.com/compte/votre-compte et https://docs.fedapay.com/dashboard/fr/dashboard-fr
- FedaPay, création d'une transaction et d'un jeton (API) : https://docs-v1.fedapay.com/payments/transactions
- Installation de Docker sur Ubuntu : https://docs.docker.com/engine/install/ubuntu/
- Autorité de protection des données personnelles du Bénin : voir `docs/conformite/README.md`.

Tous les liens ci-dessus ont été trouvés par recherche ; leur contenu intégral n'a pas pu être consulté depuis l'environnement de développement. Vérifiez les conditions actuelles à la source avant d'agir.
