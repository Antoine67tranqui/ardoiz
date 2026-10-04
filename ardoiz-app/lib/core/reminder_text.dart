import 'formatters.dart';
import 'money.dart';

/// Message de relance courtois, composé sur l'appareil (SMS/WhatsApp envoyés
/// depuis le téléphone du commerçant).
String reminderMessage({required String customerName, required String businessName, required Money remaining}) =>
    'Bonjour $customerName, ici $businessName. '
    'Il vous reste ${formatMoney(remaining)} à régler. '
    'Merci de passer nous voir dès que possible.';
