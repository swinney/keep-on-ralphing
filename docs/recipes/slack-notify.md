# Recipe: get pinged when a Ralph loop needs a human (Slack)

Developing async — kick off a loop and walk away — is only responsible if the loop can **summon you
back** when it needs a decision. The harness ships the *seam*, not an integration: set `RALPH_NOTIFY_CMD`
to a command and the **runner** (never the agent) invokes it as `<cmd> <event> <reason>` at every
needs-human halt. This recipe wires that seam to a Slack incoming webhook with a few lines of `curl` —
no vendored Slack SDK, no open port.

## The events

The runner fires the notifier once, at the halt, with one of:

| `event` | When | `reason` |
|---|---|---|
| `stop` | the agent wrote a stop reason to `STATUS.md` (work done / it decided to stop) | the `STATUS.md` line |
| `stall` | `RALPH_MAX_STALLS` consecutive no-commit turns | the halt summary |
| `review-exhausted` | the review gate still failing after `RALPH_REVIEW_MAX_ROUNDS` | the halt summary |
| `blocked` | the agent wrote a NEW question to `docs/questions.md` (a decision the specs don't cover) | the question line |

`blocked` is the sharp one: without it, a single ambiguity silently burns `RALPH_MAX_STALLS` turns before
the loop halts with no signal. With it, the loop stops the moment the question is written and pings you.

## The notifier script

```sh
#!/usr/bin/env bash
# notify-slack.sh — wire via RALPH_NOTIFY_CMD=/path/to/notify-slack.sh
# Invoked by the runner as: notify-slack.sh <event> <reason>
# The webhook is read from the ENV (SLACK_WEBHOOK_URL), never passed on the
# command line (argv is visible in `ps`).
set -euo pipefail
event=${1:?event}; reason=${2:-}
: "${SLACK_WEBHOOK_URL:?set SLACK_WEBHOOK_URL in the environment}"

text=":robot_face: *ralph* needs a human — \`${event}\`
${reason}"

# Slack expects a JSON body; build it with a tiny here-doc so quotes in $reason
# are escaped. (jq -Rs would also work if you have jq.)
payload=$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1]}))' "$text")
curl -sS -X POST -H 'Content-Type: application/json' -d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null
```

Make it executable (`chmod +x notify-slack.sh`) and set:

```sh
RALPH_NOTIFY_CMD="/path/to/notify-slack.sh"   # in ralph.conf or the environment
```

`RALPH_NOTIFY_CMD` is **startup-validated**: if it is set but not executable, the loop refuses to start
(so you find out before walking away, not at the halt). Notification is **non-fatal** — a notifier that
errors, hangs, or is slow is killed after `RALPH_NOTIFY_TIMEOUT` (default 30s) and ignored; it never
changes the loop's exit code or flow.

## Wiring the webhook into the container

The runner runs **inside** the container, so the notifier and its secret must reach the container env —
exactly like the forwarded `GH_TOKEN`. Forward it the same way in the consumer `Makefile`'s run flags:

```make
export SLACK_WEBHOOK_URL ?= $(shell cat ~/.config/ralph/slack-webhook 2>/dev/null)
RUN_FLAGS := ... -e SLACK_WEBHOOK_URL -e RALPH_NOTIFY_CMD ...
```

> **Security — the webhook is a runner-plane secret of `GH_TOKEN` sensitivity.** Because the runner
> invokes the notifier in the container, `SLACK_WEBHOOK_URL` (and `RALPH_NOTIFY_CMD`) are present in the
> container env, where the `claude` turn — started from the inherited env — can read them. This is the
> **same exposure plane as `GH_TOKEN`**, which the harness already forwards. "Agent-blind" here is a
> *behavioral* contract (the runner owns all git/gh/network work; the agent does not), **not** env
> isolation. Treat the webhook with the same care as `GH_TOKEN`: a rotatable, low-scope incoming webhook,
> not a high-privilege token. Full agent env-scrubbing (which would also have to cover `GH_TOKEN`) is out
> of scope for the harness today.

## Zero-dependency alternative: a PR comment

If you don't want a webhook at all, the runner is already `gh`-authenticated, so a notifier that drops a
comment on the loop's PR needs no new secret:

```sh
#!/usr/bin/env bash
# notify-pr.sh — RALPH_NOTIFY_CMD=/path/to/notify-pr.sh
set -euo pipefail
event=${1:?}; reason=${2:-}
gh pr comment --body ":robot_face: ralph needs a human — \`${event}\`: ${reason}" 2>/dev/null || true
```

This reuses the existing `GH_TOKEN` plane (no extra secret) but only reaches you if you watch the PR —
the Slack webhook is the better "pull me back" channel.
