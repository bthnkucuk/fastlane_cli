import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import '../localization/i18n/strings.g.dart';
import 'app_route.dart';
import 'coordinator.dart';
import 'routes/category_routes.dart';
import 'routes/guide_route.dart';
import 'routes/home_route.dart';
import 'routes/palette_route.dart';
import 'routes/quick_actions_route.dart';

class ShellLayout extends AppRoute with RouteLayout<AppRoute> {
  ShellLayout();

  @override
  IndexedStackPath<AppRoute> resolvePath(
    covariant FastlaneCliCoordinator coordinator,
  ) => coordinator.topTabsPath;

  @override
  Uri toUri() => Uri(path: '/');

  @override
  Component build(
    covariant FastlaneCliCoordinator coordinator,
    BuildContext context,
  ) {
    return _ShellView(coordinator: coordinator);
  }
}

class _ShellView extends StatefulComponent {
  const _ShellView({required this.coordinator});

  final FastlaneCliCoordinator coordinator;

  @override
  State<_ShellView> createState() => _ShellViewState();
}

class _ShellViewState extends State<_ShellView> {
  FastlaneCliCoordinator get _c => component.coordinator;

  @override
  void initState() {
    super.initState();
    _c.runTabsPath.addListener(_onChange);
    _c.overlayPath.addListener(_onChange);
    _c.palettePath.addListener(_onChange);
    _c.environment.addLocaleListener(_onLocaleChange);
  }

