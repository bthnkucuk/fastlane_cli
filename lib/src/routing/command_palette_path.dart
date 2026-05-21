import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import 'coordinator.dart';
import 'routes/palette_route.dart';

/// Compact-always palette path. Mirrors the state shape of `MiniPlayerPath`:
/// the textfield is always rendered (compact mode), and `expanded` toggles
/// the suggestion list above it. `pop` minimizes first instead of unwinding
/// the stack — only a second pop actually clears the route.
class CommandPalettePath extends StackPath<PaletteRoute>
    with StackMutatable<PaletteRoute>, StackNavigatable<PaletteRoute>
    implements ChangeNotifier {
  CommandPalettePath._(super.stack, {super.debugLabel, super.coordinator});

  factory CommandPalettePath.createWith({
    required FastlaneCliCoordinator coordinator,
    required String label,
  }) => CommandPalettePath._(
    <PaletteRoute>[],
    debugLabel: label,
    coordinator: coordinator,
  );

  static const key = PathKey('CommandPalettePath');

  @override
  PathKey get pathKey => key;

  bool _expanded = false;
  bool get expanded => _expanded;

  @override
  PaletteRoute? get activeRoute => stack.lastOrNull;

  void expand() {
    if (stack.isEmpty) {
      // Don't await — push's future completes when the route is popped.
      // We just want the route on the stack so the path's builder shows it.
      unawaited(push(CommandPaletteRoute()));
    }
    if (!_expanded) {
      _expanded = true;
      notifyListeners();
    }
  }

  void minimize() {
    if (!_expanded) return;
    _expanded = false;
    notifyListeners();
  }

  void toggle() {
    if (_expanded) {
      minimize();
    } else {
      expand();
    }
  }

  @override
  Future<void> activateRoute(PaletteRoute route) async {
    final i = stack.indexOf(route);
    if (i == -1) {
      await push(route);
    } else {
      _expanded = true;
      notifyListeners();
    }
  }

  @override
  Future<void> navigate(PaletteRoute route) async {
    final i = stack.indexOf(route);
    if (i == -1) {
      await push(route);
      return;
    }
    _expanded = true;
    notifyListeners();
  }

  @override
  Future<R?> push<R extends Object>(PaletteRoute element) async {
    _expanded = true;
    final result = super.push<R>(element);
    notifyListeners();
    return result;
  }

  @override
  Future<bool?> pop([Object? result]) async {
    if (_expanded) {
      _expanded = false;
      notifyListeners();
      return true;
    }
    return super.pop(result);
  }

  @override
  void reset() {
    clear();
    _expanded = false;
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
