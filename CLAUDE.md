# snowflake_sandbox — project context

A personal learning sandbox for Snowflake, Terraform, dbt, and CI/CD. The guiding rule: **all Snowflake objects are created via code, never via Snowsight** (the one exception is registering the RSA public key for key-pair auth, which is a one-time account operation).

## Model Persona

You are a data engineering teacher. When answering a question or giving a solution, explain alternative approaches with a recommended answer. Help me understand each step to enhance my overall understanding. Try to answer concisely without skipping any important information.

Do not make code changes directly in the project unless asked explicitly to do so. Instead, output the answers in the terminal and let me implement them myself.

Keep the CLAUDE.md file up to date as the project evolves. Add all architectural decisions to the main README.md file so they are readable from the GitHub repo.

## Stack

- **Python** 3.12, managed with `uv`
- **Snowflake** — single trial account (Standard Edition) with `DWH_DEV`, `DWH_TEST`, and `DWH_PROD` databases
- **Terraform** — provisions Snowflake account objects (`snowflakedb/snowflake` provider `~> 2.17`); project lives in `terraform/`; state in HCP Terraform
- **dbt-snowflake** — dbt project lives in `dbt/`
- **GitHub Actions** — CI on PRs, CD on merge to main
- **Ruff** — linting and format checking

## Architecture decisions

- One Snowflake account, per-environment databases (`DWH_DEV`, `DWH_TEST`, `DWH_PROD`) with matching schemas (`RAW`, `STAGING`, `MARTS`, `PRESENTATION`, `ADMIN`).
- **Terraform provisions all account objects** (databases, schemas, roles, warehouses); dbt builds models on top. SQL/Python for objects Terraform doesn't yet manage (tables, seed DML, network rules, external access integrations, stored procedures) lives in `scripts/`, grouped by object type.
- **dbt models are layered**: sources (`_src_earthquake.yml` over `RAW.USGS_EARTHQUAKES_FDSNWS`) → **staging** (`stg_earthquake__event_classification`, `stg_earthquake__location`, `stg_earthquake__alert_status`, `stg_earthquake__seismic_event` — light select/rename, one per downstream dim/fact) → **marts**, a star schema (`dim_date`, `dim_event_classification`, `dim_location`, `dim_alert_status`, `fact_seismic_event`) → **presentation**, a 1:1 view over every mart (e.g. `fact_seismic_event_view`), which is what `ANALYST` is actually granted against. Static lookups live in seeds (`magnitude_types`); `dbt_utils` supplies `date_spine`, `generate_surrogate_key`, and `accepted_range`; `dim_location` derives region/country from free-text place via `AI_EXTRACT`; `dim_location`, `dim_event_classification`, and `dim_alert_status` apply a manual SCD Type 2 pattern, `fact_seismic_event` a matching SCD Type 1 pattern. A custom `generate_schema_name` macro makes `+schema` use the configured name verbatim, so models land in `STAGING`/`MARTS`/`PRESENTATION` (not `<target>_<schema>`). Ingestion is no longer a separate manual step: an `on-run-start` hook macro (`ingest_usgc_earthquakes.sql`) calls the `INGEST_USGS_EARTHQUAKES` stored proc at the start of every `dbt build`. Generic + `dbt_utils` tests live in the `_*.yml` property files; trickier derivations (magnitude-band boundaries, alert-status flags, direction/distance regex parsing) are covered by dbt unit tests. `docs/earthquake_model.drawio` (+ its exported `docs/model/*.png`) and `docs/dbt-dag.png` document the resulting star schema and lineage.
- Terraform is structured as one directory **per environment** (`terraform/environments/{account,dev,test,prod}`) that calls shared `terraform/modules/*`. The **`account`** environment creates account-wide objects (the custom roles); **`dev`**/**`test`**/**`prod`** each create a database + warehouse and grant the roles. `account` must be applied before the database environments.
- **State lives in HCP Terraform**, one workspace per environment (org `escoates1-org`; workspaces `snowflake-sandbox-{account,dev,test}`), configured via a `cloud {}` block in each env's `versions.tf`. Workspaces use **Local execution mode** — state is stored/locked remotely, but runs happen on the local machine so the provider can read the local private-key file. (See `terraform/README.md`.)
- Terraform authenticates as a dedicated **`TERRAFORM_USER`** service account via key-pair (JWT), with roles `SYSADMIN` (objects) and `SECURITYADMIN` (roles/grants) — not the personal login. `providers.tf` declares two providers: the default (`SYSADMIN`) and an aliased `securityadmin`.
- Terraform connection values are supplied locally (Local execution mode) via a gitignored `terraform.tfvars` **or** `TF_VAR_*` environment variables; no secrets in `.tf` files. The account id splits into `organization_name` + `account_name`; HCL paths use forward slashes.
- Key-pair auth for all non-interactive connections (CI/CD and local dev after initial setup)
- `dbt/profiles.yml` is committed — it contains no secrets, reads everything from env vars; three targets (`dev`/`test`/`prod`) selected by `DBT_TARGET`, connecting role pinned via `SNOWFLAKE_ROLE` (default `ENGINEER`)
- Run dbt commands from the repo root with `--project-dir dbt --profiles-dir dbt` (or from inside `dbt/` with `--profiles-dir .`) so the committed project and profile are used rather than `~/.dbt/profiles.yml`. dbt does **not** load `.env` itself — load it with `uv run --env-file .env <dbt command>`
- `ruff` is a dev dependency (`[dependency-groups]` in pyproject.toml), installed by default with `uv sync`

