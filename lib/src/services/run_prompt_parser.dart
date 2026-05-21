/// Detects interactive prompts that fastlane (or any spawned child process)
/// writes to stdout while waiting on stdin.
///
/// fastlane's interactive paths (2FA codes, "trust this computer", multi-account
/// `Please choose:` menus, generic `[y/n]` confirms) print their prompt to
/// stdout and then block on stdin. The TUI never had stdin wired to the child,
/// so the lane would hang forever. This parser surfaces those prompts so the
/// controller can pop a modal, take the user's answer, and write it back to
/// the child's stdin.
///
/// Pure function: `parse(String line)` returns a [RunPrompt] when the line
/// matches a known pattern, or `null` otherwise. State (e.g. "is there already
/// an unanswered prompt?") is the controller's responsibility, not ours.
library;

/// Kinds of interactive prompts we know how to recognise.
enum RunPromptKind {
  /// Apple two-factor authentication code. Numeric, exact length captured
  /// from the prompt text (commonly 6).
  twoFactorCode,

  /// Generic `(y/n)` / `[Y/n]` / `[y/N]` confirm.
  yesNo,

  /// Apple "Do you want to trust this computer?" prompt — also a y/n answer,
  /// kept as a distinct kind so the modal can use a more descriptive label.
  trustComputer,

  /// Multi-choice menu: "Please choose: 1 - 5". Validator enforces the
  /// captured integer range.
  chooseIndex,

  /// Fallback: free-form question (line ends with `:`). Validator only
  /// requires non-empty. Conservative — only fires when the line is clearly
  /// a question and no other pattern matched.
  freeForm,
}

/// One detected prompt. Immutable. The controller stores it on the
/// [RunSession] until the user answers (or dismisses).
class RunPrompt {
  RunPrompt({
    required this.kind,
    required this.label,
    required this.sourceLine,
    required this.validator,
    this.hintText,
    this.maxLength,
    this.validationError,
  });

  /// What kind of prompt was detected. Drives the modal UI.
  final RunPromptKind kind;

  /// Localized-ready short label describing what the child wants. The UI
  /// usually displays this verbatim as the dialog body.
  final String label;

  /// The original log line that triggered detection — useful for analytics,
  /// debugging, and "Esc dismiss" sigint logs.
  final String sourceLine;

  /// Validator for whatever the user types. Returns an error message when
  /// the input is rejected, or null when it's acceptable.
  final String? Function(String input) validator;

  /// Optional placeholder/hint for the modal's text field.
  final String? hintText;

  /// Optional hard cap on the text field's length (used for 2FA codes).
  final int? maxLength;

  /// Sticky validation error shown inline in the modal. The controller sets
  /// this when [validator] rejects the user's input and re-emits the prompt
  /// so the dialog stays open.
  final String? validationError;

  RunPrompt withValidationError(String? error) => RunPrompt(
        kind: kind,
        label: label,
        sourceLine: sourceLine,
        validator: validator,
        hintText: hintText,
        maxLength: maxLength,
        validationError: error,
      );
}

/// Parses log lines into [RunPrompt]s. Stateless.
class RunPromptParser {
  RunPromptParser({this.localizer = const _DefaultPromptLocalizer()});

  /// Optional indirection so the route controller can inject a slang-backed
  /// localizer. Defaults to plain English labels so the parser is usable from
  /// pure unit tests without booting up slang.
  final PromptLocalizer localizer;

  // 2FA: "Please enter the 6 digit code..." — capture the digit count so the
  // validator can enforce the exact length the child is waiting for.
  static final RegExp _twoFactorCode =
      RegExp(r'Please enter the (\d+) digit code', caseSensitive: false);

  // Apple-specific trust prompt — fires before the y/n parser so we keep the
  // distinct labelling.
  static final RegExp _trustComputer =
      RegExp(r'Do you want to trust this computer', caseSensitive: false);

  // Generic y/n in any of fastlane's common renderings.
  static final RegExp _yesNo = RegExp(r'\((y/n|Y/n|y/N)\)|\[(y/n|Y/n|y/N)\]');

  // "Please choose: 1 - 5" multi-choice picker (account / team selection).
  static final RegExp _chooseIndex =
      RegExp(r'Please choose:?\s*(\d+)\s*-\s*(\d+)', caseSensitive: false);

