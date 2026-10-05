# Analyse d'impact allégée

Méthode : pour chaque scénario, gravité pour la personne et vraisemblance avant et après les mesures de Carné. Échelle : faible, moyenne, élevée. Document de travail, à compléter après la première revue juridique. Il ne remplace pas une analyse d'impact formelle si l'APDP en exige une [à vérifier].

| N° | Scénario | Personnes touchées | Avant mesures | Mesures en place | Reste à faire |
|---|---|---|---|---|---|
| R1 | Prise de contrôle d'un compte (vol du téléphone, PIN deviné) | Commerçant et sa clientèle | Gravité élevée, vraisemblance moyenne | PIN à 4 chiffres limité à 5 essais puis verrouillage 15 min ; PIN jamais en clair ; sessions révoquées au changement de PIN ; journal d'activité visible ; base du téléphone chiffrée | Rappeler dans l'application de verrouiller le téléphone. Envisager un verrou d'écran propre à l'application si les tests terrain le demandent. |
| R2 | Accès d'un commerçant aux données d'un autre | Tous | Gravité élevée | Cloisonnement par compte sur chaque requête, testé en recette (403 et 404) ; identifiants de création rejoués par un autre commerçant refusés (409) | Test d'intrusion indépendant avant ouverture large. |
| R3 | Fuite de la base du serveur | Tous | Gravité élevée | HTTPS ; PIN et codes SMS en empreinte irréversible ; secrets hors du code ; sauvegardes chiffrées ; accès base restreint | Choisir un hébergeur avec chiffrement des disques ; limiter les accès administrateur ; procédure de violation (voir violation-de-donnees.md). |
| R4 | Données excessives ou sensibles saisies dans les champs libres (motif d'une dette) | Clients | Gravité moyenne | Longueur limitée ; texte d'information au commerçant | Ajouter dans l'application un rappel de ne pas noter de donnée de santé ou d'opinion. |
| R5 | Relances non voulues ou harcelantes | Clients | Gravité moyenne | Envoi manuel ou programmé par le commerçant uniquement ; opposition prise en compte côté serveur ; engagement de courtoisie dans les conditions | Mettre en place la réponse "STOP" automatique quand le prestataire SMS le permettra. |
| R6 | Numéro d'un client utilisé par un commerçant sans lien commercial réel | Clients | Gravité moyenne | Engagement dans les conditions ; opposition possible auprès de CIVORA | Procédure de signalement (voir droits-des-personnes.md). |
| R7 | Perte de données (panne, erreur) | Commerçants | Gravité moyenne | Copie sur le téléphone et sur le serveur ; synchronisation avec reprise ; sauvegardes quotidiennes | Test de restauration à planifier chaque trimestre. |
| R8 | Export CSV détourné (injection de formule dans un tableur) | Commerçant | Gravité moyenne | Neutralisation des cellules commençant par =, +, -, @ | Aucun. |
| R9 | Accès non autorisé par un administrateur de CIVORA | Tous | Gravité élevée | Aucune route d'administration en ligne ; outil en ligne de commande exécuté sur le serveur ; l'outil n'affiche pas le contenu des carnets | Journaliser les connexions au serveur ; liste nominative des personnes habilitées. |

Conclusion provisoire : risques résiduels acceptables pour un lancement pilote, sous réserve des points "reste à faire" de R1 à R3 et R9 et de la validation de l'APDP.
