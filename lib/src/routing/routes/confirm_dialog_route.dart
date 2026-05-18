import 'package:nocterm/nocterm.dart';

import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';

final class ConfirmDialogRoute extends AppRoute {
  ConfirmDialogRoute({
    required this.title,
    required this.message,
    required this.approveLabel,
    required this.cancelLabel,
    this.hint,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String approveLabel;
  final String cancelLabel;
  final String? hint;
  final VoidCallback onConfirm;

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(path: '/confirm');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _ConfirmDialogView(coordinator: c, route: this);
  }
}

class _ConfirmDialogView extends StatefulComponent {
  const _ConfirmDialogView({required this.coordinator, required this.route});

  final FastlaneCliCoordinator coordinator;
  final ConfirmDialogRoute route;

  @override
  State<_ConfirmDialogView> createState() => _ConfirmDialogViewState();
}

class _ConfirmDialogViewState extends State<_ConfirmDialogView> {
  _ConfirmSelection _selection = _ConfirmSelection.confirm;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focusable(
      focused: true,
      onKeyEvent: _onKeyEvent,
      child: Stack(
        children: <Component>[
          ModalBarrier(
            color: Colors.black.withOpacity(0.42),
            dismissible: false,
            obscure: false,
          ),
          Center(
            child: Container(
              width: 72,
              decoration: BoxDecoration(
                color: theme.surface,
                border: BoxBorder.all(color: theme.warning),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .start,
                children: <Component>[
                  Text(
                    component.route.title,
                    style: TextStyle(
                      color: theme.warning,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(component.route.message),
                  if (component.route.hint != null) ...<Component>[
                    const SizedBox(height: 1),
                    Text(component.route.hint!,
                        style: TextStyle(color: theme.secondary)),
                  ],
                  const SizedBox(height: 1),
                  Row(
                    children: <Component>[
                      _button(
                        theme: theme,
                        label: component.route.approveLabel,
                        selected: _selection == _ConfirmSelection.confirm,
                        onHover: () => setState(
                            () => _selection = _ConfirmSelection.confirm),
                        onTap: _confirm,
                      ),
                      const SizedBox(width: 1),
                      _button(
                        theme: theme,
                        label: component.route.cancelLabel,
                        selected: _selection == _ConfirmSelection.cancel,
                        onHover: () => setState(
                            () => _selection = _ConfirmSelection.cancel),
                        onTap: _cancel,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _onKeyEvent(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.keyY) {
      _confirm();
      return true;
    }
    if (event.logicalKey == LogicalKey.keyN ||
        event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.backspace) {
      _cancel();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowLeft ||
        event.logicalKey == LogicalKey.arrowUp) {
      setState(() => _selection = _ConfirmSelection.confirm);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowRight ||
        event.logicalKey == LogicalKey.arrowDown) {
      setState(() => _selection = _ConfirmSelection.cancel);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      if (_selection == _ConfirmSelection.cancel) {
        _cancel();
      } else {
        _confirm();
      }
      return true;
    }
    return false;
  }

  void _confirm() {
    final cb = component.route.onConfirm;
    component.coordinator.overlayPath.pop();
    cb();
  }

  void _cancel() {
    component.coordinator.overlayPath.pop();
  }

  Component _button({
    required TuiThemeData theme,
    required String label,
    required bool selected,
    required VoidCallback onHover,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
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
      ),
    );
  }
}

enum _ConfirmSelection { confirm, cancel }
