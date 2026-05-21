import 'package:nocterm/nocterm.dart';
import 'package:zenrouter_nocterm/zenrouter_nocterm.dart';

import 'coordinator.dart';
import 'run_tabs_path.dart';

abstract class AppRoute extends RouteTarget with RouteUnique {
  @override
  Component build(
    covariant FastlaneCliCoordinator coordinator,
    BuildContext context,
  );
}

/// Mixin for routes that render a closable tab chip in the run-tabs strip.
mixin RouteTab on RouteUnique {
  Component tabLabel(
    FastlaneCliCoordinator coordinator,
    RunTabsPath path,
    BuildContext context, {
    required bool active,
  });
}
