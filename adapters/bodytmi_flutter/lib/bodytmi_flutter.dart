/// Flutter presentation adapter over the pure Dart BodyTMI locale service.
/// Flutter types stay here; domain, application, storage and the CLI never
/// import this package.
library;

import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:flutter/widgets.dart';

/// Maps Flutter locales and Material conventions onto [PresentationLocale].
final class BodyTmiLocaleAdapter {
  const BodyTmiLocaleAdapter._();

  /// Resolves the app's Flutter [Locale] through the shared service, so the
  /// GUI and CLI apply one fallback policy (exact, language, then `en`).
  static PresentationLocale resolve(Locale locale) =>
      PresentationLocale.resolve(locale.toLanguageTag());

  /// The nearest ambient locale's presentation service.
  static PresentationLocale of(BuildContext context) =>
      resolve(Localizations.localeOf(context));

  /// Material's `firstDayOfWeekIndex` convention: 0 = Sunday ... 6 = Saturday.
  /// The shared service uses ISO numbering (1 = Monday ... 7 = Sunday).
  static int materialFirstDayOfWeekIndex(PresentationLocale locale) =>
      locale.firstWeekday % 7;

  /// Whether the locale's own convention is a 24-hour clock. A platform
  /// `alwaysUse24HourFormat` setting is a separate user preference.
  static bool uses24HourClock(PresentationLocale locale) =>
      locale.info()['hourCycle'] == 'h24';
}
