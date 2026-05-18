import 'package:nocterm/nocterm.dart' show Container, shutdownApp;
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import '../localization/app_texts.dart';
import '../model/palette_suggestion.dart';
import 'app_route.dart';
import 'command_palette_path.dart';
import 'environment.dart';
import 'run_session_controller.dart';
import 'run_tabs_path.dart';
import 'routes/category_routes.dart';
import 'routes/confirm_dialog_route.dart';
import 'routes/guide_route.dart';
import 'routes/home_route.dart';
import 'routes/palette_route.dart';
import 'routes/quick_actions_route.dart';
import 'routes/run_route.dart';
import 'shell_layout.dart';

class FastlaneCliCoordinator extends Coordinator<AppRoute> {
  FastlaneCliCoordinator({required this.environment, super.initialRoutePath});

  final FastlaneCliEnvironment environment;

  late final IndexedStackPath<AppRoute> topTabsPath = () {
    final path = IndexedStackPath.createWith(
      coordinator: this,
      label: 'top-tabs',
      <AppRoute>[
        HomeRoute(),
        AndroidCategoryRoute(),
        IosCategoryRoute(),
        GeneralCategoryRoute(),
        GuideRoute(topicId: 'android_metadata'),
      ],
    )..bindLayout(ShellLayout.new);
    return path;
  }();

  late final RunTabsPath runTabsPath =
      RunTabsPath.createWith(coordinator: this, label: 'run-tabs');

  late final CommandPalettePath palettePath =
      CommandPalettePath.createWith(coordinator: this, label: 'palette');

  late final NavigationPath<AppRoute> overlayPath =
      NavigationPath.createWith(coordinator: this, label: 'overlay');

  @override
  List<StackPath> get paths => <StackPath>[
        ...super.paths,
        topTabsPath,
        runTabsPath,
        palettePath,
        overlayPath,
      ];

  @override
  void defineLayout() {
    defineLayoutBuilder(
      RunTabsPath.key,
      (coordinator, path, layout) {
        // Run-tab content is composed by ShellLayout — this builder is only
        // invoked if a route's `layout` resolves to RunTabsPath directly,
        // which we never do.
        return Container();
      },
    );
    defineLayoutBuilder(
      CommandPalettePath.key,
      (coordinator, path, layout) {
        // Same — ShellLayout owns the palette UI placement.
        return Container();
      },
    );
  }

  @override
  AppRoute parseRouteFromUri(Uri uri) => switch (uri.pathSegments) {
        [] => HomeRoute(),
        ['android'] => AndroidCategoryRoute(),
        ['ios'] => IosCategoryRoute(),
        ['general'] => GeneralCategoryRoute(),
        ['guides', final topic] => GuideRoute(
            topicId: topic,
            retryActionId: uri.queryParameters['action'],
          ),
        ['run', final actionId] => RunRoute(
            actionId: actionId,
            controller: RunSessionController(
              actionId: actionId,
              environment: environment,
            ),
          ),
        ['palette'] => CommandPaletteRoute(),
        ['quick-actions'] => QuickActionsRoute(),
        _ => HomeRoute(),
      };

  /// Smart entry point for running an action: always show a Y/N
  /// confirmation dialog before opening a run tab. The run tab is *only*
  /// opened after the user confirms — cancelling never pollutes the
  /// run-tab strip.
  void requestRun(String actionId) {
    final action = environment.profile.actionsById[actionId];
    final texts = AppTexts(environment.locale);
    final title = action?.titleFor(environment.locale) ?? actionId;
    // ignore: unawaited_futures
    overlayPath.push(
      ConfirmDialogRoute(
        title: texts.runConfirmTitle,
        message: texts.runConfirmMessage(title),
        approveLabel: texts.runConfirmApprove,
        cancelLabel: texts.runConfirmCancel,
        hint: texts.runConfirmHint,
        onConfirm: () => _openAndStart(actionId),
      ),
    );
  }

  /// Push a confirmation dialog and shut the app down on approval.
  void confirmQuit() {
    final texts = AppTexts(environment.locale);
    // ignore: unawaited_futures
    overlayPath.push(
      ConfirmDialogRoute(
        title: texts.quitConfirmTitle,
        message: texts.quitConfirmMessage,
        approveLabel: texts.runConfirmApprove,
        cancelLabel: texts.runConfirmCancel,
        onConfirm: shutdownApp,
      ),
    );
  }

  /// Focus an existing run tab if open; otherwise open a new one and start
  /// the action. Used post-confirmation by [requestRun] and by retry from
  /// inside an open run tab.
  void _openAndStart(String actionId) {
    final existing = _findRunRoute(actionId);
    if (existing != null) {
      runTabsPath.activateRoute(existing);
      // ignore: unawaited_futures
      existing.controller.run(confirmed: true);
      return;
    }
    final route = RunRoute(
      actionId: actionId,
      controller: RunSessionController(
        actionId: actionId,
        environment: environment,
      ),
    );
    // ignore: unawaited_futures
    runTabsPath.push(route);
    // The controller starts running on its own when the route's view mounts;
    // see _RunView.initState.
  }

  /// Open or focus a run tab without auto-starting (used by deep links such
  /// as `/run/<id>` and by the URI parser).
  void openRun(String actionId) {
    final existing = _findRunRoute(actionId);
    if (existing != null) {
      runTabsPath.activateRoute(existing);
      return;
    }
    final route = RunRoute(
      actionId: actionId,
      controller: RunSessionController(
        actionId: actionId,
        environment: environment,
      ),
    );
    runTabsPath.push(route);
  }


  /// Close a run tab and dispose its controller.
  void closeRun(RunRoute route) {
    runTabsPath.remove(route, discard: true);
  }

  /// Clear run-tab active selection so the shell falls through to the
  /// top-tab content (without closing any open run tabs).
  void deactivateRunTabs() => runTabsPath.deactivate();

  RunRoute? _findRunRoute(String actionId) {
    for (final route in runTabsPath.stack) {
      if (route.actionId == actionId) return route;
    }
    return null;
  }

  /// Dispatch a palette suggestion: navigate, open run tab, or run a command.
  void executePaletteSuggestion(PaletteSuggestion suggestion) {
    if (suggestion.commandId != null) {
      _executeCommand(suggestion.commandId!);
      return;
    }
    if (suggestion.actionId != null) {
      requestRun(suggestion.actionId!);
      return;
    }
    if (suggestion.path != null) {
      final route = parseRouteFromUri(Uri(path: suggestion.path));
      navigate(route);
    }
  }

  void _executeCommand(String commandId) {
    switch (commandId) {
      case 'quit':
        // Caller is expected to invoke shutdownApp() via key handler.
        // Routes themselves cannot terminate the runtime cleanly.
        break;
    }
  }
}
