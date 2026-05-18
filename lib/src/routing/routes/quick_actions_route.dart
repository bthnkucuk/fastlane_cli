import 'package:nocterm/nocterm.dart';

import '../../localization/app_texts.dart';
import '../../model/cli_action.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';

final class QuickActionsRoute extends AppRoute {
  QuickActionsRoute();

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(path: '/quick-actions');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _QuickActionsView(coordinator: c);
  }
}

class _QuickActionsView extends StatefulComponent {
  const _QuickActionsView({required this.coordinator});

  final FastlaneCliCoordinator coordinator;

  @override
  State<_QuickActionsView> createState() => _QuickActionsViewState();
}

class _QuickActionsViewState extends State<_QuickActionsView> {
  int _selectedIndex = 0;

  @override
  Component build(BuildContext context) {
    final env = component.coordinator.environment;
    final actions = env.profile.shortcutActions;
    final texts = AppTexts(env.locale);
    final selected = actions.isEmpty
        ? 0
        : _selectedIndex.clamp(0, actions.length - 1);
    final theme = TuiTheme.of(context);

    return Stack(
      children: <Component>[
        Positioned.fill(
          child: GestureDetector(
            onTap: _dismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          top: 2,
          right: 1,
          child: Focusable(
            focused: true,
            onKeyEvent: (event) => _onKeyEvent(event, actions),
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                color: theme.surface,
                border: BoxBorder.all(color: theme.primary),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
              child: Column(
                crossAxisAlignment: .start,
                children: <Component>[
                  Text(
                    texts.shortcuts,
                    style: TextStyle(
                      color: theme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  if (actions.isEmpty)
                    Text(texts.noAction,
                        style: TextStyle(color: theme.secondary))
                  else
                    ...actions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final action = entry.value;
                      final active = index == selected;
                      return GestureDetector(
                        onTap: () => _select(action),
                        child: MouseRegion(
                          onEnter: (_) =>
                              setState(() => _selectedIndex = index),
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: active ? theme.primary : null,
                            ),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 1),
                            child: Text(
                              '${active ? '▶' : ' '} ${action.titleFor(env.locale)}',
                              style: TextStyle(
                                color:
                                    active ? theme.onPrimary : theme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _onKeyEvent(KeyboardEvent event, List<CliAction> actions) {
    if (event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.backspace) {
      _dismiss();
      return true;
    }
    if (actions.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowDown) {
      setState(() => _selectedIndex = (_selectedIndex + 1) % actions.length);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      setState(() {
        final next = (_selectedIndex - 1) % actions.length;
        _selectedIndex = next < 0 ? actions.length - 1 : next;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      final i = _selectedIndex.clamp(0, actions.length - 1);
      _select(actions[i]);
      return true;
    }
    return false;
  }

  void _select(CliAction action) {
    component.coordinator.overlayPath.pop();
    component.coordinator.requestRun(action.id);
  }

  void _dismiss() {
    component.coordinator.overlayPath.pop();
  }
}
