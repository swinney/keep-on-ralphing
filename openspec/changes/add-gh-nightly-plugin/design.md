## Context

`ralph-harness` ships an executor. The workflow that feeds it — deciding which tracker issue
is safe to hand an unattended agent, turning it into a spec, supervising a multi-hour loop,
and working the review the next morning — exists only as one operator's private setup: 12
single-file skills under `~/.claude/skills/` (all chezmoi-managed) and ~15 scripts plus 12
systemd units in a private config repo.

Two facts make extraction cheap rather than speculative:

1. **The judgment is already project-neutral.** The triage skill's `auto-ok` bar, label
   taxonomy, effort tiers and priority tiers contain no domain concepts. The project-specific
   content is five values: repo slug, trunk branch, gate command, control-plane deny globs,
   and whether the tracker is public.
2. **The supervisor was already written for substitutability.** `nightly-drain.sh` reads every
   path, repo, branch, model and even the executor command from `DRAIN_*` env vars with a
   project default, and its header notes fixture tests inject stubs. Generalizing it is mostly
   *deleting the defaults* so the config becomes required. Five shell test suites already
   exist to prove behavior survived.

Constraints inherited from this repo: scope is deliberately Linux + podman, single
architecture, team-shared via GitHub. Specs live in `openspec/`, ADRs in `docs/decisions/`,
the gate is `make test`, and `extras/` is the established explicitly-unsupported directory.
Release runs through two channels with unlinked versions, and the Skill tool loads the
*cached* plugin rather than the working tree.

## Goals / Non-Goals

**Goals:**

- A second plugin, installable independently, that turns a GitHub tracker into a nightly
  issue→PR pipeline with the Ralph loop as executor.
- Preserve the extracted judgment *exactly*. Genericization replaces proper nouns with config
  lookups; it does not re-litigate the taxonomy or the `auto-ok` bar.
- Make the supervision layer — the part that took production incidents to get right —
  shippable rather than describable.
- Reduce private-infrastructure leakage to a machine-enforced, layered check rather than a
  checklist — without the pattern list itself becoming the disclosure.
- Keep host execution authority out of the consumed repository: nothing the unattended agent can
  write may decide what the host runs, or relax the constraints placed on it.
- Keep the two plugins independently versioned, consistent with the repo's existing
  two-channel release doctrine.

**Non-Goals:**

- Portability beyond Linux + systemd. No cron, launchd, or macOS path.
- Swappable executor or spec layer. `ralph-harness` and OpenSpec are prerequisites.
- Extracting product-specific skills (RAG golden-set maintenance, provider failover,
  deployment verification) or the three product-specific subagents.
- Changing any `ralph-harness` behavior. Its relocation is a move, not a redesign.

## Decisions

### D1: Opinionated stack over adapter contracts

Declare `ralph-harness`, OpenSpec, `gh`, systemd and `jq` as prerequisites.

*Alternatives considered.* (a) Three adapter seams — executor, spec layer, scheduler — with
the current stack as reference implementations. Rejected: the abstraction is unearned until a
second real consumer exists with a different stack, and only the adapter actually in nightly
use would ever be tested. (b) Executor-only seam, since `DRAIN_LOOP_CMD` already provides it.
Rejected as a *documented* seam while the skills' prose still assumes `.ralph/`, `STATUS.md`
and `RALPH_TASKS`; the env var stays, but it is an implementation detail, not a contract.

This also matches the repo's own precedent of narrowing scope on purpose.

**Declared is not enough — prerequisites must be enforced.** A documented dependency list fails
silently: two independently-versioned plugins can install into an incompatible pair and the first
symptom is a broken unattended run at 02:00. Each prerequisite therefore carries a minimum
version and a required capability, and onboarding, health-check and upgrade all fail fast on a
missing or incompatible dependency rather than deferring the discovery to a run.

### D2: Second plugin in this marketplace, not a new repo

`marketplace.json` takes a `plugins` array with per-plugin relative `source` paths, so one
repo can host both. The loop and the workflow around it are a matched pair — anyone
installing one should discover the other — and users add no second marketplace.

