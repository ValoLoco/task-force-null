# Model Inventory

Bootstrap only: run `scripts/detect-models.sh` to detect harness, probe endpoints, and populate tables below. This template ships **zero hardcoded model names**.

Last updated: (not yet bootstrapped)

## Harness

| field | value |
|-------|-------|
| harness | |
| detected_at | |

## Inventory

| model_id | provider | capabilities | context_tokens | cost_tier | latency_note | reliability_note |
|----------|----------|--------------|----------------|-----------|--------------|------------------|
| | | | | | | |

Capability tags use comma-separated values such as `code`, `reasoning`, `tool_use`, `long_context`, `vision`, `fast_qa`.

Cost tier is `1` (lowest) through `5` (highest). Router uses cost only when fit scores tie.

## Role Profile Defaults

Capability expectations per operator (bindings filled by `detect-models.sh`):

| role | required_capabilities | preferred_context |
|------|----------------------|-------------------|
| command | reasoning,long_context | 128000 |
| lead | reasoning,tool_use | 64000 |
| recon | fast_qa,tool_use | 32000 |
| builder | code,tool_use | 64000 |
| medic-qa | fast_qa,reasoning | 32000 |
| comms | fast_qa | 16000 |

## Learned Overrides

Command and operators promote rows here after observed outcomes (Rule-of-Two for doctrine-level policy; single successes may log locally first).

| task_pattern | model_id | outcome | notes |
|--------------|----------|---------|-------|
| | | | |

Outcome should be `success`, `partial`, or `fail`. Router adds a fit bonus for `success`, penalty for `fail` when patterns match.

## Bootstrap Instructions

1. Run `./scripts/detect-models.sh --slug <active-slug>` after deploy or on a schedule.
2. Review `brain/models.md` and optional `missions/<slug>/squad.env` `MODEL_BIND_*` keys.
3. Route tasks with `python3 scripts/router.py "<task>"` and inspect `fit_score` and candidates.
4. Record friction in AARs; update Learned Overrides when a model clearly wins or loses for a task class.