  @override
  void dispose() {
    _c.runTabsPath.removeListener(_onChange);
    _c.overlayPath.removeListener(_onChange);
    _c.palettePath.removeListener(_onChange);
    _c.environment.removeLocaleListener(_onLocaleChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onLocaleChange(_) {
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final overlay = _c.overlayPath.activeRoute;
    final runActive = _c.runTabsPath.activeRoute;

    final body = runActive != null
        ? runActive.build(_c, context)
        : _c.topTabsPath.activeRoute.build(_c, context);

    return Focusable(
      focused: overlay == null && !_c.palettePath.expanded,
      onKeyEvent: _onGlobalKey,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(color: theme.background),
        child: Stack(
          children: <Component>[
            Column(
              children: <Component>[
                _ShellHeader(coordinator: _c),
                if (_c.runTabsPath.stack.isNotEmpty)
                  _RunTabStrip(coordinator: _c),
                Expanded(child: body),
                CommandPaletteCompactBar(coordinator: _c),
                _ShellFooter(coordinator: _c),
              ],
            ),
            if (overlay != null)
              Positioned.fill(child: overlay.build(_c, context)),
          ],
        ),
      ),
    );
  }

  bool _onGlobalKey(KeyboardEvent event) {
    final palette = _c.palettePath;
    final overlayActive = _c.overlayPath.activeRoute != null;

    if (overlayActive) {
      if (event.logicalKey == LogicalKey.escape) {
        _c.overlayPath.pop();
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKey.slash && !palette.expanded) {
      palette.expand();
      return true;
    }

    if (event.logicalKey == LogicalKey.escape && palette.expanded) {
      palette.minimize();
      return true;
    }

    if (palette.expanded) {
      // Let the palette compact bar handle keys.
      return false;
    }

    if (event.logicalKey == LogicalKey.keyP && event.isControlPressed) {
      // ignore: unawaited_futures
      _c.overlayPath.push(QuickActionsRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyQ) {
      _c.confirmQuit();
      return true;
    }
    if (event.logicalKey == LogicalKey.keyL) {
      _c.environment.toggleLocale();
      return true;
    }
    if (event.logicalKey == LogicalKey.keyH) {
      _c.replace(HomeRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyA) {
      _c.replace(AndroidCategoryRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyI) {
      _c.replace(IosCategoryRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyG) {
      _c.replace(GeneralCategoryRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyD) {
      _c.replace(GuideRoute(topicId: 'android_metadata'));
      return true;
    }

    return false;
  }
}

// ---------------------------------------------------------------------------
// Header (top tab bar + quick-actions toggle)
// ---------------------------------------------------------------------------

class _ShellHeader extends StatefulComponent {
  const _ShellHeader({required this.coordinator});

  final FastlaneCliCoordinator coordinator;

  @override
  State<_ShellHeader> createState() => _ShellHeaderState();
}

class _ShellHeaderState extends State<_ShellHeader> {
  String? _hoveredKey;

  @override
  void initState() {
    super.initState();
    component.coordinator.topTabsPath.addListener(_onChange);
  }

  @override
  void dispose() {
    component.coordinator.topTabsPath.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final c = component.coordinator;
    final theme = TuiTheme.of(context);
    final title = '${t.shellBrand} [${c.environment.profile.appName}]';

    final items = <_HeaderItem>[
      _HeaderItem(label: t.homeTitle, index: 0),
      _HeaderItem(label: 'Android', index: 1),
      _HeaderItem(label: 'iOS', index: 2),
      _HeaderItem(label: t.generalTitle, index: 3),
      _HeaderItem(label: t.guidesTitle, index: 4),
    ];

    return Container(
      decoration: BoxDecoration(
        border: BoxBorder.all(color: theme.outline),
        color: theme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        crossAxisAlignment: .center,
        children: <Component>[
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.primary),
          ),
          const SizedBox(width: 2),
          ...items.map((item) => _buildItem(item, theme, c)),
          Expanded(child: const SizedBox.shrink()),
          _buildQuickActionsButton(theme, c),
        ],
      ),
    );
  }

  Component _buildItem(
    _HeaderItem item,
    TuiThemeData theme,
    FastlaneCliCoordinator c,
  ) {
    final activeIndex = c.topTabsPath.activeIndex;
    final runActive = c.runTabsPath.activeRoute != null;
    final active = !runActive && activeIndex == item.index ||
        _hoveredKey == 'tab:${item.index}';

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredKey = 'tab:${item.index}'),
      onExit: (_) {
        if (_hoveredKey == 'tab:${item.index}') {
          setState(() => _hoveredKey = null);
        }
      },
      child: GestureDetector(
        onTap: () {
          // If a run tab was hiding the top-tab body, opening a tab
          // should bring the top stack to the foreground. Reset run-tab
          // active index by activating none — easiest is to activate
          // the route directly.
          c.topTabsPath.goToIndexed(item.index);
          if (c.runTabsPath.activeRoute != null) {
            // Force fall-through to top tabs by clearing run active.
            // Note: can't set _activeIndex directly from here, so navigate.
            // We expose a helper instead.
            c.deactivateRunTabs();
          }
        },
        child: Container(
          decoration: BoxDecoration(color: active ? theme.primary : null),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          margin: const EdgeInsets.only(right: 1),
          child: Text(
            item.label,
            style: TextStyle(
              color: active ? theme.onPrimary : theme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Component _buildQuickActionsButton(
    TuiThemeData theme,
    FastlaneCliCoordinator c,
  ) {
    const buttonKey = 'header:quick-actions';
    final visible = c.overlayPath.activeRoute is QuickActionsRoute;
    final active = visible || _hoveredKey == buttonKey;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredKey = buttonKey),
      onExit: (_) {
        if (_hoveredKey == buttonKey) setState(() => _hoveredKey = null);
      },
      child: GestureDetector(
        onTap: () {
          if (visible) {
            c.overlayPath.pop();
          } else {
            // ignore: unawaited_futures
            c.overlayPath.push(QuickActionsRoute());
          }
        },
        child: Container(
          decoration: BoxDecoration(color: active ? theme.primary : null),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text(
            '${t.shortcuts} ${visible ? '▴' : '▾'}',
            style: TextStyle(
              color: active ? theme.onPrimary : theme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderItem {
  const _HeaderItem({required this.label, required this.index});
  final String label;
  final int index;
}

// ---------------------------------------------------------------------------
// Run tab strip
// ---------------------------------------------------------------------------

class _RunTabStrip extends StatefulComponent {
  const _RunTabStrip({required this.coordinator});
  final FastlaneCliCoordinator coordinator;

  @override
  State<_RunTabStrip> createState() => _RunTabStripState();
}

class _RunTabStripState extends State<_RunTabStrip> {
  @override
  void initState() {
    super.initState();
    component.coordinator.runTabsPath.addListener(_onChange);
  }

  @override
  void dispose() {
    component.coordinator.runTabsPath.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Component build(BuildContext context) {
    final c = component.coordinator;
    final theme = TuiTheme.of(context);
    final activeIndex = c.runTabsPath.activeIndex;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: theme.surface),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: c.runTabsPath.stack.asMap().entries.map((entry) {
          final i = entry.key;
          final route = entry.value;
          return route.tabLabel(c, c.runTabsPath, context, active: i == activeIndex);
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer hints
// ---------------------------------------------------------------------------

class _ShellFooter extends StatelessComponent {
  const _ShellFooter({required this.coordinator});
  final FastlaneCliCoordinator coordinator;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final hints = <String>[
      'Tab Focus',
      '/ Palette',
      'H Home',
      'A Android',
      'I iOS',
      'G General',
      'L ${t.localeLabel}',
      'Q Quit',
    ];
    return Container(
      width: double.infinity,
      child: Row(
        children: hints
            .map(
              (hint) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(hint, style: TextStyle(color: theme.onSurface)),
              ),
            )
            .toList(),
      ),
    );
  }
}
