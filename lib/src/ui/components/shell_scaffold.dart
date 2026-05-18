import 'package:nocterm/nocterm.dart';

class ShellScaffold extends StatelessComponent {
  const ShellScaffold({
    required this.pageTitle,
    required this.body,
    this.subtitle = '',
    super.key,
  });

  final String pageTitle;
  final String subtitle;
  final Component body;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.surface,
        border: BoxBorder.all(color: theme.outline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      child: Column(
        crossAxisAlignment: .start,
        children: <Component>[
          Text(
            pageTitle,
            style: TextStyle(fontWeight: FontWeight.bold, color: theme.primary),
          ),
          if (subtitle.isNotEmpty) Text(subtitle),
          const Divider(),
          Expanded(child: body),
        ],
      ),
    );
  }
}
