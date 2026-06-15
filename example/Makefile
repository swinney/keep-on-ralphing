# Worked example: consumer Makefile for "Acme Widgets". IMAGE/RUNTIME match
# example/ralph.conf (acme-loop / podman).

IMAGE      ?= acme-loop
RUNTIME    ?= podman
BASE_IMAGE ?= ralph-base:v1
WORKSPACE  := $(CURDIR)
CLAUDE_DIR := $(WORKSPACE)/.ralph/claude-home

RUN_FLAGS := \
  --userns=keep-id \
  -e RALPH_MODEL \
  -v $(WORKSPACE):/workspace \
  -v $(CLAUDE_DIR):/home/claude/.claude

.PHONY: help hooks build login loop loop-once shell clean

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

login:
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-login $(IMAGE) claude login

loop: hooks
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE) $(IMAGE) ralph.sh

loop-once: hooks
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-once $(IMAGE) ralph.sh --once

shell:
	@mkdir -p $(CLAUDE_DIR)
	$(RUNTIME) run --rm -it $(RUN_FLAGS) --name $(IMAGE)-shell $(IMAGE)

clean:
	$(RUNTIME) rmi $(IMAGE) || true
