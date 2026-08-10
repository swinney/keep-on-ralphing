## Why

The Ralph loop is an *executor*: give it a well-formed task list and it grinds. But the
machinery that decides **what** it should work on tonight — triaging a GitHub issue tracker
into an opt-in queue, turning the top issue into a spec, supervising a multi-hour loop under
systemd, working the review feedback the next morning, and never merging — exists only as
one operator's private, project-hardwired setup: 12 prefixed skills under `~/.claude/skills/`
plus ~15 supervisor scripts in a private config repo.

That machinery is not domain-specific. Strip the proper nouns from it and what remains is a
complete, project-agnostic design: a label taxonomy, a five-condition bar for "a cold agent
can do this unattended", effort tiers, and a systemd supervision model whose shape was paid
for in production incidents. `ralph-harness` ships the executor; nothing ships the workflow
around it, so every new project rebuilds it by hand or does without.

## What Changes

- **`gh-nightly`, a second plugin in this marketplace** — the GitHub-issue→PR nightly
  workflow, with `ralph-harness` as its executor. The two are a matched pair: the loop does
  the work, `gh-nightly` decides what work there is and reviews the result.
- **A layout decision, pending (see `design.md` D3).** To seat a sibling plugin, either
  `ralph-harness` moves from the marketplace root (`"source": "./"`) into
  `plugins/ralph-harness/` — **BREAKING for repo layout, not behavior**, moving `base/`,
  `Makefile`, `skills/`, `templates/`, `example/`, CI and test paths together — or it stays at
  the root and only the new plugin takes a subdirectory. No requirement changes either way, since
  `$CLAUDE_PLUGIN_ROOT` resolves dynamically. The symmetric option is a large mechanical diff
  against a green suite and must land as its own content-free commit; the asymmetric option
  avoids that churn entirely. Resolved before implementation begins.
- **13 skills in `gh-nightly`.** Ten generalized from the operator's set (`nightly-triage`,
  `nightly-explore`, `nightly-drain`, `nightly-review`, `pr-review-response`,
  `followup-issue`, `resolve-parked`, `weekly-report`, `track-work`, and
  `background-explorer`, which is already project-agnostic and is a hard dependency of
  `nightly-explore`). Three new: `nightly-onboard`, `nightly-doctor`, `nightly-upgrade`.
- **Generalization means deleting defaults, not rewriting logic.** The taxonomy
  (`auto-ok` / `explore` / `needs-human` / `needs-deploy`; effort tiers
  `sonnet` < default < `ultracode`; `P1`/`P2`/`P3`) and the five-condition `auto-ok` bar are
  already project-neutral and MUST NOT change semantically. What changes is that proper nouns
  become config lookups.
- **The supervisor layer becomes shippable.** Nine scripts and twelve systemd units are
  extracted from a private repo. `nightly-drain.sh` is already fully env-parameterized
  (`DRAIN_WORKSPACE`, `DRAIN_REPO`, `DRAIN_LOOP_CMD`, `DRAIN_BASE_BRANCH`, …), so
  generalizing it is mostly removing the project-specific defaults so config becomes *required*.
  Its five existing shell test suites come along as the evidence that behavior survived.
- **One config file.** `gh-nightly.conf`, shell-sourceable, `EnvironmentFile=`d by the units
  and read by each skill as its first step. Keeps the `DRAIN_*` names so the supervisor needs
  no rewiring.
- **`nightly-doctor` is earned, not speculative.** An issue in the operator's tracker sat
  unworked for multiple nights because a systemd timer was `disabled` rather than absent, and
  nothing in the stack noticed. Verifying *enabled*, not merely *installed*, is a requirement.
- **A publication scrub gate.** `make scrub-check`, wired into CI and the pre-commit hook,
  fails on private-infrastructure tokens (internal hostnames, private repo slugs, absolute
  operator paths, secret paths, tracker project/task IDs, internal ports). It lands **before**
  any extracted content, so nothing unscrubbed can be committed even once.
- **Declared prerequisites, not adapters:** `ralph-harness`, OpenSpec, `gh`, systemd user
  units, `jq`. This matches the repo's existing narrow scope (Linux + podman) and keeps the
  product honest — it is the one configuration that actually runs nightly.

Out of scope, staying in the operator's private setup: the `ragas-goldenset`,
`dev-llm-failover` and `dev-deploy-verify` skills and the `ingestion-verifier`,
`provider-config-auditor` and `black-seam-scout` subagents. Those are about a specific
product, and excluding them is also what keeps private infrastructure out of a public repo.

## Capabilities

### New Capabilities
- `nightly-pipeline`: the unattended chain — triage a tracker into a labeled queue, explore
  uncertain issues into notes, drain one opt-in issue per invocation to a PR, and work review
  feedback the next morning. Owns the label taxonomy, the `auto-ok` bar, the effort tiers, and
  the never-merge rail.
- `nightly-supervision`: the host-side supervision model — systemd owns the multi-hour loop's
  lifetime while agent turns stay bounded; an isolated bot checkout keeps the loop out of a
  tree a human edits; a deny hook blocks control-plane writes at the tool layer; window guard,
  token preflight, failure alarms, and per-run cost reporting.
- `nightly-config`: the `gh-nightly.conf` contract, its detection-and-interview onboarding,
  the tracked provenance manifest, health verification, and confirm-gated upgrades.
- `gh-workflow-skills`: the operator-present GitHub skills usable without any scheduler —
  responding to automated review, filing cold-start work orders, clearing the parked backlog,
  and reporting delivered work.
- `marketplace-multi-plugin`: a marketplace hosting more than one plugin — per-plugin
  relative sources, independent versioning, and the install/update path for each.
- `publication-scrub`: the machine-enforced guarantee that private infrastructure never
  reaches a public commit.

### Modified Capabilities
<!-- None. base-image-provisioning resolves the plugin root via $CLAUDE_PLUGIN_ROOT, so
     relocating ralph-harness changes no requirement; project-bootstrap and config-upgrade
     remain scoped to /ralph-init and /ralph-upgrade and are untouched. -->

## Impact

- **Repo layout:** under the symmetric option every path in `ralph-harness` moves one level down —
  `Makefile`, CI workflow, `base/tests/*` relative paths, `.claude-plugin/` location, and the
  root-relative path documentation in `CLAUDE.md` all follow. Under the asymmetric option only
  the marketplace manifest gains an entry.
- **Release channels:** a second `plugin.json` to version. The repo's existing rule — a
  `skills/` or `templates/` change without a version bump makes `/plugin update` a silent
  no-op — now applies twice, independently.
- **Gate:** `make test` must cover the new plugin. The five extracted supervisor suites join
  it, and `make scrub-check` becomes a gate step.
- **Source of truth moves for 10 skills.** Their chezmoi-managed copies under
  `~/.claude/skills/` must be `chezmoi forget`-ed and deleted, or the dotfile copies will
  reappear and shadow the plugin versions.
- **Private repo:** the extracted supervisor scripts remain deployed there until the operator's
  own project is cut over to the plugin; the two coexist during migration.
- **Acceptance is a live night, not a green suite:** the operator's project becomes the first
  consumer, its values in a `gh-nightly.conf`, draining a real issue to a real PR through the
  generic plugin with unchanged behavior.
