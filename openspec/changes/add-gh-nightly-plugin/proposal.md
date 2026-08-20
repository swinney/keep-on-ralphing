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
- **BREAKING (repo layout, not behavior):** `ralph-harness` moves from the marketplace root
  (`"source": "./"`) into `plugins/ralph-harness/`, so plugin roots are disjoint. `base/`,
  `Makefile`, `skills/`, `templates/`, `example/`, CI paths and test paths all move together. No
  requirement changes — `$CLAUDE_PLUGIN_ROOT` resolves dynamically. The zero-churn alternative
  (leave `ralph-harness` at the root, nest only the new plugin) was **rejected as unsound**: a
  root-sourced plugin's release tree contains its siblings, so a `gh-nightly`-only edit would also
  change `ralph-harness`'s tree, contradicting independent versioning. Disjoint roots is the only
  layout in which that requirement is implementable. The move lands as its own content-free commit
  with the gate green on both sides.
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
- **Two configs, split by trust, never shell-sourced.** Host-execution settings (workspace,
  executor command, agent binary, models, baseline deny globs) are operator-owned and live outside
  the consumed repo; only inert descriptors (repo slug, trunk, gate command, labels, branch
  pattern, tracker visibility, report sink) are tracked in the consumer. Both use one restricted
  `KEY=VALUE` grammar — no substitution, no expansion, unknown keys rejected — chosen as the
  intersection of what the service manager and a strict reader both accept, so the two readers
  cannot silently disagree. Deny globs are **additive-only**: a repo can broaden the restriction on
  itself, never narrow it. Keeps the `DRAIN_*` key names so the supervisor needs no rewiring.
- **Concurrency is specified, not assumed.** A per-repository host lock plus an atomic claim
  protocol with stale-claim recovery reconciled against branch and pull-request state — because a
  one-issue-per-invocation budget cannot stop two invocations selecting the same issue.
- **Prerequisites are enforced, not merely documented.** Each carries a minimum version and
  required capability; onboarding, health-check and upgrade fail fast on a missing or incompatible
  dependency, including an incompatible companion-plugin pair.
- **`nightly-doctor` is earned, not speculative.** An issue in the operator's tracker sat
  unworked for multiple nights because a systemd timer was `disabled` rather than absent, and
  nothing in the stack noticed. Verifying *enabled*, not merely *installed*, is a requirement.
- **A layered publication scrub with a stated threat model.** `make scrub-check`, wired into CI and
  the pre-commit hook, lands **before** any extracted content so nothing unscrubbed is ever
  committed. Crucially it stores **no literal private value** — the pattern file is itself tracked
  content, so it carries structural patterns plus salted digests, with synthetic fixtures. A second,
  pattern-independent entropy and credential-shape layer catches tokens nobody enumerated. The
  guarantee is explicitly *not* absolute: unlisted, paraphrased, split or encoded values remain out
  of scope and human review still applies.
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

- **Repo layout:** every path in `ralph-harness` moves one level down — `Makefile`, CI workflow,
  `base/tests/*` relative paths, `.claude-plugin/` location, and the root-relative path
  documentation in `CLAUDE.md` all follow.
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
- **Acceptance is fault-path coverage, with the live night as the last gate:** a
  requirement-to-test traceability matrix (an unmapped requirement blocks release), fault-injected
  runs for every supervision and recovery invariant including a rehearsed rollback, and only then
  multiple live scheduled cycles on the first consuming project. One green night proves the happy
  path and none of the expensive failure paths this design exists to get right.