*Alternatives considered.* A standalone repo under the same owner (cleanest separation, but forces
a second marketplace and splits a matched pair); folding the new skills into `ralph-harness`
itself (single install, but bloats a deliberately narrow plugin and imposes the GitHub
workflow on loop-only users).

### D3: Symmetric relocation — RESOLVED, the alternative was unsound

`ralph-harness` moves from `"source": "./"` to `plugins/ralph-harness/` so both plugins sit
under disjoint roots below `plugins/`. Plugin roots MUST be disjoint: neither plugin's release
tree may contain the other's files.

*Zero-churn alternative, rejected as contradictory.* Leaving `ralph-harness` at `"source": "./"`
and adding only `./plugins/gh-nightly` looked free — the docs require no symmetry, and skill
discovery scans `<plugin-root>/skills/` only, so a nested directory is inert to discovery. But a
root-sourced plugin's release tree *contains* its sibling, so every `gh-nightly`-only edit also
changes the `ralph-harness` source tree. That directly contradicts the independent-versioning
requirement in `specs/marketplace-multi-plugin/spec.md`: a change confined to one plugin must
require only that plugin's version bump. Preserving both would need an undocumented exclusion
rule inside the version-conformance check — i.e. the check could no longer use ordinary tree
semantics. Disjoint roots is the only layout where the versioning requirement is honestly
implementable.

The cost is real and accepted: `base/`, `Makefile`, `skills/`, `templates/`, `example/`,
`extras/`, `.claude-plugin/`, the CI workflow, every relative path inside `base/tests/*`, and the
root-relative path documentation in `CLAUDE.md` all move at once — a large mechanical diff against
a currently-green suite, on the one artifact already published to installs. Mitigation: the move
lands as its own commit with **zero content change** and `make test` green on both sides, and the
release-tree boundary gets an explicit test that changing either plugin leaves the other's package
byte-identical.

### D4: Two configs split by trust, strictly parsed, never shell-sourced

The original single shell-sourceable file in the consuming repo was **unsound** and is replaced.
Two defects, both real:

1. **It crossed the host trust boundary.** The file was tracked in the very repo the unattended
   agent can write. Anything the host `source`s from there is host code execution controlled by
   repo content — a branch, or the loop itself, could inject shell syntax, rewrite the executor
   command, or *weaken the control-plane deny globs* that are supposed to constrain it.
2. **The two readers would silently disagree.** `systemd EnvironmentFile=` is not a shell parser:
   it does no command substitution, no `$VAR` expansion, no quoting-driven word splitting. A file
   that `source` interprets one way and systemd another produces different effective values for
   the same key with no error anywhere.

The replacement splits by *who is trusted to set it*:

- **Host config — operator-owned, outside the consumed repo.** Everything selecting what executes
  on the host: workspace/bot-checkout path, executor command, agent binary and settings path,
  model identifiers, timeouts, and the **baseline** control-plane deny globs. The unattended agent
  cannot write this path.
- **Project config — repo-owned, tracked in the consumer.** Inert descriptors only: repo slug,
  trunk branch, gate command, branch-name pattern, label overrides, tracker visibility, report
  sink. No value here selects a host binary or path.

Both use one restricted, strictly-parsed grammar: `KEY=VALUE`, one pair per line, no
substitution, no expansion, no interpolation, unknown keys rejected. This is deliberately the
*intersection* of what systemd accepts and what a strict reader can parse, so parity is
structural rather than hoped for. Nothing is ever `source`d.

**Deny globs are additive-only.** The effective control-plane deny list is the union of the
operator baseline and any repo additions. A repo can broaden the restriction on itself; it can
never narrow one. This closes the escalation path where editing a tracked file relaxes the hook
meant to police that same tree.

Before privileged use the host validates ownership and permissions of the host config and refuses
if either is unsafe. Retaining the `DRAIN_*` key names keeps the extracted supervisor's diff
confined to deleted defaults.

*Alternatives considered.* A single strictly-parsed file with no trust split — still lets repo
content set the executor command. Signing the repo file — key management for no gain over simply
keeping host settings out of the repo. A block in the consumer's `CLAUDE.md` (the
`spec-driven-onboard` pattern) — readable by skills, meaningless to systemd. Plugin-level
settings — invisible to the units and not per-repo.