## Repository layout

```text
terraform/                   — infrastructure as code for Snowflake account objects
  README.md                  — full Terraform guide (modules, HCP workspaces, apply order)
  modules/                   — reusable: database/, warehouse/, role/, grants/
  environments/
    account/                 — account-wide objects: custom roles; apply FIRST
    dev/                     — DWH_DEV + WH_DEV + grants; HCP state
    test/                    — DWH_TEST + WH_TEST + grants; HCP state
    prod/                    — DWH_PROD + WH_PROD + grants; HCP state
scripts/                     — SQL/Python for objects not yet managed by Terraform
  ddl/                       — table definitions (INGESTION_METADATA, USGS landing + staging)
  dml/                       — seed/merge data (INGESTION_METADATA config rows)
  network/                   — network rules + external access integration (USGS API egress)
  procs/                     — Python stored procedures (USGS earthquake ingestion)
dbt/                         — dbt project
  dbt_project.yml            — model + seed configs (schemas, materializations, column types)
  profiles.yml               — env-var-based, safe to commit
  packages.yml               — dbt_utils
  macros/                    — generate_schema_name override (+schema used verbatim);
                                ingest_usgc_earthquakes (on-run-start hook, calls INGEST_USGS_EARTHQUAKES)
  seeds/                     — magnitude_types.csv (magnitude code → description lookup)
  models/
    staging/                 — _src_earthquake.yml source + stg_earthquake__* staging models
                                (event_classification, location, alert_status, seismic_event)
    marts/                   — star schema: dim_date, dim_event_classification, dim_location,
                                dim_alert_status, fact_seismic_event (+ _mart__models.yml)
    presentation/             — 1:1 views over each mart, e.g. dim_location_view,
                                fact_seismic_event_view (+ _presentation__models.yml); what ANALYST is
                                actually granted against
docs/                        — data model diagrams
  earthquake_model.drawio    — editable source for the model diagrams
  dbt-dag.png                — dbt lineage graph (source → staging → marts → presentation)
  model/                     — conceptual_model.png, logical_model.png, physical_model.png (exported)
.github/workflows/
  terraform.yml              — PR (terraform/** changed): fmt/validate/plan (all envs); merge: gated
                                apply account→dev→test→prod
  ci.yml                     — PR: ruff lint + format check
  dbt.yml                    — merge only (dbt/** changed, no PR trigger): gated dbt build
                                dev→test→prod, each tied to a GitHub Environment
.env.example                 — credential template; copy to .env (gitignored)
```

## Custom roles

- **ENGINEER** — read/write across all schemas of a database (created in `account`, granted per-database in `dev`/`test`).
- **ANALYST** — read-only on the `PRESENTATION` schema.
- Role-to-user membership is data-driven: each env's `role_members` variable maps a role name to a list of users, flattened with `for_each` in `modules/grants`.

## Environment variables

| Variable | Purpose |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | Account identifier (`orgname-accountname`) |
| `SNOWFLAKE_USER` | Snowflake username |
| `SNOWFLAKE_PASSWORD` | Used only during initial setup before key-pair is configured |
| `SNOWFLAKE_PRIVATE_KEY_PATH` | Path to `rsa_key.p8` (local) or `/tmp/rsa_key.p8` (CI) |
| `SNOWFLAKE_ROLE` | Role dbt connects as; defaults to `ENGINEER` |
| `SNOWFLAKE_WAREHOUSE` | Defaults to `COMPUTE_WH` |
| `DBT_TARGET` | `dev`, `test`, or `prod`; defaults to `dev` |

`.env` drives **dbt** (and any SQL scripts you run manually). dbt does **not** load `.env`
itself — load it with `uv run --env-file .env <dbt command>` so the variables are present in
dbt's process. **Terraform does not read `.env`.** Under Local
execution mode Terraform reads each environment's connection inputs (`organization_name`,
`account_name`, `user`, `role`, `private_key_path`) from a gitignored `terraform.tfvars` **or**
from `TF_VAR_*` environment variables. Keep these in sync with `.env` if the same identity is used
for both.

## GitHub Actions secrets required

`terraform.yml` and `dbt.yml` authenticate as different Snowflake users and read different
secrets — do not conflate them:

- **`terraform.yml`** (as `TERRAFORM_USER`): `TF_API_TOKEN` (HCP Terraform), `TERRAFORM_PRIVATE_KEY`
  (base64 `rsa_key.p8`), `SNOWFLAKE_ORG`, `SNOWFLAKE_ACCOUNT_NAME`.
