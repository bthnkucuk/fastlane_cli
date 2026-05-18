import 'package:nocterm/nocterm.dart';

import '../../localization/i18n/strings.g.dart';
import '../../ui/components/action_list_view.dart';
import '../../ui/components/shell_scaffold.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';
import 'home_route.dart';

abstract base class _CategoryRoute extends AppRoute {
  _CategoryRoute();

  String get categoryId;

  @override
  Type get layout => ShellLayout;

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _CategoryView(coordinator: c, categoryId: categoryId);
  }
}

final class AndroidCategoryRoute extends _CategoryRoute {
  AndroidCategoryRoute();
  @override
  String get categoryId => 'android';
  @override
  Uri toUri() => Uri(path: '/android');
}

final class IosCategoryRoute extends _CategoryRoute {
  IosCategoryRoute();
  @override
  String get categoryId => 'ios';
  @override
  Uri toUri() => Uri(path: '/ios');
}

final class GeneralCategoryRoute extends _CategoryRoute {
  GeneralCategoryRoute();
  @override
  String get categoryId => 'general';
  @override
  Uri toUri() => Uri(path: '/general');
}

class _CategoryView extends StatefulComponent {
  const _CategoryView({required this.coordinator, required this.categoryId});

  final FastlaneCliCoordinator coordinator;
  final String categoryId;

  @override
  State<_CategoryView> createState() => _CategoryViewState();
}

class _CategoryViewState extends State<_CategoryView> {
  int _selectedIndex = 0;
  int? _hoveredIndex;

  @override
  Component build(BuildContext context) {
    final env = component.coordinator.environment;
    final profile = env.profile;
    final matching = profile.categories.where((c) => c.id == component.categoryId);
    final category = matching.isEmpty ? null : matching.first;
    final actions = profile.actionsForCategory(component.categoryId);

    if (_selectedIndex >= actions.length) {
      _selectedIndex = actions.isEmpty ? 0 : actions.length - 1;
    }
    if (_hoveredIndex != null && _hoveredIndex! >= actions.length) {
      _hoveredIndex = null;
    }

    final pageTitle =
        category?.titleFor(env.locale) ?? component.categoryId.toUpperCase();
    final subtitle = category?.descriptionFor(env.locale) ?? '';

    return Focusable(
      focused: !component.coordinator.palettePath.expanded,
      onKeyEvent: (event) => _onKeyEvent(event, actions.length),
      child: ShellScaffold(
        pageTitle: pageTitle,
        subtitle: subtitle,
        body: Column(
          crossAxisAlignment: .start,
          children: <Component>[
            Text(
              '${t.upDownNavigate} · ${t.pressEnterToRun} · ${t.back}',
            ),
            const SizedBox(height: 1),
            if (actions.isEmpty)
              Text(t.noAction)
            else
              ActionListView(
                actions: actions,
                selectedIndex: _selectedIndex,
                hoveredIndex: _hoveredIndex,
                locale: env.locale,
                onActionHover: (index) {
                  if (_hoveredIndex == index) return;
                  setState(() => _hoveredIndex = index);
                },
                onActionTap: (index) {
                  setState(() => _selectedIndex = index);
                  _runSelected();
                },
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
    if (event.logicalKey == LogicalKey.enter && len > 0) {
      _runSelected();
      return true;
    }
    if (event.logicalKey == LogicalKey.backspace ||
        event.logicalKey == LogicalKey.escape) {
      component.coordinator.replace(HomeRoute());
      return true;
    }
    return false;
  }

  void _runSelected() {
    final actions = component.coordinator.environment.profile
        .actionsForCategory(component.categoryId);
    if (_selectedIndex < actions.length) {
      component.coordinator.requestRun(actions[_selectedIndex].id);
    }
  }
}
