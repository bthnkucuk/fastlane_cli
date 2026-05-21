import '../model/run_session.dart';
import 'i18n/strings.g.dart';

/// Maps each [RunStatus] to its localized label via slang's top-level `t`
/// accessor. Replaces the deleted `AppTexts.statusLabel(...)` helper.
extension RunStatusLocalization on RunStatus {
  String get label => switch (this) {
        RunStatus.idle => t.status.idle,
        RunStatus.validating => t.status.validating,
        RunStatus.blocked => t.status.blocked,
        RunStatus.confirmationRequired => t.status.confirmationRequired,
        RunStatus.running => t.status.running,
        RunStatus.succeeded => t.status.succeeded,
        RunStatus.failed => t.status.failed,
        RunStatus.dryRun => t.status.dryRun,
      };
}
