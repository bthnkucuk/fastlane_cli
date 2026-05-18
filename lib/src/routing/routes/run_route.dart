import 'dart:async';

import 'package:nocterm/nocterm.dart';

import '../../localization/app_texts.dart';
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
  final ScrollController _logScrollController = ScrollController();
  String? _copyFeedback;
  Timer? _copyFeedbackTimer;

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
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final env = component.coordinator.environment;
    final texts = AppTexts(env.locale);
    final action = env.profile.actionsById[component.route.actionId];
    final run = _controller.session;
    _autoStickToTail(run);
    final theme = TuiTheme.of(context);

    return Focusable(
      focused:
          !component.coordinator.palettePath.expanded &&
          component.coordinator.overlayPath.activeRoute == null,
      onKeyEvent: _onKeyEvent,
      child: ShellScaffold(
        pageTitle:
            '${texts.runTitle}: ${action?.titleFor(env.locale) ?? component.route.actionId}',
        subtitle:
            '${texts.statusLabel(run.status)}${run.command == null ? '' : ' · ${texts.command}: ${run.command}'}',
        body: Column(
          crossAxisAlignment: .start,
          children: <Component>[
            if (run.status == RunStatus.blocked)
              Text(
                texts.blockedByGuide,
                style: TextStyle(color: theme.error),
              ),
            if (run.validationErrors.isNotEmpty) ...<Component>[
              const SizedBox(height: 1),
              Text(texts.validationFailed),
              for (final item in run.validationErrors) Text('- $item'),
            ],
            const SizedBox(height: 1),
            _buildProgressSection(run: run, texts: texts, theme: theme),
            const SizedBox(height: 1),
            Expanded(
              child: _buildLogConsole(run: run, theme: theme, texts: texts),
            ),
            const SizedBox(height: 1),
            Text('${texts.retry} · ${texts.back} · ${texts.copyOutput}'),
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
      _copyOutput(
        _controller.session,
        AppTexts(component.coordinator.environment.locale),
      );
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

  void _copyOutput(RunSession run, AppTexts texts) {
    final buf = StringBuffer()
      ..writeln(texts.statusLabel(run.status))
      ..writeln('${texts.command}: ${run.command ?? '-'}')
      ..writeln('')
      ..writeln(texts.logs);
    if (run.logs.isEmpty) {
      buf.writeln('-');
    } else {
      for (final entry in run.logs) {
        buf.writeln(stripAnsiSequences(entry.message));
      }
    }
    ClipboardManager.copy(buf.toString());
    _copyFeedbackTimer?.cancel();
    setState(() => _copyFeedback = texts.copiedOutput);
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

  /// Keeps the log viewport pinned to the most-recent entry as logs stream
  /// in. We schedule the `ensureIndexVisible` call after the frame so the
  /// ListView has laid out the new tail item before we ask the controller
  /// to bring it into view.
  void _autoStickToTail(RunSession run) {
    if (run.logs.isEmpty) return;
    final tailIndex = run.logs.length - 1;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _logScrollController.ensureIndexVisible(index: tailIndex);
    });
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
    required AppTexts texts,
  }) {
    final logs = run.logs;
    // BorderTitle threads the existing localized `texts.logs` string into
    // the panel chrome — no new string literals introduced here.
    final decoration = BoxDecoration(
      color: theme.background,
      border: BoxBorder.all(
        color: theme.outlineVariant,
        style: BoxBorderStyle.rounded,
      ),
      title: BorderTitle(
        text: texts.logs,
        style: TextStyle(color: theme.onSurface),
      ),
    );

    if (logs.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: decoration,
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Text(
          texts.waitingLogs,
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
    required AppTexts texts,
    required TuiThemeData theme,
  }) {
    final currentFile = run.activeFile;
    final indeterminate = run.progressIndeterminate;
    final progressValue = indeterminate
        ? null
        : (run.progressValue ?? 0).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: .start,
      children: <Component>[
        Text(texts.progress),
        ProgressBar(
          value: progressValue,
          indeterminate: indeterminate,
          showPercentage: !indeterminate,
          borderStyle: ProgressBarBorderStyle.rounded,
          valueColor: indeterminate ? theme.warning : theme.success,
          minHeight: 3,
        ),
        Text(
          '${texts.currentFile}: ${currentFile ?? texts.waitingLogs}',
          style: TextStyle(color: currentFile == null ? theme.secondary : null),
        ),
      ],
    );
  }
}
