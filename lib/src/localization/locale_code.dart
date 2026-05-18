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
