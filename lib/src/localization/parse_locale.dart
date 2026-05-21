import 'i18n/strings.g.dart';

/// Parses a raw locale string (e.g. `tr`, `EN`, `en-US`) into an [AppLocale].
///
/// Returns [fallback] when [raw] is `null`, empty, or doesn't match any
/// generated locale. Slang's [AppLocaleUtils.parse] silently resolves unknown
/// input to the slang base locale (and is case-sensitive), so this wrapper
/// normalizes case and detects "no real match" to preserve the previous
/// "unknown -> caller-supplied fallback" contract the YAML profile loader
/// relies on.
AppLocale parseLocale(String? raw, {AppLocale fallback = AppLocale.tr}) {
  final normalized = raw?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return fallback;
  }
  final parsed = AppLocaleUtils.parse(normalized);
  // Slang's parser silently returns the base locale on unknown input;
  // distinguish a real match (languageCode equals our normalized input,
  // possibly with a regional suffix) from a silent fallback.
  final matched = normalized == parsed.languageCode ||
      normalized.startsWith('${parsed.languageCode}-') ||
      normalized.startsWith('${parsed.languageCode}_');
  return matched ? parsed : fallback;
}
