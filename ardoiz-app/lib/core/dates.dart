/// Une échéance « le 10 » signifie « jusqu'à la fin du 10 » : la dette ne devient
/// en retard que le 11. On enregistre donc la fin de la journée locale.
DateTime endOfLocalDay(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day, 23, 59, 59);
}

/// Jour calendaire local (sans heure).
DateTime localDateOnly(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Même bornage que le serveur (`clampClientDate`) : une date saisie sur
/// l'appareil reste dans [maintenant - 366 jours ; maintenant]. Appliqué aussi
/// en local pour que la valeur affichée avant l'envoi soit celle que le
/// serveur conservera.
DateTime clampToServerWindow(DateTime date, DateTime now) {
  final earliest = now.subtract(const Duration(days: 366));
  if (date.isAfter(now)) return now;
  if (date.isBefore(earliest)) return earliest;
  return date;
}
