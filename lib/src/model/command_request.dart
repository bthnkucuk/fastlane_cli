class CommandRequest {
  const CommandRequest({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;

  String get displayCommand => '$executable ${arguments.join(' ')}'.trim();
}
