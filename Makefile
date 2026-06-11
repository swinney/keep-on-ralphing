# keep-on-ralphing — build the base sandbox image and run the kit's tests.
# Linux + podman, single architecture.

BASE_IMAGE ?= ralph-base:v1
RUNTIME    ?= podman

.PHONY: help build-base test

help:
	@echo "Targets:"
	@echo "  build-base   build the $(BASE_IMAGE) sandbox image (UID/GID matched to you)"
	@echo "  test         run the kit test suite (until_reset unit + ralph.sh runner)"

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
