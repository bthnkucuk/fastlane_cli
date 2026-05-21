class PreflightResult {
  const PreflightResult({
    required this.success,
    this.guideTopic,
    this.errors = const <String>[],
    this.checklist = const <String>[],
  });

  final bool success;
  final String? guideTopic;
  final List<String> errors;
  final List<String> checklist;
}
