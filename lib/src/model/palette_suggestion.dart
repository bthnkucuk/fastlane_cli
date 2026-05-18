enum PaletteSuggestionType { page, action, guide, command }

class PaletteSuggestion {
  const PaletteSuggestion({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.path,
    this.actionId,
    this.commandId,
  });

  final PaletteSuggestionType type;
  final String id;
  final String title;
  final String subtitle;
  final String? path;
  final String? actionId;
  final String? commandId;
}
