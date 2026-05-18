# packages/fastlane_cli — Test Quality Report

**Overall grade:** B

> 13 test files / 3,840 LOC for 36 lib files / 9,988 LOC = **0.38** ratio. Pure-Dart, tests use `package:test` directly (not flutter_test). Strategy §11.8 #5 flagged `coverage/` directory committed (now removed?). No leak-tracker (correctly — pure-Dart). The single biggest leverage: confirm coverage/ dir is gitignored; add command-flow regression tests around the new `fastlane-summary-log` skill.

## Dimensions

### Unit / Logic coverage — A-
- 13 test files cover command_execution_service, storepilot_bridge commands, lane orchestration.

### Widget tests — N/A
- CLI tool; no widgets.

### Golden tests — N/A

### Mocking discipline — B+
- 0 mockito; 0 mocktail (uses `package:test` plus dedicated fakes).
- Action: consider mocktail for delegate fakes once the CLI grows.

### Leak hygiene — N/A
- Pure-Dart; `flutter_test_config.dart` not present (correct — Flutter not in pubspec).
- Action: none.

### Hydration round-trips — N/A

### Equatable / stringify — N/A
- Pure-Dart context.

### Flaky tests — A
- 1 `skip: Platform.isWindows ? 'POSIX shell only' : false` — correct platform gating.

### Test:source ratio — B+
- 3,840 / 9,988 = **0.38**.

### CI hookup — B
- Not all melos workspace scripts target pure-Dart packages today. `melos run test-changes` may invoke `flutter test` here and fail; Strategy §6.10 #2 (`scripts/tool/melos_smart_test.sh`) is the action.

### `BUGS_FOUND.md` outstanding — A
- None.

## File inventory

- Tests: 13 files / 3,840 lines
- Lib: 36 files / 9,988 lines
- Test:source ratio: **0.38**
- `flutter_test_config.dart`: not present (correctly absent for pure-Dart)

## How to upgrade overall grade
1. **Add `dart test` invocation to melos `test-changes`** for pure-Dart packages (Strategy §6.10 #2).
2. **Confirm `coverage/` is gitignored** (Strategy §11.8 #5) and committed `*.vm.json` are gone.
3. Add 4 regression tests around the `fastlane-summary-log` skill output format.
