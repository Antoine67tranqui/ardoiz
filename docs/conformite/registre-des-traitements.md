# Registre des traitements de Carné

Éditeur et responsable pour les données de compte : CIVORA CONSEIL ET SOLUTIONS (sigle CCS), entreprise exploitée par Sedjro Antoine Tranquillin Affossogbe, RCCM de Cotonou n° RB/ABC/21 A 32517. Mise à jour : à chaque évolution fonctionnelle (voir la fin du document).

Légende des rôles : **R** = CIVORA est responsable du traitement ; **ST** = CIVORA traite pour le compte du commerçant, qui est responsable [qualification à faire valider par un juriste].

## Vue d'ensemble

| N° | Traitement | Rôle | Personnes concernées |
|---|---|---|---|
| T1 | Gestion des comptes et authentification | R | Commerçants |
| T2 | Carnet de crédit (clients, fournisseurs, dettes, remboursements) | ST | Clients et fournisseurs des commerçants |
| T3 | Caisse (ventes au comptant, dépenses) | ST | Commerçants (opérations de leur commerce) |
| T4 | Relances par SMS | ST | Clients des commerçants |
| T5 | Journal d'activité et sécurité | R | Commerçants |
| T6 | Consentement aux conditions | R | Commerçants |
| T7 | Abonnement Premium et paiement (pas encore ouvert) | R | Commerçants |

## T1. Gestion des comptes et authentification

| Rubrique | Contenu |
|---|---|
| Finalité | Créer le compte, vérifier le numéro, authentifier le commerçant. |
| Fondement | Exécution du service demandé ; consentement (inscription). [à valider] |
| Données | Numéro de téléphone, nom de la boutique, empreinte irréversible du PIN (bcrypt), empreinte du code SMS (5 minutes), compteurs d'essais, date de verrouillage, formule (gratuite ou Premium) et échéance. |
| Destinataires | Équipe technique de CIVORA (accès à la base). Prestataire SMS (numéro et code). Hébergeur. |
| Durée | Tant que le compte existe ; suppression à la demande du commerçant (action "Supprimer mon compte"). Empreinte du code SMS : effacée automatiquement au plus tard un jour après expiration. |
| Sécurité | PIN jamais en clair ; verrouillage de 15 minutes après 5 erreurs ; jetons à durée limitée (15 minutes et 30 jours) révoqués à la déconnexion et au changement de PIN ; limitation du débit des requêtes. |
| Transfert hors Bénin | Selon l'hébergeur et le prestataire SMS : [à compléter]. |

## T2. Carnet de crédit

| Rubrique | Contenu |
|---|---|
| Finalité | Tenir le carnet du commerçant : ce qu'on lui doit et ce qu'il doit. |
| Fondement | Exécution du service demandé par le commerçant. L'information des personnes notées relève du commerçant (texte fourni : voir information-des-clients-du-commercant.md). |
| Données | Nom, téléphone, plafond de crédit, refus éventuel des relances ; dettes et remboursements : montants, motifs, catégories, dates, moyen de paiement. |
| Personnes | Clients et fournisseurs du commerçant. Pas de personnes mineures visées. Pas de donnée dite sensible (santé, opinions, etc.) : le champ "motif" est libre, voir le risque R4 de l'analyse d'impact. |
| Destinataires | Le commerçant seul. L'équipe technique de CIVORA n'ouvre pas ces données en exploitation normale (voir la procédure d'accès). |
| Durée | Tant que le compte du commerçant existe. Suppression d'une fiche par le commerçant : immédiate, avec ses dettes et remboursements. Suppression du compte : tout est effacé. Sauvegardes : 30 jours au plus. |
| Sécurité | Chiffrement de la base du téléphone (AES-256, clé dans le coffre du téléphone) ; HTTPS ; cloisonnement strict entre commerçants (testé en recette) ; protection contre l'injection de formules dans les exports CSV. |
| Droits | Accès : le commerçant exporte la fiche (JSON). Opposition aux relances : case à cocher sur la fiche, ou commande d'administration `opt-out-contact`. |

## T3. Caisse

| Rubrique | Contenu |
|---|---|
| Finalité | Calculer la trésorerie du commerçant. |
| Données | Montant, date, libellé libre, catégorie. Aucune donnée sur l'acheteur. |
| Durée et sécurité | Comme T2. |

## T4. Relances par SMS

| Rubrique | Contenu |
|---|---|
| Finalité | Rappeler poliment à un client le reste à payer, à l'initiative du commerçant (envoi manuel) ou selon les étapes qu'il a programmées (Premium). |
| Données | Nom, numéro, montant restant, nom de la boutique, historique des envois (date, état). |
| Garde-fous | Aucune relance à un fournisseur, à une dette soldée, ni à une personne qui a refusé les relances (contrôlé côté serveur). Un envoi n'est jamais répété pour la même étape. |
| Destinataires | Prestataire SMS (Africa's Talking prévu, à confirmer). |
| Durée | Historique d'envoi : comme T2. |

## T5. Journal d'activité

| Rubrique | Contenu |
|---|---|
| Finalité | Sécurité du compte ; permettre au commerçant de repérer un accès inconnu. |
| Données | Type d'événement (création, connexion, verrouillage, changement de PIN, déconnexion, acceptation des conditions, exports) et date. Ni adresse IP, ni contenu du carnet. |
| Durée | 12 mois, purge automatique quotidienne à 03 h 30. |

## T6. Consentement

| Rubrique | Contenu |
|---|---|
| Finalité | Conserver la preuve de l'accord et de sa version. |
| Données | Version des textes acceptés, date. |
| Durée | Tant que le compte existe. |

## T7. Abonnement et paiement (non ouvert)

Non actif. Avant l'ouverture : nommer l'agrégateur de paiement dans la politique de confidentialité, signer son contrat, mettre à jour ce registre et republier les textes (nouvelle version, nouveau consentement). Carné ne conservera ni numéro de carte ni code secret Mobile Money.

## Mesures communes

- Hébergement : [à compléter]. Accès administrateur : [à compléter : personnes habilitées, authentification forte recommandée].
- Sauvegardes chiffrées, 30 jours de rétention (voir le guide de déploiement).
- Pas de traceur publicitaire, pas de cookie dans la version en ligne, pas de vente de données.

## Tenue du registre

À mettre à jour à chaque nouvelle fonction qui collecte une nouvelle donnée, change un destinataire ou une durée. Dernière revue : [à compléter à la publication]. Responsable de la tenue : [à compléter].
