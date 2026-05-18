import 'i18n/strings.g.dart';

enum LocaleCode {
  tr,
  en;

  static LocaleCode parse(String? raw, {LocaleCode fallback = LocaleCode.tr}) {
    final normalized = raw?.trim().toLowerCase();
    return switch (normalized) {
      'tr' => LocaleCode.tr,
      'en' => LocaleCode.en,
      _ => fallback,
    };
  }
}

/// Bridges the public [LocaleCode] enum (referenced widely and by the profile
/// YAML model) with slang's generated [AppLocale] enum.
extension LocaleCodeToAppLocale on LocaleCode {
  AppLocale toAppLocale() => switch (this) {
    LocaleCode.tr => AppLocale.tr,
    LocaleCode.en => AppLocale.en,
  };
}

extension AppLocaleToLocaleCode on AppLocale {
  LocaleCode toLocaleCode() => switch (this) {
    AppLocale.tr => LocaleCode.tr,
    AppLocale.en => LocaleCode.en,
  };
}
