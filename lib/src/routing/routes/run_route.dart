import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../../localization/i18n/strings.g.dart';
import '../../localization/run_status_label.dart';
import '../../model/run_session.dart';
import '../../ui/ansi_parsed_log_line.dart';
import '../../ui/components/shell_scaffold.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../run_session_controller.dart';
import '../run_tabs_path.dart';
import '../shell_layout.dart';
import 'guide_route.dart';
import 'home_route.dart';
import 'prompt_dialog_route.dart';

final class RunRoute extends AppRoute with RouteTab {
  RunRoute({required this.actionId, required this.controller});

  final String actionId;
  final RunSessionController controller;

  @override
  List<Object?> get props => [actionId];

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(path: '/run/$actionId');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _RunView(coordinator: c, route: this);
  }

  @override
  Component tabLabel(
    FastlaneCliCoordinator coordinator,
    RunTabsPath path,
    BuildContext context, {
    required bool active,
  }) {
    final theme = TuiTheme.of(context);
    final action = coordinator.environment.profile.actionsById[actionId];
    final label = action?.titleFor(coordinator.environment.locale) ?? actionId;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final session = controller.session;
        final statusColor = switch (session.status) {
          RunStatus.failed => theme.error,
          RunStatus.succeeded || RunStatus.dryRun => theme.success,
          RunStatus.running || RunStatus.validating => theme.warning,
          _ => theme.secondary,
        };
        return Container(
          decoration: BoxDecoration(color: active ? theme.primary : null),
          margin: const EdgeInsets.only(right: 1),
          child: Row(
            children: <Component>[
              GestureDetector(
                onTap: () => coordinator.openRun(actionId),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    '● $label',
                    style: TextStyle(
                      color: active ? theme.onPrimary : statusColor,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => coordinator.closeRun(this),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Text(
                    '×',
                    style: TextStyle(
                      color: active ? theme.onPrimary : theme.secondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RunView extends StatefulComponent {
  const _RunView({required this.coordinator, required this.route});

  final FastlaneCliCoordinator coordinator;
  final RunRoute route;

  @override
  State<_RunView> createState() => _RunViewState();
}

class _RunViewState extends State<_RunView> {
  // AutoScrollController keeps the viewport pinned to the most recent log
  // line as new content streams in. When the user scrolls up,
  // `isAutoScrollEnabled` flips to false and stick disengages; scrolling
  // back to the bottom re-engages it automatically (handled inside the
  // controller's updateMetrics / scrollBy hooks).
  final AutoScrollController _logScrollController = AutoScrollController();
  String? _copyFeedback;
  Timer? _copyFeedbackTimer;
  bool _promptDialogPushed = false;

  RunSessionController get _controller => component.route.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSessionChanged);
    // Auto-start when the tab opens for the first time. The coordinator's
    // requestRun() handles the confirmation dialog before getting here, so
    // the user has already approved any prompts.
    if (_shouldAutoStart(_controller.session)) {
      // ignore: unawaited_futures
      _autoStart();
    }
  }

  Future<void> _autoStart() async {
    final session = await _controller.run(confirmed: true);
    if (!mounted) return;
    if (session.status == RunStatus.blocked && session.guideTopic != null) {
      component.coordinator.replace(
        GuideRoute(
          topicId: session.guideTopic!,
          retryActionId: component.route.actionId,
        ),
      );
    }
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    _controller.removeListener(_onSessionChanged);
    _logScrollController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    _syncPromptDialog();
    setState(() {});
  }

  /// Push (or pop) the interactive prompt dialog in lockstep with the
  /// controller's `activePrompt` field. We track local `_promptDialogPushed`
  /// state because the controller may emit several updates that don't change
  /// the dialog's lifecycle (validator error attached, etc.) and we don't
  /// want to push duplicate overlays.
  void _syncPromptDialog() {
    final prompt = _controller.session.activePrompt;
    if (prompt != null && !_promptDialogPushed) {
      _promptDialogPushed = true;
      // ignore: unawaited_futures
      component.coordinator.overlayPath.push(
        PromptDialogRoute(controller: _controller),
      );
    } else if (prompt == null && _promptDialogPushed) {
      _promptDialogPushed = false;
      // The dialog handles its own pop on session change, but if the prompt
      // was cleared from outside (e.g. process exited), make sure the
      // overlay is gone.
      final overlay = component.coordinator.overlayPath;
      if (overlay.activeRoute is PromptDialogRoute) {
        overlay.pop();
      }
    }
  }

  @override
  Component build(BuildContext context) {
    final env = component.coordinator.environment;
    final action = env.profile.actionsById[component.route.actionId];
    final run = _controller.session;
    final theme = TuiTheme.of(context);

    return Focusable(
      focused:
          !component.coordinator.palettePath.expanded &&
          component.coordinator.overlayPath.activeRoute == null,
      onKeyEvent: _onKeyEvent,
      child: ShellScaffold(
        pageTitle:
            '${t.runTitle}: ${action?.titleFor(env.locale) ?? component.route.actionId}',
        subtitle:
            '${run.status.label}${run.command == null ? '' : ' · ${t.command}: ${run.command}'}',
        body: Column(
          crossAxisAlignment: .start,
          children: <Component>[
            if (run.status == RunStatus.blocked)
              Text(
                t.blockedByGuide,
                style: TextStyle(color: theme.error),
              ),
            if (run.validationErrors.isNotEmpty) ...<Component>[
              const SizedBox(height: 1),
              Text(t.validationFailed),
              for (final item in run.validationErrors) Text('- $item'),
            ],
            const SizedBox(height: 1),
            _buildProgressSection(run: run, theme: theme),
            const SizedBox(height: 1),
            Expanded(
              child: _buildLogConsole(run: run, theme: theme),
            ),
            const SizedBox(height: 1),
            Text('${t.retry} · ${t.back} · ${t.copyOutput}'),
            if (_copyFeedback != null)
              Text(_copyFeedback!, style: TextStyle(color: theme.success)),
          ],
        ),
      ),
    );
  }

  bool _onKeyEvent(KeyboardEvent event) {
    if (_handleLogScrollKey(event)) return true;
    if (_isCopyShortcut(event)) {
      _copyOutput(_controller.session);
      return true;
    }
    if (event.logicalKey == LogicalKey.keyB ||
        event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.backspace) {
      component.coordinator.replace(HomeRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyR ||
        event.logicalKey == LogicalKey.enter) {
      // Retry — go back through the confirmation gate. requestRun pushes
      // the dialog if needed; otherwise it focuses this tab and re-runs.
      component.coordinator.requestRun(component.route.actionId);
      return true;
    }
    return false;
  }

  void _copyOutput(RunSession run) {
    final buf = StringBuffer()
      ..writeln(run.status.label)
      ..writeln('${t.command}: ${run.command ?? '-'}')
      ..writeln('')
      ..writeln(t.logs);
    if (run.logs.isEmpty) {
      buf.writeln('-');
    } else {
      for (final entry in run.logs) {
        buf.writeln(stripAnsiSequences(entry.message));
      }
    }
    ClipboardManager.copy(buf.toString());
    _copyFeedbackTimer?.cancel();
    setState(() => _copyFeedback = t.copiedOutput);
    _copyFeedbackTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _copyFeedback = null);
    });
  }

  bool _handleLogScrollKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.arrowUp) {
      _logScrollController.scrollUp(1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      _logScrollController.scrollDown(1);
      return true;
    }
    if (event.logicalKey == LogicalKey.pageUp) {
      _logScrollController.pageUp();
      return true;
    }
    if (event.logicalKey == LogicalKey.pageDown) {
      _logScrollController.pageDown();
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _logScrollController.scrollToStart();
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _logScrollController.scrollToEnd();
      return true;
    }
    return false;
  }

  bool _isCopyShortcut(KeyboardEvent event) {
    if (event.logicalKey != LogicalKey.keyC) return false;
    if (!event.modifiers.hasAnyModifier) return true;
    return event.isControlPressed &&
        event.isShiftPressed &&
        !event.isAltPressed &&
        !event.isMetaPressed;
  }

  bool _shouldAutoStart(RunSession run) {
    return run.status == RunStatus.idle &&
        run.logs.isEmpty &&
        run.command == null &&
        run.exitCode == null;
  }

  Component _logLine(RunLogEntry entry, TuiThemeData theme) {
    if (!logLineContainsAnsi(entry.message)) {
      return Text(
        entry.message,
        style: TextStyle(
          color: entry.isError ? theme.error : theme.onBackground,
        ),
      );
    }
    return RichText(
      text: ansiLineToSpan(
        entry.message,
        baseStyle: TextStyle(color: theme.onBackground),
      ),
      softWrap: true,
    );
  }

  Component _buildLogConsole({
    required RunSession run,
    required TuiThemeData theme,
  }) {
    final logs = run.logs;
    // BorderTitle threads the existing localized `t.logs` string into
    // the panel chrome — no new string literals introduced here.
    final decoration = BoxDecoration(
      color: theme.background,
      border: BoxBorder.all(
        color: theme.outlineVariant,
        style: BoxBorderStyle.rounded,
      ),
      title: BorderTitle(
        text: t.logs,
        style: TextStyle(color: theme.onSurface),
      ),
    );

    if (logs.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: decoration,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(
          t.waitingLogs,
          style: TextStyle(color: theme.secondary),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: decoration,
      child: Scrollbar(
        controller: _logScrollController,
        thumbVisibility: true,
        child: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: ListView.builder(
              controller: _logScrollController,
              lazy: true,
              itemCount: logs.length,
              itemBuilder: (context, index) => _logLine(logs[index], theme),
            ),
          ),
        ),
      ),
    );
  }

  Component _buildProgressSection({
    required RunSession run,
    required TuiThemeData theme,
  }) {
    final currentFile = run.activeFile;
    // Stay indeterminate until fastlane emits a real, positive progress
    // signal — otherwise the bar would render at 0% for the entire
    // pre-parse window, which reads as "stuck".
    final rawValue = run.progressValue;
    final indeterminate =
        run.progressIndeterminate || rawValue == null || rawValue <= 0;
    final progressValue =
        indeterminate ? null : rawValue.clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: .start,
      children: <Component>[
        Text(t.progress),
        ProgressBar(
          value: progressValue,
          indeterminate: indeterminate,
          showPercentage: !indeterminate,
          borderStyle: ProgressBarBorderStyle.rounded,
          valueColor: indeterminate ? theme.warning : theme.success,
          minHeight: 3,
        ),
        Text(
          '${t.currentFile}: ${currentFile ?? t.waitingLogs}',
          style: TextStyle(color: currentFile == null ? theme.secondary : null),
        ),
      ],
    );
  }
}
