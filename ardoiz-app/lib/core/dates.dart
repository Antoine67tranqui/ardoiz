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
