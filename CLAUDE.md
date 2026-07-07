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
- Terraform is structured as one directory **per environment** (`terraform/environments/{account,dev,test,prod}`) that calls shared `terraform/modules/*`. The **`account`** environment creates account-wide objects (the custom roles); **`dev`**/**`test`**/**`prod`** each create a database + warehouse and grant the roles. `account` must be applied before the database environments.
- **State lives in HCP Terraform**, one workspace per environment (org `escoates1-org`; workspaces `snowflake-sandbox-{account,dev,test}`), configured via a `cloud {}` block in each env's `versions.tf`. Workspaces use **Local execution mode** — state is stored/locked remotely, but runs happen on the local machine so the provider can read the local private-key file. (See `terraform/README.md`.)
- Terraform authenticates as a dedicated **`TERRAFORM_USER`** service account via key-pair (JWT), with roles `SYSADMIN` (objects) and `SECURITYADMIN` (roles/grants) — not the personal login. `providers.tf` declares two providers: the default (`SYSADMIN`) and an aliased `securityadmin`.
- Terraform connection values are supplied locally (Local execution mode) via a gitignored `terraform.tfvars` **or** `TF_VAR_*` environment variables; no secrets in `.tf` files. The account id splits into `organization_name` + `account_name`; HCL paths use forward slashes.
- Key-pair auth for all non-interactive connections (CI/CD and local dev after initial setup)
- `dbt/profiles.yml` is committed — it contains no secrets, reads everything from env vars; three targets (`dev`/`test`/`prod`) selected by `DBT_TARGET`, connecting role pinned via `SNOWFLAKE_ROLE` (default `ENGINEER`)
- Run dbt commands with `--profiles-dir dbt` (or `--profiles-dir .` from inside `dbt/`) so the committed profile is used rather than `~/.dbt/profiles.yml`. dbt does **not** load `.env` itself — load it with `uv run --env-file .env <dbt command>`
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
  dbt_project.yml
  profiles.yml               — env-var-based, safe to commit
  packages.yml
  models/                    — empty; add staging/ and marts/ subdirs as you build
.github/workflows/
  terraform.yml              — PR: fmt/validate/plan (all envs); merge: gated apply account→dev→test→prod
  ci.txt                     — (inactive .txt) ruff lint + dbt compile against DEV
  cd.txt                     — (inactive .txt) dbt run + dbt test against PROD
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

`SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY` (base64-encoded `rsa_key.p8`)

## Progress

### Done

- [x] Snowflake environment provisioning script — superseded by Terraform and removed
- [x] `scripts/` reorganised into `ddl/`/`dml/`/`network/`/`procs/` for objects Terraform doesn't yet manage
- [x] `INGESTION_METADATA` control table (in `ADMIN`) + idempotent seed DML
- [x] USGS Earthquake ingestion pipeline: landing + staging tables, egress network rules, external access integration, and a Python (Snowpark) stored proc with watermarking
- [x] dbt `profiles.yml` extended to three targets (`dev`/`test`/`prod`) with a pinned connecting role
- [x] dbt project scaffold with env-var-based profiles
- [x] CI workflow: ruff lint + dbt compile against DEV (on PR to main)
- [x] CD workflow: dbt run + dbt test against PROD (on merge to main)
- [x] Key-pair auth setup guide in README (PowerShell + bash)
- [x] Branch protection instructions in README
- [x] Terraform scaffold: per-environment dirs + shared modules
- [x] `TERRAFORM_USER` service account with key-pair (JWT) auth
- [x] `database`, `warehouse`, `role`, and `grants` modules built and wired into all four environments
- [x] Custom roles (`ENGINEER`, `ANALYST`) with privilege grants and data-driven role-to-user membership
- [x] Migrated Terraform state to HCP Terraform (one workspace per environment, Local execution)
- [x] `account`, `dev`, `test`, and `prod` environments all provisioned
- [x] Terraform CI/CD (`terraform.yml`): fmt/validate/plan on PR (all envs, plan posted as PR comment); gated sequential apply (`account→dev→test→prod`) on merge

### Next / ideas to explore

- [ ] Extend Terraform CI with `tflint` + a security scanner (`checkov`/`tfsec`)
- [ ] Harden secrets: mark connection variables `sensitive`; move to a passphrase-protected key
- [ ] Add a `snowflake_resource_monitor` to cap trial-account credit usage
- [ ] Establish role hierarchy: grant custom roles up to `SYSADMIN`
- [ ] Add `terraform test` coverage for the `grants` module (membership flattening)
- [ ] Build first dbt model — a simple staging model over a raw source
- [ ] Add dbt sources (`sources.yml`) and generic tests (`not_null`, `unique`)
- [ ] Load sample data into `DWH_DEV.RAW` to have something to model
- [ ] Explore dbt snapshots (SCD Type 2)
- [ ] Add `dbt test` to the CI workflow once models exist
- [ ] Explore Snowflake features: dynamic tables, streams, tasks
