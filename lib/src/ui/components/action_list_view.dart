import 'package:nocterm/nocterm.dart';

import '../../localization/locale_code.dart';
import '../../model/cli_action.dart';

class ActionListView extends StatelessComponent {
  const ActionListView({
    required this.actions,
    required this.selectedIndex,
    required this.locale,
    this.hoveredIndex,
    this.onActionTap,
    this.onActionHover,
    super.key,
  });

  final List<CliAction> actions;
  final int selectedIndex;
  final LocaleCode locale;
  final int? hoveredIndex;
  final void Function(int index)? onActionTap;
  final void Function(int? index)? onActionHover;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    if (actions.isEmpty) {
      // Empty-state glyph only — no new localized strings introduced
      // here. Callers that need a localized message still render their
      // own `texts.noAction` next to this list.
      return Center(
        child: Text(
          '◌',
          style: TextStyle(color: theme.secondary),
        ),
      );
    }


    final rows = <Component>[];
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      final isSelected = index == selectedIndex;
      final isHovered = hoveredIndex == index;
      final isActive = isSelected || isHovered;
      final indicator = isSelected ? '▶' : ' ';
      final description = action.descriptionFor(locale);
      final line = description.isEmpty
          ? '$indicator ${index + 1}. ${action.titleFor(locale)}'
          : '$indicator ${index + 1}. ${action.titleFor(locale)} — $description';
      rows.add(
        MouseRegion(
          onEnter: (_) => onActionHover?.call(index),
          onExit: (_) => onActionHover?.call(null),
          child: GestureDetector(
            onTap: onActionTap == null ? null : () => onActionTap!(index),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: isActive ? theme.primary : null),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text(
                line,
                style: TextStyle(
                  color: isActive ? theme.onPrimary : theme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: .start, children: rows);
  }
}
