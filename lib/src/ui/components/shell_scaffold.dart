import 'package:nocterm/nocterm.dart';

class ShellScaffold extends StatelessComponent {
  const ShellScaffold({
    required this.pageTitle,
    required this.body,
    this.subtitle = '',
    this.focused = false,
    super.key,
  });

  final String pageTitle;
  final String subtitle;
  final Component body;

  /// When true, the scaffold's border is drawn in the primary theme color
  /// so the focused panel is visually distinguishable. Optional one-line
  /// focus cue per Upgrade 5 bonus.
  final bool focused;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final borderColor = focused ? theme.primary : theme.outline;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.surface,
        border: BoxBorder.all(
          color: borderColor,
          style: BoxBorderStyle.rounded,
        ),
        title: BorderTitle(
          text: pageTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.primary,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: Column(
        crossAxisAlignment: .start,
        children: <Component>[
          if (subtitle.isNotEmpty) Text(subtitle),
          const Divider(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
