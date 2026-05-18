import 'package:nocterm/nocterm.dart';

import '../../localization/app_texts.dart';
import '../../ui/components/action_list_view.dart';
import '../../ui/components/shell_scaffold.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';

final class HomeRoute extends AppRoute {
  HomeRoute();

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(path: '/');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _HomeView(coordinator: c);
  }
}

class _HomeView extends StatefulComponent {
  const _HomeView({required this.coordinator});

  final FastlaneCliCoordinator coordinator;

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  int _selectedIndex = 0;
  int? _hoveredIndex;

  @override
  Component build(BuildContext context) {
    final env = component.coordinator.environment;
    final texts = AppTexts(env.locale);
    final shortcuts = env.profile.shortcutActions;
    if (_selectedIndex >= shortcuts.length) {
      _selectedIndex = shortcuts.isEmpty ? 0 : shortcuts.length - 1;
    }
    if (_hoveredIndex != null && _hoveredIndex! >= shortcuts.length) {
      _hoveredIndex = null;
    }

    return Focusable(
      focused: !component.coordinator.palettePath.expanded,
      onKeyEvent: (event) => _onKeyEvent(event, shortcuts.length),
      child: ShellScaffold(
        pageTitle: texts.homeTitle,
        subtitle:
            '${texts.shortcuts} · ${texts.localeLabel}: ${env.locale.name.toUpperCase()}',
        body: Column(
          crossAxisAlignment: .start,
          children: <Component>[
            Text('${texts.upDownNavigate} · ${texts.pressEnterToRun}'),
            const SizedBox(height: 1),
            if (shortcuts.isEmpty)
              Text(texts.noAction)
            else
              ActionListView(
                actions: shortcuts,
                selectedIndex: _selectedIndex,
                hoveredIndex: _hoveredIndex,
                locale: env.locale,
                onActionHover: (index) {
                  if (_hoveredIndex == index) return;
                  setState(() => _hoveredIndex = index);
                },
                onActionTap: (index) {
                  setState(() => _selectedIndex = index);
                  _runShortcut(index);
                },
              ),
            const SizedBox(height: 1),
            Text(
              '${texts.categories}: Android (/android), iOS (/ios), ${texts.generalTitle} (/general)',
            ),
          ],
        ),
      ),
    );
  }

  bool _onKeyEvent(KeyboardEvent event, int len) {
    if (event.logicalKey == LogicalKey.arrowDown && len > 0) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % len;
        _hoveredIndex = null;
      });
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp && len > 0) {
      setState(() {
        final next = _selectedIndex - 1;
        _selectedIndex = next < 0 ? len - 1 : next;
        _hoveredIndex = null;
      });
      return true;
    }
    final digit = _digitToIndex(event.logicalKey);
    if (digit != null && len > 0 && digit < len) {
      _runShortcut(digit);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter && len > 0) {
      _runShortcut(_selectedIndex);
      return true;
    }
    return false;
  }

  int? _digitToIndex(LogicalKey key) {
    if (key == LogicalKey.digit1) return 0;
    if (key == LogicalKey.digit2) return 1;
    if (key == LogicalKey.digit3) return 2;
    if (key == LogicalKey.digit4) return 3;
    if (key == LogicalKey.digit5) return 4;
    if (key == LogicalKey.digit6) return 5;
    if (key == LogicalKey.digit7) return 6;
    if (key == LogicalKey.digit8) return 7;
    if (key == LogicalKey.digit9) return 8;
    return null;
  }

  void _runShortcut(int index) {
    final shortcuts =
        component.coordinator.environment.profile.shortcutActions;
    if (index >= shortcuts.length) return;
    component.coordinator.requestRun(shortcuts[index].id);
  }
}
