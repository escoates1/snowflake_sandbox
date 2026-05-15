# snowflake_sandbox — project context

A personal learning sandbox for Snowflake, dbt, and CI/CD. The guiding rule: **all Snowflake objects are created via code, never via Snowsight** (the one exception is registering the RSA public key for key-pair auth, which is a one-time account operation).

## Stack

- **Python** 3.12, managed with `uv`
- **Snowflake** — single trial account with `DEV` and `PROD` databases
- **dbt-snowflake** — dbt project lives in `dbt/`
- **GitHub Actions** — CI on PRs, CD on merge to main
- **Ruff** — linting and format checking

## Architecture decisions

- One Snowflake account, two databases (`DEV`, `PROD`) with matching schemas (`RAW`, `STAGING`, `MARTS`)
- Key-pair auth for all non-interactive connections (CI/CD and local dev after initial setup)
- `dbt/profiles.yml` is committed — it contains no secrets, reads everything from env vars
- Run dbt commands with `--profiles-dir dbt` (or `--profiles-dir .` from inside `dbt/`) so the committed profile is used rather than `~/.dbt/profiles.yml`
- `ruff` is a dev dependency (`[dependency-groups]` in pyproject.toml), installed by default with `uv sync`

## Repository layout

```text
scripts/setup_snowflake.py   — provision Snowflake objects from scratch (idempotent)
dbt/                         — dbt project
  dbt_project.yml
  profiles.yml               — env-var-based, safe to commit
  packages.yml
  models/                    — empty; add staging/ and marts/ subdirs as you build
.github/workflows/
  ci.yml                     — lint (ruff) + dbt compile against DEV; runs on every PR
  cd.yml                     — dbt run + dbt test against PROD; runs on merge to main
.env.example                 — credential template; copy to .env (gitignored)
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | Account identifier (`orgname-accountname`) |
| `SNOWFLAKE_USER` | Snowflake username |
| `SNOWFLAKE_PASSWORD` | Used only during initial setup before key-pair is configured |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | Path to `rsa_key.p8` (local) or `/tmp/rsa_key.p8` (CI) |
| `SNOWFLAKE_WAREHOUSE` | Defaults to `COMPUTE_WH` |
| `DBT_TARGET` | `dev` or `prod`; defaults to `dev` |

## GitHub Actions secrets required

`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY` (base64-encoded `rsa_key.p8`)

## Progress

### Done
- [x] Snowflake environment provisioning script (`scripts/setup_snowflake.py`)
- [x] dbt project scaffold with env-var-based profiles
- [x] CI workflow: ruff lint + dbt compile against DEV (on PR to main)
- [x] CD workflow: dbt run + dbt test against PROD (on merge to main)
- [x] Key-pair auth setup guide in README (PowerShell + bash)
- [x] Branch protection instructions in README

### Next / ideas to explore
- [ ] Complete first-time setup: run `setup_snowflake.py`, configure key-pair, add GitHub secrets, enable branch protection
- [ ] Build first dbt model — a simple staging model over a raw source
- [ ] Add dbt sources (`sources.yml`) and generic tests (`not_null`, `unique`)
- [ ] Load sample data into `DEV.RAW` to have something to model
- [ ] Explore dbt snapshots (SCD Type 2)
- [ ] Add `dbt test` to the CI workflow once models exist
- [ ] Explore Snowflake features: dynamic tables, streams, tasks
