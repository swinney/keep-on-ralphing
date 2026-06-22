## 1. Test harness (write first)

- [x] 1.1 Extend the stub-`claude` test scaffold so a turn can emit chosen stdout, a non-zero exit, and a usage-limit message — enough to assert log capture and control-signal preservation without a real agent
- [x] 1.2 Add `base/tests/test_live_log.sh`; wire it into `base/tests/run.sh` and the CLAUDE.md single-slice list

## 2. Line-prefixer helper (base image)

- [x] 2.1 Add `base/scripts/ralph_prefix.py`: read stdin line-by-line, write `"<ISO-8601> turn=<n> | <line>"` to stdout with per-line flush; takes the turn number as argv; Python 3.7+-safe (mirror the `until_reset.py` portability note)
- [x] 2.2 Bake it onto PATH in `base/Containerfile` next to `until_reset.py`
- [x] 2.3 Unit-test the prefixer (pytest, alongside `test_until_reset.py`): correct prefix shape, line buffering, and that it passes content through unchanged after the prefix

## 3. Aggregate log in the runner (`base/scripts/ralph.sh`)

- [x] 3.1 Resolve `RALPH_LIVE_LOG` (default `1`) and the `live.log` path under `RALPH_STATE_DIR/log/`, honoring `environment > ralph.conf > default`; bash 3.2-safe
- [x] 3.2 Add a `narrate()` helper: echo to the terminal as today AND append one turn-prefixed line to `live.log` (shell-side formatter, same prefix shape as the Python helper); convert the existing terminal-only `echo "ralph: …"` / review-gate / stall-halt lines to `narrate`
- [x] 3.3 Add the prefixer as a `tee` **fan-out** (process substitution) so a copy stays on stdout: `… | tee "$log" >(python3 "$script_dir/ralph_prefix.py" "$turn" >> "$live")` — invoke via `$script_dir` (matching `until_reset.py`, not a bare name or `/usr/local/bin`); VERIFY `turn_ec=${PIPESTATUS[0]}` still captures the agent stage
- [x] 3.4 Confirm the usage-limit grep still reads the raw `turn-N.txt` (unprefixed) so detection is byte-identical to today
- [x] 3.5 Gate all `live.log` writes on `RALPH_LIVE_LOG=1` so `=0` reproduces today's behavior exactly

## 4. Tests pass (control-signal preservation is the critical case)

- [x] 4.1 Test: `live.log` is created, is append-only across ≥2 turns, and contains BOTH a `narrate` line and agent output
- [x] 4.2 Test: every `live.log` line carries `turn=<n>` and a parseable ISO-8601 timestamp
- [x] 4.3 Test: a non-zero agent exit is still detected (PIPESTATUS preserved) and a usage-limit turn still pauses/replays (not a stall) with the aggregate log active
- [x] 4.4 Test: `RALPH_LIVE_LOG=0` writes no `live.log` and leaves `turn-N.txt`/`status.jsonl` unchanged
- [x] 4.5 Test: with `RALPH_LIVE_LOG=1` and NO aggregator, agent output still reaches the runner's stdout (the terminal / `podman logs` stream is not blanked by the fan-out) and `turn-N.txt` is byte-identical to the pre-change run

## 5. Config surface and golden reference

- [x] 5.1 Document `RALPH_LIVE_LOG` (and the `live.log` path) in `templates/ralph.conf.example`, default-on, inert-when-`0`
- [x] 5.2 Keep `example/` (Acme Widgets) in sync — `ralph.conf` and any rendered output
- [x] 5.3 (Decide per design Open Questions) Optionally have `skills/ralph-status/SKILL.md` surface the `live.log` path + a `tail -f` hint

## 6. Vector recipe doc (kit reference)

- [x] 6.1 Add `docs/recipes/vector-console.md` with **two `file` sources** (or one source + a path-keyed conditional), NOT a single blanket parse: `status.jsonl` → `remap` `. = parse_json!(.message)`; `live.log` → text (optionally lift the `turn=<n>` prefix), never `parse_json!`; a shared transform derives `.project` from `.file`; a `console` sink + `vector top` for the zero-backend realtime view
- [x] 6.2 Note the one-line sink swap to `elasticsearch`/`loki`/`datadog_logs`, the multi-loop glob+`project` pattern, and that the kit ships NO aggregation code (harness-as-source); mention the future `RALPH_LOG_SINK` push seam as the no-host-shipper fallback
- [x] 6.3 Link the recipe from `README.md` (and note it under the relevant CLAUDE.md section)

## 7. Release and validation

- [x] 7.1 `make test` green, including the new prefixer unit test and `test_live_log.sh`
- [x] 7.2 `make build-base` then `make smoke-base` — confirm `ralph_prefix.py` is baked into the image alongside `until_reset.py` (same dir, invoked via `$script_dir`) and is executable
- [x] 7.3 Two-channel release: bump `.claude-plugin/plugin.json` (semver) AND flag the base-image rebuild requirement in the change notes / CLAUDE.md release checklist
- [x] 7.4 `openspec validate log-streaming --strict` passes
