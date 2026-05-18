import 'package:fastlane_cli/fastlane_cli.dart';
import 'package:fastlane_cli/src/services/command_execution_service.dart';
import 'package:fastlane_cli/src/services/guide_registry.dart';
import 'package:test/test.dart';

import 'support/profile_factory.dart';

FastlaneCliCoordinator buildCoordinator() {
  final profile = createTestProfile(
    appRootPath: '/tmp/fastlane_cli_coordinator_test',
    categories: <CliCategory>[
      makeCategory(id: 'android', actionIds: <String>['a1']),
      makeCategory(id: 'ios', actionIds: <String>['i1']),
      makeCategory(id: 'general', actionIds: <String>[]),
    ],
    actions: <CliAction>[
      makeFastlaneAction(id: 'a1', categoryId: 'android', lane: 'lane_a'),
      makeFastlaneAction(id: 'i1', categoryId: 'ios', lane: 'lane_i'),
    ],
    shortcuts: const <String>['a1'],
  );
  final environment = FastlaneCliEnvironment(
    profile: profile,
    initialLocale: LocaleCode.en,
    dryRun: false,
    commandBuilder: const CommandBuilder(),
    executionService: const ProcessCommandExecutionService(),
    preflightValidator: const PreflightValidator(),
    guideRegistry: const GuideRegistry(),
  );
  return FastlaneCliCoordinator(environment: environment);
}

void main() {
  group('parseRouteFromUri', () {
    test('empty path → HomeRoute', () {
      final c = buildCoordinator();
      expect(c.parseRouteFromUri(Uri(path: '/')), isA<HomeRoute>());
    });

    test('/android → AndroidCategoryRoute', () {
      final c = buildCoordinator();
      expect(
        c.parseRouteFromUri(Uri(path: '/android')),
        isA<AndroidCategoryRoute>(),
      );
    });

    test('/run/<id> round-trips', () {
      final c = buildCoordinator();
      final route = c.parseRouteFromUri(Uri(path: '/run/a1')) as RunRoute;
      expect(route.actionId, 'a1');
      expect(route.toUri().toString(), '/run/a1');
    });

    test('/guides/topic carries action query parameter', () {
      final c = buildCoordinator();
      final route = c.parseRouteFromUri(
        Uri(path: '/guides/android_metadata', queryParameters: {'action': 'a1'}),
      ) as GuideRoute;
      expect(route.topicId, 'android_metadata');
      expect(route.retryActionId, 'a1');
    });

    test('unknown segment → HomeRoute fallback', () {
      final c = buildCoordinator();
      expect(c.parseRouteFromUri(Uri(path: '/nope')), isA<HomeRoute>());
    });
  });

  group('RunTabsPath', () {
    test('openRun deduplicates by actionId', () async {
      final c = buildCoordinator();
      c.openRun('a1');
      await pumpEventQueue();
      c.openRun('a1');
      await pumpEventQueue();
      expect(c.runTabsPath.stack.length, 1);
      expect(c.runTabsPath.activeRoute?.actionId, 'a1');
    });

    test('openRun pushes second tab and focuses it', () async {
      final c = buildCoordinator();
      c.openRun('a1');
      await pumpEventQueue();
      c.openRun('i1');
      await pumpEventQueue();
      expect(c.runTabsPath.stack.length, 2);
      expect(c.runTabsPath.activeRoute?.actionId, 'i1');
    });

    test('closeRun on middle tab keeps activeIndex valid', () async {
      final c = buildCoordinator();
      c.openRun('a1');
      await pumpEventQueue();
      c.openRun('i1');
      await pumpEventQueue();
      final first = c.runTabsPath.stack.first;
      c.closeRun(first);
      expect(c.runTabsPath.stack.length, 1);
      expect(c.runTabsPath.activeRoute?.actionId, 'i1');
    });

    test('closing the last tab leaves activeIndex null', () async {
      final c = buildCoordinator();
      c.openRun('a1');
      await pumpEventQueue();
      c.closeRun(c.runTabsPath.stack.first);
      expect(c.runTabsPath.activeRoute, isNull);
      expect(c.runTabsPath.activeIndex, isNull);
    });

    test('deactivateRunTabs clears active without removing tabs', () async {
      final c = buildCoordinator();
      c.openRun('a1');
      await pumpEventQueue();
      c.deactivateRunTabs();
      expect(c.runTabsPath.activeRoute, isNull);
      expect(c.runTabsPath.stack.length, 1);
    });
  });

  group('CommandPalettePath', () {
    test('expand on empty stack pushes a CommandPaletteRoute', () async {
      final c = buildCoordinator();
      c.palettePath.expand();
      // push() is async — give the microtask queue a chance to run it.
      await Future<void>.value();
      expect(c.palettePath.expanded, isTrue);
      expect(c.palettePath.activeRoute, isA<CommandPaletteRoute>());
    });

    test('first pop minimizes; second pop clears the route', () async {
      final c = buildCoordinator();
      c.palettePath.expand();
      await Future<void>.value();
      final firstPop = await c.palettePath.pop();
      expect(firstPop, isTrue);
      expect(c.palettePath.expanded, isFalse);
      expect(c.palettePath.stack.length, 1);

      final secondPop = await c.palettePath.pop();
      expect(secondPop, isTrue);
      expect(c.palettePath.stack, isEmpty);
    });

    test('toggle alternates expanded state', () async {
      final c = buildCoordinator();
      c.palettePath.toggle();
      await Future<void>.value();
      expect(c.palettePath.expanded, isTrue);
      c.palettePath.toggle();
      expect(c.palettePath.expanded, isFalse);
    });
  });

  group('overlayPath', () {
    test('push QuickActionsRoute then pop clears it', () async {
      final c = buildCoordinator();
      // Don't await push — its future resolves when the route is popped.
      // ignore: unawaited_futures
      c.overlayPath.push(QuickActionsRoute());
      await Future<void>.value();
      expect(c.overlayPath.activeRoute, isA<QuickActionsRoute>());
      await c.overlayPath.pop();
      expect(c.overlayPath.activeRoute, isNull);
    });
  });

  group('requestRun confirmation gating', () {
    test(
        'requestRun always pushes ConfirmDialogRoute and does NOT open the '
        'run tab on its own', () async {
      final c = buildCoordinator();
      c.requestRun('a1');
      await pumpEventQueue();
      expect(c.overlayPath.activeRoute, isA<ConfirmDialogRoute>());
      expect(c.runTabsPath.stack, isEmpty);
    });

    test('cancelling the dialog leaves no run tab', () async {
      final c = buildCoordinator();
      c.requestRun('a1');
      await pumpEventQueue();
      await c.overlayPath.pop();
      expect(c.overlayPath.activeRoute, isNull);
      expect(c.runTabsPath.stack, isEmpty);
    });

    test('confirming the dialog opens the run tab', () async {
      final c = buildCoordinator();
      c.requestRun('a1');
      await pumpEventQueue();
      final dialog = c.overlayPath.activeRoute as ConfirmDialogRoute;
      await c.overlayPath.pop();
      dialog.onConfirm();
      await pumpEventQueue();
      expect(c.runTabsPath.stack.length, 1);
      expect(c.runTabsPath.activeRoute?.actionId, 'a1');
    });
  });

  group('confirmQuit', () {
    test('pushes a ConfirmDialogRoute on overlayPath', () async {
      final c = buildCoordinator();
      c.confirmQuit();
      await pumpEventQueue();
      expect(c.overlayPath.activeRoute, isA<ConfirmDialogRoute>());
    });
  });
}