### D12: Concurrency is a specified protocol, not an emergent property

The one-issue-per-invocation rule bounds a *single* run and says nothing about two runs. Because
the schedule fires repeatedly and an operator can invoke by hand, two invocations can select the
same opt-in issue before either advances its labels — producing duplicate branches, duplicate
pull requests, or two processes mutating one isolated checkout.

The design therefore specifies a **per-repository host lock** taken before any claim, and an
**atomic claim protocol** with explicit stale-claim recovery. This is partly a formalization: the
extracted system already claims via an in-flight label and already distinguishes a crashed run's
stale claim (label present, no pull request ever) from a human-rejected fix (label present, pull
request closed unmerged), and `ralph-harness` carries a one-orchestrator workspace lock. What was
missing is any *requirement* — none of it was specified, and a label read-then-write is not atomic
regardless.

Recovery is defined by reconciling against observable state rather than trusting the label: branch
existence, pull-request existence and state. That makes the restart-after-pull-request-but-before-
relabel window recoverable instead of ambiguous.

### D13: The scrub is a threat model with layers, not an absolute guarantee

The original claim — whole-repo scan, no exemptions, leakage impossible — could not be
implemented as stated, for a reason worth recording: **the pattern list is itself tracked
content.** A pattern that literally spells a private hostname makes the pattern file trip its own
check. Bootstrapping around that by exempting the pattern file reintroduces the allowlist the
decision was trying to avoid.

The resolution keeps the whole-repo scope but changes what lives in the repo:

- **No literal private value is ever stored in tracked content.** The repo holds *structural*
  patterns (absolute home-directory paths, secret-store paths, private-slug shapes, internal port
  numbers) plus a list of **salted digests** for literal private values. Matching compares token
  digests, so the literal never appears.
- **Fixtures are synthetic look-alikes**, never real values, so the fixture-matching test proves
  pattern well-formedness without importing anything sensitive.
- **A second, pattern-independent layer**: high-entropy string and known-credential-shape
  detection, which catches tokens nobody thought to list. Pattern matching alone only ever finds
  what someone already enumerated.
- **Narrow, individually justified exclusions are permitted** for test data, each requiring an
  inline reason — replacing a blanket "no allowlist" rule that the design could not honor.

What remains true and worth keeping: the check is armed before any extracted content lands, it
covers planning artifacts as well as plugin trees, and the near-miss requirement stands — an
unanchored pattern that fires on ordinary prose (the earlier `archi` / "architecture" collision)
must fail its own test, because a noisy check gets disabled and then protects nothing.

*Alternative considered.* Keeping the absolute guarantee and hiding patterns in an untracked
operator file only. Rejected: a check whose rules live nowhere in the repo cannot be reviewed,
and a fresh clone would silently scan for nothing. Digests give reviewability without disclosure.

### D5: `nightly-upgrade` as its own skill, not an extension of `/ralph-upgrade`

`/ralph-init` writes a tracked provenance manifest (`{template_version, files:{path:sha256}}`)
letting `/ralph-upgrade` distinguish pristine-since-scaffold files from operator-customized
ones. `nightly-onboard` reuses that pattern with its own manifest, and a sibling
`nightly-upgrade` consumes it.

*Alternative considered:* teach `/ralph-upgrade` about a second plugin's config channel.
Rejected because the existing `config-upgrade` capability is explicitly scoped to the loop
harness's own config, and the marketplace split exists precisely so the two plugins version
independently. Cross-plugin coupling would mean a `gh-nightly` config change could only ship
via a `ralph-harness` release — reintroducing the linkage the split removes.

### D6: The scrub gate lands first and covers the whole repo

`make scrub-check` is committed and wired into CI and the pre-commit hook **before** any
extracted content arrives, so no unscrubbed content is ever committed even transiently.

It scopes to the **entire repo**, including `openspec/` and `docs/`, rather than only
`plugins/**`. Consequence, adopted deliberately: planning artifacts refer to "the operator's
project" generically instead of naming private repos, hosts or trackers. An allowlist that
exempted planning directories would rot into the hole it was meant to bound.