  // Free-form fallback: a line ending with `:` (after trimming), which is
  // fastlane's house style for "I'm waiting on input". Conservative — we
  // require the trimmed line to be at least 6 chars (avoids matching empty
  // colons in tabular log output).
  static final RegExp _freeForm = RegExp(r'^.{6,}:\s*$');

  /// Returns a [RunPrompt] when [line] looks like a prompt, otherwise null.
  RunPrompt? parse(String line) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return null;

    final twoFa = _twoFactorCode.firstMatch(trimmed);
    if (twoFa != null) {
      final digits = int.tryParse(twoFa.group(1) ?? '6') ?? 6;
      return RunPrompt(
        kind: RunPromptKind.twoFactorCode,
        label: localizer.twoFactorBody(digits),
        hintText: localizer.twoFactorHint(digits),
        sourceLine: line,
        maxLength: digits,
        validator: (input) {
          final v = input.trim();
          if (v.length != digits) {
            return localizer.errorWrongLength(digits);
          }
          if (!RegExp(r'^\d+$').hasMatch(v)) {
            return localizer.errorOnlyDigits();
          }
          return null;
        },
      );
    }

    if (_trustComputer.hasMatch(trimmed)) {
      return RunPrompt(
        kind: RunPromptKind.trustComputer,
        label: localizer.trustComputerBody(),
        sourceLine: line,
        validator: _yesNoValidator,
      );
    }

    if (_yesNo.hasMatch(trimmed)) {
      return RunPrompt(
        kind: RunPromptKind.yesNo,
        label: trimmed,
        sourceLine: line,
        validator: _yesNoValidator,
      );
    }

    final choose = _chooseIndex.firstMatch(trimmed);
    if (choose != null) {
      final lo = int.tryParse(choose.group(1) ?? '');
      final hi = int.tryParse(choose.group(2) ?? '');
      if (lo != null && hi != null && hi >= lo) {
        return RunPrompt(
          kind: RunPromptKind.chooseIndex,
          label: localizer.chooseIndexBody(lo, hi),
          hintText: '$lo-$hi',
          sourceLine: line,
          validator: (input) {
            final parsed = int.tryParse(input.trim());
            if (parsed == null) return localizer.errorOnlyDigits();
            if (parsed < lo || parsed > hi) {
              return localizer.errorOutOfRange(lo, hi);
            }
            return null;
          },
        );
      }
    }

    // Free-form fallback. Only fire when the line is clearly a sentence
    // ending in `:` — not the noisy `[03:26:55]:` timestamp prefix style.
    if (_freeForm.hasMatch(trimmed) &&
        !RegExp(r'^\[\d').hasMatch(trimmed) &&
        !trimmed.contains('passed')) {
      return RunPrompt(
        kind: RunPromptKind.freeForm,
        label: trimmed,
        sourceLine: line,
        validator: (input) => input.trim().isEmpty
            ? localizer.errorRequired()
            : null,
      );
    }

    return null;
  }

  String? _yesNoValidator(String input) {
    final v = input.trim().toLowerCase();
    if (v == 'y' || v == 'yes' || v == 'n' || v == 'no') return null;
    return localizer.errorYesOrNo();
  }
}

/// Indirection point used by [RunPromptParser] so the parser is decoupled
/// from slang. Production code wires in a slang-backed implementation; unit
/// tests use the [_DefaultPromptLocalizer] fallback.
abstract class PromptLocalizer {
  String twoFactorBody(int digits);
  String twoFactorHint(int digits);
  String trustComputerBody();
  String chooseIndexBody(int lo, int hi);
  String errorWrongLength(int digits);
  String errorOnlyDigits();
  String errorYesOrNo();
  String errorOutOfRange(int lo, int hi);
  String errorRequired();
}

class _DefaultPromptLocalizer implements PromptLocalizer {
  const _DefaultPromptLocalizer();

  @override
  String twoFactorBody(int digits) => 'Enter the $digits-digit code';

  @override
  String twoFactorHint(int digits) => '$digits-digit code';

  @override
  String trustComputerBody() => 'Do you want to trust this computer?';

  @override
  String chooseIndexBody(int lo, int hi) =>
      'Please choose a number between $lo and $hi';

  @override
  String errorWrongLength(int digits) => 'Must be $digits digits';

  @override
  String errorOnlyDigits() => 'Digits only';

  @override
  String errorYesOrNo() => 'Type y or n';

  @override
  String errorOutOfRange(int lo, int hi) => 'Must be $lo-$hi';

  @override
  String errorRequired() => 'Required';
}
