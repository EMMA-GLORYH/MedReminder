// lib/localization/app_localizations.dart
//
// Lightweight, hand-rolled localization (no build_runner / gen-l10n needed).
// Add new keys to every language map below as you localize more screens.

import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
  _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'), // English
    Locale('fr'), // French
    Locale('tw'), // Twi
    Locale('ee'), // Ewe
  ];

  static String displayNameFor(Locale locale) {
    switch (locale.languageCode) {
      case 'fr':
        return 'Français';
      case 'tw':
        return 'Twi';
      case 'ee':
        return 'Eʋegbe';
      default:
        return 'English';
    }
  }

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'markAsTaken': 'Mark as Taken',
      'saving': 'Saving…',
      'notDueYet': 'Not due yet',
      'availableAt': 'Available at {time}',
      'tapToMarkTaken': 'Tap to mark as taken',
      'overdue': 'Overdue',
      'dueSoon': 'Due Soon',
      'upcoming': 'Upcoming',
      'stopReminder': 'Stop Reminder',
      'reminderActiveTitle': 'Reminder Active',
      'reminderActiveBody':
      'You have not marked this dose as taken yet.\n\nWould you like to stop the reminder?',
      'cancel': 'Cancel',
      'medicationReminder': 'Medication Reminder',
      'noImageAvailable': 'No image available for this medicine',
      'doseMarkedTaken': 'Dose marked as taken ✓',
      'failedToMarkDose': 'Failed to mark dose. Try again.',
      'notDueSnackbar': 'This dose isn\'t due yet. It will be available at {time}.',
      'ttsReminderMessage':
      'It is time to take {name}. Dosage: {dosage}. Please take your medicine now.',
      'allDoneTitle': 'All done for today!',
      'allDoneBody': 'You\'ve taken all {count} of your doses. Great job!',
      'nothingScheduled': 'Nothing scheduled today',
      'nothingScheduledBody':
      'Once you add medications with schedules,\nyour daily doses will appear here.',
      'addMedication': 'Add Medication',
      'couldNotLoadSchedule': 'Could not load schedule',
      'retry': 'Retry',
    },
    'fr': {
      'markAsTaken': 'Marquer comme pris',
      'saving': 'Enregistrement…',
      'notDueYet': 'Pas encore l\'heure',
      'availableAt': 'Disponible à {time}',
      'tapToMarkTaken': 'Touchez pour marquer comme pris',
      'overdue': 'En retard',
      'dueSoon': 'Bientôt',
      'upcoming': 'À venir',
      'stopReminder': 'Arrêter le rappel',
      'reminderActiveTitle': 'Rappel actif',
      'reminderActiveBody':
      'Vous n\'avez pas encore marqué cette dose comme prise.\n\nVoulez-vous arrêter le rappel ?',
      'cancel': 'Annuler',
      'medicationReminder': 'Rappel de médicament',
      'noImageAvailable': 'Aucune image disponible pour ce médicament',
      'doseMarkedTaken': 'Dose marquée comme prise ✓',
      'failedToMarkDose': 'Échec de l\'enregistrement. Réessayez.',
      'notDueSnackbar':
      'Cette dose n\'est pas encore due. Elle sera disponible à {time}.',
      'ttsReminderMessage':
      'Il est temps de prendre {name}. Dosage : {dosage}. Veuillez prendre votre médicament maintenant.',
      'allDoneTitle': 'Tout est fait pour aujourd\'hui !',
      'allDoneBody': 'Vous avez pris les {count} doses. Bravo !',
      'nothingScheduled': 'Rien de prévu aujourd\'hui',
      'nothingScheduledBody':
      'Une fois que vous ajoutez des médicaments avec des horaires,\nvos doses quotidiennes apparaîtront ici.',
      'addMedication': 'Ajouter un médicament',
      'couldNotLoadSchedule': 'Impossible de charger le programme',
      'retry': 'Réessayer',
    },
    // ⚠️ Twi (Akan) — best-effort machine/reference translation.
    // Please have a fluent Twi speaker review before shipping to production.
    'tw': {
      'markAsTaken': 'Kyerɛ sɛ Mafa',
      'saving': 'Rekora…',
      'notDueYet': 'Mmerɛ no nnuu ɛ',
      'availableAt': 'Ɛbɛba {time}',
      'tapToMarkTaken': 'Fa nsa ka sɛ woafa aduro no',
      'overdue': 'Aka akyi',
      'dueSoon': 'Ɛreba',
      'upcoming': 'Ɛreba',
      'stopReminder': 'Gyae Nkae no',
      'reminderActiveTitle': 'Nkae no Da So Reyɛ Adwuma',
      'reminderActiveBody':
      'Wonkyerɛɛ sɛ woafa aduro yi.\n\nWo pɛ sɛ wugyae nkae no?',
      'cancel': 'Twa Mu',
      'medicationReminder': 'Aduro Nkaebɔ',
      'noImageAvailable': 'Aduro yi mfoni nni hɔ',
      'doseMarkedTaken': 'Wɔakyerɛ sɛ woafa aduro no ✓',
      'failedToMarkDose': 'Antumi ankyerɛ sɛ woafa aduro no. San yɛ bio.',
      'notDueSnackbar': 'Mmerɛ no nnuu ɛ. Ɛbɛba {time}.',
      'ttsReminderMessage':
      'Berɛ aso sɛ wofa {name}. Dosage: {dosage}. Yɛ sɛ fa wo aduro seesei.',
      'allDoneTitle': 'Woawie nnɛ nyinaa!',
      'allDoneBody': 'Woafa wo nnuro {count} nyinaa. Adwuma pa!',
      'nothingScheduled': 'Biribiara nni hɔ ma ɛnnɛ',
      'nothingScheduledBody':
      'Sɛ wode nnuro a wɔahyehyɛ ba a,\nwo da biara aduro bɛda adi wɔ ha.',
      'addMedication': 'Fa Aduro Ka Ho',
      'couldNotLoadSchedule': 'Antumi anhyɛ nhyehyɛe no mu',
      'retry': 'San Sɔ Hwɛ',
    },
    // ⚠️ Ewe — best-effort machine/reference translation.
    // Please have a fluent Ewe speaker review before shipping to production.
    'ee': {
      'markAsTaken': 'Dze edzi be Meno',
      'saving': 'Wole eŋlɔm…',
      'notDueYet': 'Ɣeyiɣia mede haɖeke o',
      'availableAt': 'Anɔ eteƒe le {time}',
      'tapToMarkTaken': 'Ka asi eŋu be nàɖo dzesi be èno atikea',
      'overdue': 'Eva yi',
      'dueSoon': 'Egogo',
      'upcoming': 'Gbɔna',
      'stopReminder': 'Tɔ Ŋkuɖodzia',
      'reminderActiveTitle': 'Ŋkuɖodzia Le Dɔ Wɔm',
      'reminderActiveBody':
      'Mèɖo dzesi be yeno atikea haɖeke o.\n\nÈdi be yeatɔ ŋkuɖodzia?',
      'cancel': 'Tsi',
      'medicationReminder': 'Atike Ŋkuɖodzi',
      'noImageAvailable': 'Nɔnɔmetata aɖeke meli na atike sia o',
      'doseMarkedTaken': 'Wode dzesi be woano atikea ✓',
      'failedToMarkDose': 'Mete ŋu wɔ dɔ o. Gadze edzi.',
      'notDueSnackbar': 'Ɣeyiɣia mede haɖeke o. Anɔ eteƒe le {time}.',
      'ttsReminderMessage':
      'Ɣeyiɣi de be nàno {name}. Dosage: {dosage}. Meɖe kuku no atikea fifia.',
      'allDoneTitle': 'Èwu nu egbe!',
      'allDoneBody': 'Èno wò atike {count} katã. Dɔ nyui!',
      'nothingScheduled': 'Naneke meli si woɖo ɖi na egbe o',
      'nothingScheduledBody':
      'Ne èdo atike siwo woɖo ɖi ɖe, atike siwo nàno gbesiagbe la ado go le afii.',
      'addMedication': 'Tsɔ Atike Kpe Ɖe Eŋu',
      'couldNotLoadSchedule': 'Mete ŋu hea ɖoɖoa o',
      'retry': 'Gadze Edzi',
    },
  };

  String _raw(String key) {
    final lang = locale.languageCode;
    return _values[lang]?[key] ?? _values['en']![key] ?? key;
  }

  /// Look up [key] for the current locale and substitute any `{param}`
  /// placeholders, e.g. `t('availableAt', {'time': '8:00 AM'})`.
  String t(String key, [Map<String, String>? params]) {
    var s = _raw(key);
    params?.forEach((k, v) {
      s = s.replaceAll('{$k}', v);
    });
    return s;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async => AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}