Institutional narratives are **kept**. The incident that motivated systemd owning the loop's
lifetime — an agent backgrounded the loop inside its own turn, the turn ended, the cgroup tore
down and killed the loop ~98s in while reporting success — carries no secret and is the reason
the architecture is shaped this way. Dates and symptoms stay; hostnames and repo slugs go.

### D7: `background-explorer` ships with the plugin

`nightly-explore` cannot run without it, and it is already project-agnostic. Vendoring it
makes the plugin self-sufficient. `spec-driven-workflow` and `glossary` are referenced only as
guidance and are declared optional companions instead.

### D8: `nightly-doctor` verifies *enabled*, not *installed*

Grounded in a real failure: a timer existed, was `disabled`, and an issue class sat unworked
for multiple nights with no signal anywhere. Presence checks would have passed. The skill also
verifies token validity, loop image existence, and bot-checkout cleanliness — the other
preconditions whose silent absence produces a quiet no-op rather than an error.

### D9: Naming — a `nightly-*` family

Drop the product prefix; name the unattended chain `nightly-triage` / `nightly-explore` /
`nightly-drain` / `nightly-review` and the lifecycle skills `nightly-onboard` /
`nightly-doctor` / `nightly-upgrade`. Operator-present GitHub skills keep plain names
(`pr-review-response`, `followup-issue`, `resolve-parked`, `weekly-report`, `track-work`)
because they are useful with no scheduler installed at all.

### D10: Report sinks become pluggable; the personal plumbing goes to `extras/`

`weekly-report` and `track-work` keep their generic mechanism — assemble a quantified,
skip-level-framed report — with a file sink as the default and a task-tracker sink as one
option. The operator's specific upload and mail plumbing moves to `extras/`, this repo's
established unsupported directory.

### D11: Acceptance is fault-path coverage; the live night is a canary on top

A single successful night proves only the happy path. It does not exercise an empty queue, a
bounced candidate, a halted executor, a start-timeout kill, cleanup after a signal, public-tracker
redaction, a disabled timer, upgrade drift, overlapping invocations, or rollback — which is
precisely the set of expensive paths this design exists to get right. Releasing on one green night
could ship a system whose failure handling is entirely broken.

Acceptance is therefore three things, in order:

1. **A requirement-to-test traceability matrix.** Every requirement in the six capability specs
   maps to at least one test or an explicit, reasoned waiver. An unmapped requirement blocks
   release — that is what makes the specs falsifiable rather than decorative.
2. **Fault-injected end-to-end runs** for the supervision and recovery invariants: empty queue,
   candidate bounce, executor halt, timeout kill, signal mid-run, overlapping invocation, stale
   claim, restart between pull-request creation and relabeling, unreachable report sink, and a
   rehearsed rollback. These are scoped to supervision/recovery rather than "every requirement"
   because that is where silent failure is both likely and costly, and because the five inherited
   suites already give these paths a harness.
3. **Multiple live scheduled cycles**, then release. The live night stays — it catches integration
   reality no fixture reproduces — but as the last gate, not the only one.

*Alternative considered.* Fault-inject every requirement across all six capabilities. Rejected as
disproportionate: the operator-present skills fail visibly in front of a human, so their failure
modes are self-revealing in a way an unattended 02:00 path is not.

## Risks / Trade-offs

- **Relocation churn breaks the green suite** → land the move as a content-free commit,
  `make test` green immediately before and after; no genericization in the same commit. Or take
  the zero-churn alternative (D3).
- **A version bump is forgotten and `/plugin update` silently no-ops** → the repo already
  documents this hazard for one plugin; it now applies twice, independently. Add a conformance
  check asserting each `plugin.json` version differs from the last released tag when its own
  tree changed.
- **chezmoi copies shadow the plugin skills** → the migration is `chezmoi forget` **and**
  delete for all ten moved skills, verified by their absence from `~/.claude/skills/`. A
  half-migration is worse than none: the dotfile copy wins silently and diverges.
- **Development friction from cache staleness** → the Skill tool loads the cached plugin, so
  edits to `plugins/gh-nightly/skills/` are invisible until the cache refreshes. Document the
  refresh step in the contributor notes; do not let a stale cache be misread as a broken skill.
- **The scrub gate false-negatives on a token nobody listed** → keep the pattern list in one
  file with a test that asserts each pattern actually matches a fixture, so a typo'd pattern
  cannot silently match nothing.
