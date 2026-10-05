# Procédure en cas de violation de données

Une violation est un incident de sécurité qui entraîne, de manière accidentelle ou illicite, la destruction, la perte, l'altération, la divulgation ou l'accès non autorisé à des données personnelles. Exemples : base copiée, accès administrateur volé, sauvegarde perdue, e-mail envoyé au mauvais destinataire, bug qui montre les données d'un commerçant à un autre.

D'après des sources secondaires, la loi béninoise impose de notifier l'APDP et la personne concernée "sans délai" [délai précis et seuil de gravité à vérifier sur le texte]. En attendant, retenir comme objectif interne : prévenir l'APDP dans les 72 heures après avoir constaté l'incident.

## Les responsables

| Rôle | Nom | Téléphone |
|---|---|---|
| Responsable de l'incident | [à compléter] | [à compléter] |
| Remplaçant | [à compléter] | [à compléter] |
| Juriste | [à compléter] | [à compléter] |

## Première heure : contenir

1. Noter l'heure de découverte et ce qui a été constaté (sans modifier les preuves : journaux du serveur, captures).
2. Couper la cause : fermer l'accès compromis, changer le mot de passe du compte concerné, mettre le service en maintenance si nécessaire.
3. Si des jetons ou des secrets ont pu fuiter : changer `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `JWT_OTP_SECRET` et `MOMO_WEBHOOK_SECRET` puis redémarrer le service. Effet : toutes les sessions sont invalidées, chaque commerçant devra se reconnecter par son PIN (les données locales du téléphone et du serveur ne sont pas perdues).
4. Si les clés du prestataire SMS ou de paiement ont pu fuiter : les révoquer dans leur tableau de bord et en créer de nouvelles.

## Premier jour : évaluer

Répondre par écrit à : quelles données (comptes, carnets, caisse) ? combien de commerçants et de personnes notées ? depuis quand ? les données étaient-elles lisibles (les PIN et les codes SMS ne le sont pas : seules leurs empreintes sont stockées) ? y a-t-il un risque pour les personnes (fraude, harcèlement, atteinte à la réputation) ?

## Notifier

- **APDP** : selon la procédure et le formulaire de l'autorité [à compléter après vérification]. Contenu minimal : nature de la violation, données et nombre de personnes concernés, conséquences probables, mesures prises, contact.
- **Commerçants concernés** : message clair par SMS ou dans l'application : ce qui s'est passé, ce que cela peut changer pour eux, ce qu'ils doivent faire (changer de PIN), qui contacter. Ne pas minimiser, ne pas jargonner.
- **Personnes notées** : si le risque pour elles est élevé, passer par les commerçants (CIVORA ne connaît que leurs numéros) ou par SMS.

## Après : corriger et apprendre

Corriger la cause, ajouter un test qui aurait détecté le problème, mettre à jour l'analyse d'impact, inscrire l'incident au registre des violations : date, description, personnes concernées, mesures, notifications faites.

## Modèle de message aux commerçants

> Carné : information de sécurité. Le [date], nous avons constaté [description simple]. Les données concernées sont [liste]. Votre code PIN n'a pas été exposé en clair. Par précaution, nous avons déconnecté tous les appareils : reconnectez-vous avec votre PIN et changez-le dans Réglages. Nous avons informé l'APDP. Pour toute question : [contact].
