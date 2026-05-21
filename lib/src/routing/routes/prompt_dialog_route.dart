import 'package:nocterm/nocterm.dart';

import '../../localization/i18n/strings.g.dart';
import '../../services/run_prompt_parser.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../run_session_controller.dart';
import '../shell_layout.dart';

/// Modal route for interactive child-process prompts (2FA codes,
/// trust-this-computer, y/n, account picker, free-form fallback).
///
/// Mirrors the chrome of `ConfirmDialogRoute` (FadeModalBarrier + bordered
/// panel) but adds either a TextField (for codes / free-form / numeric
/// picker) or two buttons (for y/n style answers). On submit the input is
/// validated by the [RunPrompt.validator]; on success the value is forwarded
/// to the child via [RunSessionController.submitPromptResponse]. Esc / N
/// dismisses the dialog, which relays SIGINT to the child (implying "stop
/// this lane") — see [RunSessionController.dismissPrompt].
final class PromptDialogRoute extends AppRoute {
  PromptDialogRoute({required this.controller});

  final RunSessionController controller;

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(path: '/prompt/${controller.actionId}');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _PromptDialogView(coordinator: c, route: this);
  }
}

class _PromptDialogView extends StatefulComponent {
  const _PromptDialogView({required this.coordinator, required this.route});

  final FastlaneCliCoordinator coordinator;
  final PromptDialogRoute route;

  @override
  State<_PromptDialogView> createState() => _PromptDialogViewState();
}

class _PromptDialogViewState extends State<_PromptDialogView> {
  final TextEditingController _textController = TextEditingController();
  bool _busy = false;

  RunSessionController get _controller => component.route.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSessionChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    // If the controller cleared the prompt out from under us (e.g. the child
    // exited before the user answered), close ourselves. We compare by
    // `activePrompt == null` rather than identity because the controller
    // re-emits an updated prompt instance when a validator error needs to
    // be attached, and we want to stay open in that case.
    if (_controller.session.activePrompt == null) {
      _maybePop();
      return;
    }
    setState(() {});
  }

  void _maybePop() {
    final overlay = component.coordinator.overlayPath;
    if (overlay.activeRoute == component.route) {
      overlay.pop();
    }
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final prompt = _controller.session.activePrompt;
    if (prompt == null) {
      // Race: rebuild happened after the prompt was cleared. Return an empty
      // overlay; _onSessionChanged will pop us on the next listener tick.
      return const SizedBox.shrink();
    }
    final title = _titleFor(prompt.kind);
    final isYesNo = prompt.kind == RunPromptKind.yesNo ||
        prompt.kind == RunPromptKind.trustComputer;

    return Focusable(
      focused: true,
      onKeyEvent: (e) => _onKeyEvent(e, prompt, isYesNo: isYesNo),
      child: Stack(
        children: <Component>[
          FadeModalBarrier(
            color: Colors.black.withOpacity(0.42),
            dismissible: false,
            obscure: false,
          ),
          Center(
            child: Container(
              width: 72,
              decoration: BoxDecoration(
                color: theme.surface,
                border: BoxBorder.all(
                  color: theme.primary,
                  style: BoxBorderStyle.rounded,
                ),
                title: BorderTitle(
                  text: title,
                  style: TextStyle(
                    color: theme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: <Component>[
                  Text(prompt.label),
                  if (prompt.hintText != null) ...<Component>[
                    const SizedBox(height: 1),
                    Text(
                      prompt.hintText!,
                      style: TextStyle(color: theme.secondary),
                    ),
                  ],
                  const SizedBox(height: 1),
                  if (isYesNo)
                    _yesNoButtons(theme: theme, prompt: prompt)
                  else
                    _textInput(theme: theme, prompt: prompt),
                  if (prompt.validationError != null) ...<Component>[
                    const SizedBox(height: 1),
                    Text(
                      prompt.validationError!,
                      style: TextStyle(color: theme.error),
                    ),
                  ],
                  const SizedBox(height: 1),
                  Text(
                    isYesNo
                        ? 'Y/N · Esc: ${t.prompt.cancel}'
                        : 'Enter: ${t.prompt.submit} · Esc: ${t.prompt.cancel}',
                    style: TextStyle(color: theme.secondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Component _textInput({
    required TuiThemeData theme,
    required RunPrompt prompt,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(color: theme.outline),
        color: theme.background,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: TextField(
        controller: _textController,
        focused: true,
        placeholder: prompt.hintText ?? '',
        onChanged: (_) {},
        onSubmitted: (value) => _submit(prompt, value),
        onFocusChange: (_) {},
      ),
    );
  }

  Component _yesNoButtons({
    required TuiThemeData theme,
    required RunPrompt prompt,
  }) {
    return Row(
      children: <Component>[
        _button(
          theme: theme,
          label: t.prompt.yes,
          selected: true,
          onTap: () => _submit(prompt, 'y'),
        ),
        const SizedBox(width: 1),
        _button(
          theme: theme,
          label: t.prompt.no,
          selected: false,
          onTap: () => _submit(prompt, 'n'),
        ),
      ],
    );
  }

  Component _button({
    required TuiThemeData theme,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: selected ? theme.primary : null),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.onPrimary : theme.onSurface,
          ),
        ),
      ),
    );
  }

  String _titleFor(RunPromptKind kind) {
    switch (kind) {
      case RunPromptKind.twoFactorCode:
        return t.prompt.twoFactorTitle;
      case RunPromptKind.yesNo:
        return t.prompt.yesNoTitle;
      case RunPromptKind.trustComputer:
        return t.prompt.trustComputerTitle;
      case RunPromptKind.chooseIndex:
        return t.prompt.chooseIndexTitle;
      case RunPromptKind.freeForm:
        return t.prompt.freeFormTitle;
    }
  }

  bool _onKeyEvent(KeyboardEvent event, RunPrompt prompt, {required bool isYesNo}) {
    if (event.logicalKey == LogicalKey.escape) {
      _controller.dismissPrompt();
      _maybePop();
      return true;
    }
    if (isYesNo) {
      if (event.logicalKey == LogicalKey.keyY) {
        _submit(prompt, 'y');
        return true;
      }
      if (event.logicalKey == LogicalKey.keyN) {
        _submit(prompt, 'n');
        return true;
      }
    }
    if (event.logicalKey == LogicalKey.enter && !isYesNo) {
      _submit(prompt, _textController.text);
      return true;
    }
    return false;
  }

  Future<void> _submit(RunPrompt prompt, String value) async {
    if (_busy) return;
    _busy = true;
    final error = await _controller.submitPromptResponse(value);
    _busy = false;
    if (error == null) {
      _textController.clear();
      _maybePop();
    } else if (mounted) {
      setState(() {});
    }
  }
}
