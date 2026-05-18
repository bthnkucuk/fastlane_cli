import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import 'coordinator.dart';
import 'routes/run_route.dart';

/// Chrome-style dynamic tab path for run sessions.
///
/// Modeled on `dynamic_tab_zenrouter`'s `TabsPath`: `navigate` focuses an
/// existing tab (by [RouteUnique.props] equality) or pushes a new one;
/// `activeIndex` is nullable so a null state means "no run tab active —
/// fall through to whatever the top-tab path is showing".
class RunTabsPath extends StackPath<RunRoute>
    with StackMutatable<RunRoute>, StackNavigatable<RunRoute>
    implements ChangeNotifier {
  RunTabsPath._(super.stack, {super.debugLabel, super.coordinator});

  factory RunTabsPath.createWith({
    required FastlaneCliCoordinator coordinator,
    required String label,
    List<RunRoute>? stack,
  }) => RunTabsPath._(stack ?? <RunRoute>[], debugLabel: label, coordinator: coordinator);

  static const key = PathKey('RunTabsPath');

  @override
  PathKey get pathKey => key;

  int? _activeIndex;
  int? get activeIndex => _activeIndex;

  /// Clear the active selection so the shell falls through to the top-tab
  /// content (without removing any open run tabs).
  void deactivate() {
    if (_activeIndex == null) return;
    _activeIndex = null;
    notifyListeners();
  }

  @override
  RunRoute? get activeRoute {
    final i = _activeIndex;
    if (i == null || i < 0 || i >= stack.length) return null;
    return stack[i];
  }

  @override
  Future<void> activateRoute(RunRoute route) async {
    final i = stack.indexOf(route);
    if (i == -1) {
      await push(route);
      return;
    }
    if (_activeIndex == i) return;
    _activeIndex = i;
    notifyListeners();
  }

  @override
  Future<void> navigate(RunRoute route) async {
    final i = stack.indexOf(route);
    if (i != -1) {
      // Already in the stack — focus it and update its state.
      final existing = stack[i];
      existing.onUpdate(route);
      if (!existing.deepEquals(route)) {
        route.onDiscard();
      }
      _activeIndex = i;
      notifyListeners();
      return;
    }
    await push(route);
  }

  @override
  Future<R?> push<R extends Object>(RunRoute element) {
    // super.push adds the route to the stack asynchronously (after a redirect
    // resolution microtask). Use a one-shot listener to focus the new route
    // once it actually lands.
    late VoidCallback listener;
    listener = () {
      final idx = stack.indexOf(element);
      if (idx == -1) return;
      _activeIndex = idx;
      removeListener(listener);
      notifyListeners();
    };
    addListener(listener);
    return super.push<R>(element);
  }

  @override
  Future<bool?> pop([Object? result]) async {
    final beforeLength = stack.length;
    final popped = await super.pop(result);
    if (popped == true) {
      if (stack.isEmpty) {
        _activeIndex = null;
      } else if (_activeIndex == beforeLength - 1) {
        _activeIndex = stack.length - 1;
      }
      notifyListeners();
    }
    return popped;
  }

  @override
  void remove(RunRoute element, {bool discard = true}) {
    final removedIndex = stack.indexOf(element);
    if (removedIndex == -1) return;
    if (discard) {
      element.controller.dispose();
    }
    super.remove(element, discard: discard);
    if (stack.isEmpty) {
      _activeIndex = null;
    } else if (_activeIndex == null) {
      // no-op
    } else if (removedIndex < _activeIndex!) {
      _activeIndex = _activeIndex! - 1;
    } else if (removedIndex == _activeIndex!) {
      _activeIndex = removedIndex < stack.length ? removedIndex : stack.length - 1;
    }
    notifyListeners();
  }

  @override
  void reset() {
    for (final route in stack) {
      route.controller.dispose();
    }
    clear();
    _activeIndex = null;
    notifyListeners();
  }

  // --- ChangeNotifier proxy --------------------------------------------------
  final List<VoidCallback> _listeners = <VoidCallback>[];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  @override
  void dispose() {
    _listeners.clear();
    super.dispose();
  }
}
