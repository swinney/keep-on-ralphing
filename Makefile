# keep-on-ralphing — build the base sandbox image and run the kit's tests.
# Linux + podman, single architecture.

BASE_IMAGE ?= ralph-base:v1
RUNTIME    ?= podman

.PHONY: help build-base test smoke-base

help:
	@echo "Targets:"
	@echo "  build-base   build the $(BASE_IMAGE) sandbox image (UID/GID matched to you)"
	@echo "  test         run the kit test suite (until_reset unit + ralph.sh runner)"
	@echo "  smoke-base   verify the BUILT $(BASE_IMAGE) has the runner's tools (gh/git/ralph.sh)"

# Registry-free local build. The build context is base/, so the Containerfile's
# `COPY scripts/...` resolves to base/scripts/. Match host UID/GID so files the
# in-container user writes under a bind mount are host-owned.
build-base:
	$(RUNTIME) build \
	  --build-arg USER_UID=$$(id -u) \
	  --build-arg USER_GID=$$(id -g) \
	  -t $(BASE_IMAGE) -f base/Containerfile base

test:
	bash base/tests/run.sh

# Smoke-test the BUILT image. `make test` stubs `gh` and runs without the image, and
# CI does not build the image, so neither covers image contents — this does. Run it
# after `build-base`. Asserts the runner's tools are on PATH inside $(BASE_IMAGE).
smoke-base:
	@$(RUNTIME) run --rm $(BASE_IMAGE) sh -c '\
	  for t in gh git ralph.sh until_reset.py; do \
	    command -v $$t >/dev/null 2>&1 || { echo "smoke-base FAIL: $$t missing from $(BASE_IMAGE)"; exit 1; }; \
	  done; echo "smoke-base OK: gh=$$(gh --version | head -1), git, ralph.sh, until_reset.py present"'
