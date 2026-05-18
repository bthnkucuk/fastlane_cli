import 'package:nocterm/nocterm.dart';

import '../../localization/app_texts.dart';
import '../../model/palette_suggestion.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';

/// Base for palette path routes (currently only the command palette itself).
abstract base class PaletteRoute extends AppRoute {
  PaletteRoute();

  @override
  Type get layout => ShellLayout;
}

final class CommandPaletteRoute extends PaletteRoute {
  CommandPaletteRoute();

  @override
  Uri toUri() => Uri(path: '/palette');

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    // The palette UI is rendered inline by the CommandPalettePath layout
    // builder (compact field always visible, suggestions shown when expanded).
    // The route's `build` is intentionally minimal — it lets the coordinator
    // know the route is "live" so the path's builder takes over.
    return const SizedBox.shrink();
  }
}

/// Compact, always-visible text field. Mounted by the
/// CommandPalettePath layout builder, not by individual pages.
class CommandPaletteCompactBar extends StatefulComponent {
  const CommandPaletteCompactBar({required this.coordinator, super.key});

  final FastlaneCliCoordinator coordinator;

  @override
  State<CommandPaletteCompactBar> createState() =>
      _CommandPaletteCompactBarState();
}

class _CommandPaletteCompactBarState extends State<CommandPaletteCompactBar> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  int _selectedIndex = 0;

  FastlaneCliCoordinator get _c => component.coordinator;

  @override
  void initState() {
    super.initState();
    _c.palettePath.addListener(_onPathChanged);
  }

  @override
  void dispose() {
    _c.palettePath.removeListener(_onPathChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onPathChanged() {
    if (mounted) setState(() {});
  }

  List<PaletteSuggestion> _buildSuggestions() {
    return _c.environment.paletteSuggestionService.build(
      profile: _c.environment.profile,
      locale: _c.environment.locale,
      query: _query,
    );
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final texts = AppTexts(_c.environment.locale);
    final expanded = _c.palettePath.expanded;
    final suggestions = expanded ? _buildSuggestions() : const <PaletteSuggestion>[];
    if (_selectedIndex >= suggestions.length) {
      _selectedIndex = suggestions.isEmpty ? 0 : suggestions.length - 1;
    }

    return Column(
      crossAxisAlignment: .start,
      children: <Component>[
        if (expanded) _buildSuggestions_(suggestions, theme, texts),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: BoxBorder.all(
              color: expanded ? theme.primary : theme.outline,
            ),
            color: theme.surface,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: TextField(
            controller: _controller,
            focused: expanded,
            placeholder: texts.commandPalettePlaceholder,
            onChanged: (value) {
              setState(() {
                _query = value;
                _selectedIndex = 0;
              });
              if (value.isNotEmpty && !expanded) {
                _c.palettePath.expand();
              }
            },
            onSubmitted: (_) => _executeSelection(suggestions),
            onFocusChange: (_) {},
            onKeyEvent: (event) {
              if (event.logicalKey == LogicalKey.arrowDown) {
                _move(1, suggestions.length);
                return true;
              }
              if (event.logicalKey == LogicalKey.arrowUp) {
                _move(-1, suggestions.length);
                return true;
              }
              if (event.logicalKey == LogicalKey.escape) {
                _close(clearQuery: true);
                return true;
              }
              if (event.logicalKey == LogicalKey.enter) {
                _executeSelection(suggestions);
                return true;
              }
              return false;
            },
          ),
        ),
      ],
    );
  }

  Component _buildSuggestions_(
    List<PaletteSuggestion> suggestions,
    TuiThemeData theme,
    AppTexts texts,
  ) {
    const visible = 8;
    final safeSelected = suggestions.isEmpty
        ? 0
        : _selectedIndex.clamp(0, suggestions.length - 1);
    final start = suggestions.length <= visible
        ? 0
        : (safeSelected - visible + 1).clamp(0, suggestions.length - visible);
    final end = suggestions.length <= visible
        ? suggestions.length
        : start + visible;
    final window = suggestions.sublist(start, end);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.surface,
        border: BoxBorder.all(color: theme.primary),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: .start,
        children: <Component>[
          if (suggestions.isEmpty)
            Text(texts.commandPaletteNoResult,
                style: TextStyle(color: theme.warning))
          else
            ...window.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final item = entry.value;
              final absolute = start + rowIndex;
              final active = absolute == safeSelected;
              return MouseRegion(
                onEnter: (_) => setState(() => _selectedIndex = absolute),
                child: GestureDetector(
                  onTap: () => _execute(suggestions[absolute]),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: active ? theme.primary : null,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Text(
                      '${active ? '▶' : ' '} ${item.title} · ${item.subtitle}',
                      style: TextStyle(
                        color: active ? theme.onPrimary : theme.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            }),
          const SizedBox(height: 1),
          Text(
            texts.commandPaletteTitle,
            style: TextStyle(
              color: theme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _move(int delta, int count) {
    if (count <= 0) return;
    final next = (_selectedIndex + delta) % count;
    setState(() => _selectedIndex = next < 0 ? count - 1 : next);
  }

  void _executeSelection(List<PaletteSuggestion> suggestions) {
    if (suggestions.isEmpty) return;
    final safe = _selectedIndex.clamp(0, suggestions.length - 1);
    _execute(suggestions[safe]);
  }

  void _execute(PaletteSuggestion suggestion) {
    _c.executePaletteSuggestion(suggestion);
    _close(clearQuery: true);
  }

  void _close({required bool clearQuery}) {
    if (clearQuery) {
      _controller.text = '';
      _query = '';
      _selectedIndex = 0;
    }
    _c.palettePath.minimize();
  }
}
