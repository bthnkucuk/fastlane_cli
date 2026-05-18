import 'package:nocterm/nocterm.dart';

import '../../localization/i18n/strings.g.dart';
import '../../localization/locale_code.dart';
import '../../model/guide_topic.dart';
import '../../ui/components/shell_scaffold.dart';
import '../app_route.dart';
import '../coordinator.dart';
import '../shell_layout.dart';
import 'home_route.dart';

final class GuideRoute extends AppRoute {
  GuideRoute({required this.topicId, this.retryActionId});

  final String topicId;
  final String? retryActionId;

  @override
  List<Object?> get props => [topicId, retryActionId];

  @override
  Type get layout => ShellLayout;

  @override
  Uri toUri() => Uri(
    path: '/guides/$topicId',
    queryParameters: retryActionId == null ? null : {'action': retryActionId!},
  );

  @override
  Component build(FastlaneCliCoordinator c, BuildContext context) {
    return _GuideView(
      coordinator: c,
      topicId: topicId,
      retryActionId: retryActionId,
    );
  }
}

class _GuideView extends StatelessComponent {
  const _GuideView({
    required this.coordinator,
    required this.topicId,
    required this.retryActionId,
  });

  final FastlaneCliCoordinator coordinator;
  final String topicId;
  final String? retryActionId;

  @override
  Component build(BuildContext context) {
    final env = coordinator.environment;
    final guide = env.guideRegistry.topicById(
      topicId: topicId,
      profile: env.profile,
    );

    return Focusable(
      focused: !coordinator.palettePath.expanded,
      onKeyEvent: _onKeyEvent,
      child: ShellScaffold(
        pageTitle: guide?.titleFor(env.locale) ?? t.guidesTitle,
        subtitle: guide?.summaryFor(env.locale) ?? t.guideFallback,
        body: _buildBody(env.locale, guide),
      ),
    );
  }

  Component _buildBody(LocaleCode locale, GuideTopic? guide) {
    final items = <Component>[];
    if (guide == null) {
      items.add(Text(t.guideFallback));
    } else {
      // NOTE: `markdownFor` currently synthesizes markdown from the
      // checklist + paths maps. When the Slang agent migrates the registry
      // strings to slang YAML, `markdownFor` can return localized markdown
      // verbatim with no changes here.
      items.add(MarkdownText(guide.markdownFor(locale)));
    }

    if (retryActionId != null && retryActionId!.isNotEmpty) {
      items.add(const SizedBox(height: 1));
      items.add(Text('${t.guideRetry} ($retryActionId)'));
    }
    items.add(const SizedBox(height: 1));
    items.add(Text(t.back));

    return Column(crossAxisAlignment: .start, children: items);
  }

  bool _onKeyEvent(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.backspace ||
        event.logicalKey == LogicalKey.escape ||
        event.logicalKey == LogicalKey.keyB) {
      coordinator.replace(HomeRoute());
      return true;
    }
    if (event.logicalKey == LogicalKey.keyR &&
        retryActionId != null &&
        retryActionId!.isNotEmpty) {
      coordinator.requestRun(retryActionId!);
      return true;
    }
    return false;
  }
}