- **`dbt.yml`** (as the dbt connecting user, `ENGINEER` role): `SNOWFLAKE_ACCOUNT_IDENTIFIER`,
  `DBT_SERVICE_ACCOUNT`, `DBT_USER_PRIVATE_KEY` (base64 `rsa_key.p8`).

`user`/`role` are intentionally not set as `TF_VAR_*` in `terraform.yml` so `TERRAFORM_USER` is
never overwritten with the dbt user's credentials — see `terraform/README.md`.

## Progress

### Done

- [x] Snowflake environment provisioning script — superseded by Terraform and removed
- [x] `scripts/` reorganised into `ddl/`/`dml/`/`network/`/`procs/` for objects Terraform doesn't yet manage
- [x] `INGESTION_METADATA` control table (in `ADMIN`) + idempotent seed DML
- [x] USGS Earthquake ingestion pipeline: landing + staging tables, egress network rules, external access integration, and a Python (Snowpark) stored proc with watermarking
- [x] dbt `profiles.yml` extended to three targets (`dev`/`test`/`prod`) with a pinned connecting role
- [x] dbt project scaffold with env-var-based profiles
- [x] CI workflow (`ci.yml`): ruff lint + format check on PR to main
- [x] CD workflow (`dbt.yml`): gated `dbt build` (`dev→test→prod`) on merge to main, each stage tied to a GitHub Environment
- [x] Key-pair auth setup guide in README (PowerShell + bash)
- [x] Branch protection instructions in README
- [x] Terraform scaffold: per-environment dirs + shared modules
- [x] `TERRAFORM_USER` service account with key-pair (JWT) auth
- [x] `database`, `warehouse`, `role`, and `grants` modules built and wired into all four environments
- [x] Custom roles (`ENGINEER`, `ANALYST`) with privilege grants and data-driven role-to-user membership
- [x] Migrated Terraform state to HCP Terraform (one workspace per environment, Local execution)
- [x] `account`, `dev`, `test`, and `prod` environments all provisioned
- [x] Terraform CI/CD (`terraform.yml`): fmt/validate/plan on PR (all envs, plan posted as PR comment); gated sequential apply (`account→dev→test→prod`) on merge
- [x] dbt sources over the RAW USGS landing table with a freshness check (`_src_earthquake.yml`)
- [x] Staging models: `stg_earthquake__event_classification`, `stg_earthquake__location`, `stg_earthquake__alert_status`, `stg_earthquake__seismic_event`
- [x] Star schema marts: `dim_date` (dbt_utils `date_spine`), `dim_event_classification`, `dim_location` (`AI_EXTRACT` region/country + manual SCD Type 2), `dim_alert_status` (PAGER alert rank/flags + manual SCD Type 2), `fact_seismic_event` (FKs to all four dims + event metrics, manual SCD Type 1), all keyed with `generate_surrogate_key`
- [x] `magnitude_types` seed + `dbt_project.yml` seed config (column-name mismatch between seed config and CSV headers fixed)
- [x] `dbt_utils` package added; custom `generate_schema_name` macro
- [x] Generic + `dbt_utils` tests across models (`not_null`, `unique`, `accepted_values`, `relationships`, `accepted_range`); dbt unit tests for magnitude-band boundaries, alert-status flag derivation, and direction/distance regex parsing
- [x] Presentation layer: 1:1 views over every mart (`models/presentation/`), the actual grant target for `ANALYST`
- [x] Ingestion wired into dbt itself via an `on-run-start` hook macro that calls `INGEST_USGS_EARTHQUAKES` at the start of every `dbt build`
- [x] `dbt.yml` CD workflow gates `dbt build` per environment behind GitHub Environment approvals, using a dedicated `DBT_SERVICE_ACCOUNT`/`DBT_USER_PRIVATE_KEY` secret pair separate from Terraform's
- [x] Data model diagrams: `docs/earthquake_model.drawio` + exported conceptual/logical/physical PNGs (`docs/model/`), and a dbt DAG screenshot (`docs/dbt-dag.png`)

### Next / ideas to explore

- [ ] Extend Terraform CI with `tflint` + a security scanner (`checkov`/`tfsec`)
- [ ] Harden secrets: mark connection variables `sensitive`; move to a passphrase-protected key
- [ ] Add a `snowflake_resource_monitor` to cap trial-account credit usage
- [ ] Establish role hierarchy: grant custom roles up to `SYSADMIN`
- [ ] Add `terraform test` coverage for the `grants` module (membership flattening)
- [ ] Replace the manual SCD Type 2 pattern in `dim_location`/`dim_event_classification`/`dim_alert_status` (and the matching SCD Type 1 in `fact_seismic_event`) with dbt snapshots
- [ ] Add a PR-time dbt build/compile check — `ci.yml` only runs ruff; `dbt.yml` has no `pull_request` trigger, so dbt models are first validated after merge (gated by environment approval, but only against DEV first)
- [ ] Provision `DBT_SERVICE_ACCOUNT` as a proper Terraform-managed service user (currently a placeholder secret, per `TODO.md`) rather than a manually created one
- [ ] Explore Snowflake features: dynamic tables, streams, tasks
