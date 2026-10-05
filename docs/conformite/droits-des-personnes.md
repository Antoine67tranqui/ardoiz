# Répondre aux demandes des personnes

Deux publics : les **commerçants** (qui ont un compte) et les **personnes notées** par un commerçant (clients, fournisseurs, qui n'ont pas de compte).

Délai de réponse : [à fixer avec le juriste ; viser un délai court et le publier dans la politique]. Journal des demandes : un tableau simple (date, nom, nature, réponse, date de réponse), conservé 3 ans [durée à valider].

## Vérifier qui demande

- Commerçant : la demande se fait dans l'application (connecté), donc l'identité est déjà établie. Pour une demande reçue par e-mail, répondre uniquement vers le numéro du compte, ou demander un code SMS via la fonction de connexion.
- Personne notée : la demande doit venir du numéro concerné (message depuis ce numéro, ou rappel de ce numéro). Ne jamais communiquer à un tiers ce qui est noté sur quelqu'un.

## Cas 1. Un commerçant veut voir, corriger ou emporter ses données

Tout est en libre service :

| Demande | Où |
|---|---|
| Copie complète | Application : Réglages, "Exporter toutes mes données" (JSON). Version en ligne : Réglages, "Toutes mes données (JSON)". Limité à 5 par heure. |
| Historique des dettes et remboursements | "Exporter l'historique" (CSV) |
| Journal de caisse | Version en ligne : "Caisse (tableur CSV)" |
| Journal de sécurité | "Activité du compte" |
| Correction | Modifier directement les fiches, les dettes, les paiements, le nom de la boutique |

## Cas 2. Un commerçant veut supprimer son compte

Application ou version en ligne : Réglages, "Supprimer mon compte", confirmation par le PIN. Effet immédiat sur le serveur et sur ce téléphone. Les sauvegardes disparaissent sous 30 jours. S'il a perdu son PIN : refaire la vérification par SMS (choix d'un nouveau PIN), puis supprimer.

## Cas 3. Une personne notée demande ce qui est noté sur elle

1. Lui répondre que ces données sont tenues par le commerçant et lui demander de s'adresser à lui.
2. Le commerçant peut télécharger la copie de cette personne depuis sa fiche ("Télécharger ses données", ou "Exporter les données" selon l'écran) : fichier JSON limité à cette personne.
3. Si la personne ne connaît pas le commerçant ou ne peut pas le joindre : l'éditeur ne peut pas lui communiquer le contenu (il ne consulte pas les carnets). Il peut, après vérification, transmettre la demande au commerçant si celui-ci est identifiable [procédure à valider par le juriste].

## Cas 4. Une personne notée ne veut plus de relances (opposition)

Procédure en 3 minutes, sans compte :

1. Vérifier que la demande vient du numéro concerné.
2. Sur le serveur, exécuter : `cd ardoiz-backend && npm run admin -- opt-out-contact +229XXXXXXXXXX` (voir l'aide de l'outil ; en conteneur : `docker compose exec backend node dist/admin/cli.js opt-out-contact +229XXXXXXXXXX`).
3. L'outil marque comme "refuse les relances" toutes les fiches de client portant ce numéro, chez tous les commerçants (comparaison sur les 8 derniers chiffres, quel que soit le format saisi). Il répond avec le nombre de fiches modifiées. Aucun message ne peut plus lui être envoyé : le serveur refuse l'envoi manuel comme l'envoi programmé.
4. Confirmer à la personne, sans lui communiquer le nom des commerçants.
5. Inscrire la demande dans le journal des demandes.

Limite connue : l'opposition vise les fiches existantes. Si un commerçant crée plus tard une nouvelle fiche avec ce numéro, elle n'est pas bloquée automatiquement. Amélioration possible : liste d'opposition consultée à la création d'une fiche (à décider).

## Cas 5. Une personne conteste être cliente d'un commerçant

Demander au commerçant de justifier ou de supprimer la fiche. À défaut de réponse sous [délai], appliquer le cas 4 pour stopper les messages et noter la contestation. Cas répété pour un même commerçant : suspendre le compte (conditions, article 4 et 10).

## Réclamation

Informer la personne de son droit de saisir l'APDP [coordonnées à compléter après vérification sur le site officiel].
