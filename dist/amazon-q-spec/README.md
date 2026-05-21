# Amazon Q / Kiro CLI autocomplete spec

This directory contains the [Fig-style] completion spec for `fastlane_cli`
consumed by **Amazon Q Developer CLI for command line** (formerly Fig) and
[Kiro CLI]. The canonical upstream destination is
`withfig/autocomplete/src/fastlane_cli.ts`.

[Fig-style]: https://fig.io/docs/autocomplete
[Kiro CLI]: https://kiro.dev/docs/cli/

## Why a copy lives here

We track the spec in this repo (as well as upstream) so:

- It travels with the CLI version it describes (`pubspec.yaml` `version:`).
- Drift between code and spec is caught by the same reviewers who own
  `lib/src/cli/*_command.dart`.
- A user can opt into the spec **before** the upstream PR is merged by
  pointing their local dev-mode autocomplete repo at this file.

## Files

| File | Purpose |
|---|---|
| [`fastlane_cli.ts`](fastlane_cli.ts) | Fig.Spec definition — every subcommand, option, and arg the CLI accepts. |

## Generators (no static action enumeration)

The `run <action-id>` and `list --category <id>` arguments resolve their
suggestions by shelling out to `fastlane_cli list --json` and parsing the
result. The JSON shape is fixed (`id`, `title`, `description`, `category`)
and emitted by `lib/src/cli/list_command.dart`. Results are cached for 5
seconds inside the autocomplete runtime.

This means **the spec never goes stale** when consumers add custom actions
in their `profile.yaml` — the dropdown reflects whatever
`fastlane_cli list --json` reports.

## Testing locally with Amazon Q / Kiro CLI

Both clients can load a local spec via the `withfig/autocomplete` dev-mode
flow:

```bash
# 1. Fork + clone the upstream specs repo.
git clone https://github.com/<you>/autocomplete.git
cd autocomplete
pnpm install

# 2. Drop our spec into src/.
cp /path/to/fastlane_cli/dist/amazon-q-spec/fastlane_cli.ts src/

# 3. Start dev mode — specs are recompiled on save and read live.
pnpm dev

# 4. In another terminal: `fastlane_cli ` and hit space; the ghost-text
#    and dropdown should now reflect this spec.
```

For Kiro CLI specifically, follow the dev-spec injection instructions in
[kiro.dev/docs/cli](https://kiro.dev/docs/cli/) — Kiro consumes the same
`@withfig/autocomplete` build output that Q does, so the steps above apply.

## Typecheck

Inside the upstream fork (the cleanest path — types are already wired):

```bash
cp dist/amazon-q-spec/fastlane_cli.ts <path-to>/autocomplete/src/
cd <path-to>/autocomplete
pnpm test    # runs tsc --noEmit on the entire src/ tree
```

Standalone (without cloning upstream):

```bash
cd dist/amazon-q-spec
bun add -d typescript@~5.5.4 @withfig/autocomplete-types@^1.31.0
bun ./node_modules/typescript/lib/tsc.js \
  --target es2018 --module esnext --moduleResolution node \
  --types @withfig/autocomplete-types --noEmit --skipLibCheck \
  fastlane_cli.ts
```

The standalone typecheck artefacts (`node_modules`, `package.json`,
`tsconfig.typecheck.json`) are deliberately not committed — recreate them
on demand.

## Upstream PR

This spec is mirrored upstream at
`withfig/autocomplete/src/fastlane_cli.ts`. Upstream PR:
[withfig/autocomplete#2625](https://github.com/withfig/autocomplete/pull/2625).
