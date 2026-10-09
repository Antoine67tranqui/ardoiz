# Sous-traitants et prestataires

Pour chaque prestataire qui touche à des données personnelles, il faut un contrat ou des conditions acceptées qui prévoient au minimum : usage limité aux instructions de CIVORA, confidentialité, sécurité, aide pour les demandes des personnes, notification des incidents, suppression en fin de contrat, et la liste des pays où les données sont traitées.

| Prestataire | Rôle | Données reçues | Pays | Statut | À faire |
|---|---|---|---|---|---|
| Hébergeur (à choisir) | Serveur et base de données | Toutes (données du carnet et des comptes) | [à compléter] | À choisir | Comparer au moins deux offres (voir guide-deploiement.md). Préférer un hébergement au Bénin ou dans un pays reconnu comme offrant une protection adéquate [à vérifier auprès de l'APDP]. Obtenir le contrat ou les conditions. |
| Africa's Talking (prévu) | Envoi des SMS (codes, relances) | Numéro du destinataire, texte du message | [à compléter] | À confirmer | Ouvrir le compte, enregistrer l'identifiant d'expéditeur pour le Bénin (délais et opérateurs à vérifier), lire et conserver les conditions de traitement des données. |
| FedaPay (prévu, non ouvert) | Paiement de l'abonnement Mobile Money | Montant, numéro du payeur | Bénin (société béninoise, à vérifier) | Clés de test reçues, jamais utilisées sur le serveur de production | Valider le compte (KYC), signer les conditions, tester en bac à sable, puis nommer FedaPay dans la politique avant l'ouverture. |
| Google Play (diffusion Android) | Distribution de l'application | Données techniques de téléchargement (côté Google) ; aucune donnée du carnet | Hors Bénin | Compte à ouvrir | Remplir le formulaire "sécurité des données" de la fiche de l'application de façon cohérente avec ce registre. |
| GitHub | Hébergement du code | Aucune donnée personnelle de production | Hors Bénin | En place | Ne jamais déposer de donnée réelle ni de secret dans le dépôt. |

Les clés FedaPay de test transmises pendant le développement doivent être considérées comme exposées : à régénérer dans le tableau de bord FedaPay avant toute mise en production, et à ne stocker que dans les variables d'environnement du serveur.
