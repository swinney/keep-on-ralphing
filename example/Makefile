# Worked example: consumer Makefile for "Acme Widgets". IMAGE/RUNTIME match
# example/ralph.conf (acme-loop / podman).

IMAGE      ?= acme-loop
RUNTIME    ?= podman
BASE_IMAGE ?= ralph-base:v1
WORKSPACE  := $(CURDIR)
CLAUDE_DIR := $(WORKSPACE)/.ralph/claude-home

# The review gate (ON by default) runs `gh` in the runner inside the container, so
# forward a host-derived token as GH_TOKEN. `export` + `-e GH_TOKEN` keeps it out
# of argv. Not needed when RALPH_REVIEW_GATE=0.
export GH_TOKEN ?= $(shell gh auth token 2>/dev/null)

RUN_FLAGS := \
  --userns=keep-id \
  -e RALPH_MODEL \
  -e GH_TOKEN \
  -v $(WORKSPACE):/workspace \
  -v $(CLAUDE_DIR):/home/claude/.claude

.PHONY: help hooks build check-base login loop loop-once shell clean

help:
	@echo "Targets:"
	@echo "  hooks      install the pre-commit gate hook (git config core.hooksPath hooks)"
	@echo "  build      build $(IMAGE) FROM $(BASE_IMAGE) (run keep-on-ralphing 'make build-base' first)"
	@echo "  login      one-time: authenticate Claude Code"
	@echo "  loop       run the Ralph Loop in the foreground (Ctrl-C to stop)"
	@echo "  loop-once  run exactly one turn"
	@echo "  shell      interactive shell in the container"
	@echo "  clean      remove $(IMAGE)"
	@echo "  (status:   use the /ralph-status skill in Claude Code)"

# Point git at the tracked hooks/ dir so the pre-commit gate is active in the
# loop container (which shares /workspace/.git). Idempotent — a prerequisite of
# build/loop/loop-once so it is never forgotten. NOTE: core.hooksPath overrides
# ALL of .git/hooks; if you have other hooks, consolidate them into hooks/.
hooks:
	@git config core.hooksPath hooks

build: hooks
	$(RUNTIME) build \
	  --build-arg USER_UID=$$(id -u) \
	  --build-arg USER_GID=$$(id -g) \
	  -t $(IMAGE) -f Containerfile .

# Refuse to run a loop image built on a SUPERSEDED base. $(IMAGE) inherits
# $(BASE_IMAGE)'s org.ralph.* LABELs; if the base-version OR the baked UID/GID
# differ from the base image now on the machine, the base was rebuilt without
# `make build` here — so the loop would run a stale runner or wrong-owner image.
# Detect + instruct only (rebuilding the BASE needs the plugin; that is
# /ralph-build-base's job). Skips silently if either image is unstamped (legacy)
# or the runtime is absent.
check-base:
	@command -v $(RUNTIME) >/dev/null 2>&1 || exit 0; \
	  fmt='{{ index .Config.Labels "org.ralph.base-version" }}:{{ index .Config.Labels "org.ralph.user-uid" }}:{{ index .Config.Labels "org.ralph.user-gid" }}'; \
	  img=$$($(RUNTIME) image inspect $(IMAGE) --format "$$fmt" 2>/dev/null); \
	  base=$$($(RUNTIME) image inspect $(BASE_IMAGE) --format "$$fmt" 2>/dev/null); \
	  if [ -n "$${img%%:*}" ] && [ -n "$${base%%:*}" ] && [ "$$img" != "$$base" ]; then \
	    echo "ERROR: $(IMAGE) was built on a stale/mismatched $(BASE_IMAGE) ($$img != $$base)."; \
	    echo "       Run 'make build' to rebuild it on the current base before looping."; \
	    exit 1; \
	  fi

login:
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-login $(IMAGE) claude login

# Single-shell wrapper for `make loop` so one teardown trap can span the whole run
# (Make runs each recipe LINE in its own shell). With RALPH_DASHBOARD=1 it extracts
# the host-side dashboard viewer FROM the loop image (the base image bakes it), runs
# it with HOST python3 against the host-native .ralph/, and traps teardown to kill it
# + remove the temp file. The loop container stays FOREGROUND and port-free, so its
# SIGINT -> exit 130 stop path is unchanged (only the viewer is backgrounded).
# Precedence for the flag: env > ralph.conf > default(0). Dashboard is OFF by default.
define RALPH_LOOP_RUN
set -e
rt="$$1"; img="$$2"; ws="$$3"; dash_env="$$4"; shift 4
sd="$$ws/.ralph"
dash="$$dash_env"
if [ -z "$$dash" ] && [ -f "$$ws/ralph.conf" ]; then
  dash=$$(. "$$ws/ralph.conf" 2>/dev/null; printf '%s' "$${RALPH_DASHBOARD:-}")
fi
[ -z "$$dash" ] && dash=0
dpid=""; dtmp=""
if [ "$$dash" = 1 ]; then
  if command -v python3 >/dev/null 2>&1; then
    dtmp=$$(mktemp)
    if cid=$$("$$rt" create "$$img" 2>/dev/null) \
       && "$$rt" cp "$$cid:/usr/local/bin/ralph_dashboard.py" "$$dtmp" 2>/dev/null; then
      "$$rt" rm "$$cid" >/dev/null 2>&1 || true
    fi
    if [ -s "$$dtmp" ]; then
      python3 "$$dtmp" --state-dir "$$sd" --workspace "$$ws" --runtime "$$rt" \
        --container "$$img" --tasks "$$ws/tasks.md" & dpid=$$!
    else
      echo "ralph: could not extract the dashboard viewer from $$img - skipping dashboard" >&2
    fi
  else
    echo "ralph: RALPH_DASHBOARD=1 but host python3 not found - skipping dashboard" >&2
  fi
fi
trap '[ -n "$$dpid" ] && kill "$$dpid" 2>/dev/null; [ -n "$$dtmp" ] && rm -f "$$dtmp"' EXIT
"$$rt" run --rm -it "$$@" --name "$$img" "$$img" ralph.sh
endef
export RALPH_LOOP_RUN

loop: hooks check-base
	@mkdir -p $(CLAUDE_DIR)
	@bash -c "$$RALPH_LOOP_RUN" ralph_loop $(RUNTIME) $(IMAGE) "$(WORKSPACE)" "$${RALPH_DASHBOARD:-}" $(RUN_FLAGS)

loop-once: hooks check-base
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-once $(IMAGE) ralph.sh --once

shell:
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-shell $(IMAGE)

clean:
	$(RUNTIME) rmi $(IMAGE) || true