- **Extracted supervisor tests may encode project assumptions** → run them unchanged first to
  establish a baseline, and only then generalize; a suite that goes green *after* being edited
  proves nothing about the extraction.
- **Two coexisting copies during migration** → the private repo keeps serving the live nightly
  until cutover. Both must not run the same timers on the same host; cutover disables the old
  units in the same step that installs the new ones.
- **systemd-only excludes non-Linux operators** → accepted, consistent with the repo's stated
  scope.
- **Repo content escalating into host execution** → the trust split in D4: host-execution settings
  live outside the consumed repo, nothing is `source`d, deny globs are additive-only, and ownership
  and permissions are validated before privileged use. Tested with injection strings, not just
  well-formed input.
- **The two config readers diverging silently** → one restricted grammar that is the intersection
  of what systemd and a strict reader both accept, with an explicit parser-parity test asserting
  both readers derive identical values from the same file.
- **Two invocations claiming the same issue** → per-repository host lock plus an atomic claim
  protocol, with recovery reconciled against branch and pull-request state rather than the label
  alone (D12).
- **The scrub's pattern list leaking the values it protects** → structural patterns plus salted
  digests and synthetic fixtures, so no literal private value is ever tracked (D13).
- **Unlisted secrets passing a pattern-only scrub** → a second, pattern-independent entropy and
  credential-shape layer; pattern matching alone only finds what someone enumerated.
- **An incompatible plugin pair discovered at 02:00** → versioned prerequisites enforced at
  onboarding, health-check and upgrade time, with version-skew tests (D1).
- **Requirements that no test maps to** → the traceability matrix gates release; an unmapped
  requirement is a release blocker, not a footnote (D11).

## Migration Plan

1. Scrub gate — structural patterns, salted digests, synthetic fixtures, entropy layer — wired to
   CI and pre-commit. Nothing extracted yet, so the gate is armed before it has anything to catch.
2. Relocation to disjoint plugin roots as a content-free commit; `make test` green both sides;
   release-tree boundary test proving each plugin's package excludes the other.
3. `gh-nightly` skeleton: `plugin.json`, marketplace entry, empty skills/supervisor trees.
   Verify the marketplace re-resolves and both plugins install and update independently.
4. Supervisor extraction. Copy scripts and the five suites verbatim; run them to establish a
   baseline; then delete project defaults so config becomes required; suites green again. Add the
   run lock and atomic claim protocol with their concurrency tests.
5. Skills genericization, ten skills, proper nouns → config reads. Taxonomy untouched.
6. Config contract — the host/project trust split, the restricted grammar, the parser-parity and
   injection tests, the typed key schema with its per-consumer dependency table — plus
   `nightly-onboard` / `nightly-doctor` / `nightly-upgrade`, the provenance manifest, and a golden
   reference for the rendered output.
7. Traceability matrix: every requirement mapped to a test or a reasoned waiver. Unmapped
   requirements block progress past this point.
8. Fault-injected end-to-end runs for the supervision and recovery invariants, including a
   rehearsed rollback.
9. Cutover: write the operator's host and project configs, install the rendered units, disable the
   private repo's units in the same step, `chezmoi forget` + delete the ten moved skills.
10. Multiple live scheduled cycles. Then bump both `plugin.json` versions and release.

**Rollback:** through step 8 nothing user-facing has changed — revert the branch. After step 9,
rollback is re-enabling the private repo's units and `chezmoi apply` to restore the dotfile
skills. The rollback is *rehearsed* in step 8 rather than first attempted under pressure, and the
private copies stay in place until the live cycles in step 10 have passed.

## Open Questions

- **`weekly-report` and `track-work` — generalize or leave behind?** Both carry the most
  personal configuration (report framing, tracker project, upload destination) and the least
  mechanism. Shipping them with a file-only default sink is cheap; shipping them at all may be
  scope that earns nothing.
- **Does `nightly-drain`'s Loop-1/wrap-up handoff belong in the spec or stay an
  implementation detail?** The split exists because a headless agent turn cannot outlive
  itself; that constraint is real and general, but the JSON handoff shape is not obviously a
  public contract.
