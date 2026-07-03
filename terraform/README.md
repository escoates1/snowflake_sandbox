# Terraform — Snowflake account provisioning

This directory provisions all Snowflake account objects as code: databases, schemas,
warehouses, custom roles, and grants. Nothing here is created by hand in Snowsight.

State is stored in **HCP Terraform** (one workspace per environment) with **Local execution
mode**, so runs happen on your machine (or the CI runner) and the provider can read the local
private-key file, while state is stored and locked remotely.

---

## Layout

```text
terraform/
├── modules/                     # reusable building blocks (no backend, no provider config)
│   ├── database/                #   snowflake_database + its schemas
│   ├── warehouse/               #   snowflake_warehouse
│   ├── role/                    #   account-level custom roles (ENGINEER, ANALYST)
│   └── grants/                  #   privilege grants + role-to-user memberships
└── environments/                # one root module + one HCP workspace each
    ├── account/                 #   custom roles (account-wide)      → apply FIRST
    ├── dev/                      #   DWH_DEV  + WH_DEV  + grants
    ├── test/                     #   DWH_TEST + WH_TEST + grants
    └── prod/                     #   DWH_PROD + WH_PROD + grants
```

### Modules

| Module | Creates | Key inputs |
| --- | --- | --- |
| `database` | A database and its `RAW`, `STAGING`, `MARTS`, `PRESENTATION` schemas | `name`, `schemas` |
| `warehouse` | A single warehouse (auto-suspend, initially suspended) | `name`, `warehouse_size`, `auto_suspend` |
| `role` | The `ENGINEER` and `ANALYST` account roles | *(none — names are fixed)* |
| `grants` | Privilege grants to the roles on a database + role-to-user membership | `engineer_role_name`, `analyst_role_name`, `database_name`, `warehouse_name`, `role_members` |

### Environments

Each environment is an independent **root module** with its own HCP workspace and state:

| Environment | Workspace | Provisions | Provider role(s) |
| --- | --- | --- | --- |
| `account` | `snowflake-sandbox-account` | Custom roles (`ENGINEER`, `ANALYST`) | `SECURITYADMIN` |
| `dev` | `snowflake-sandbox-dev` | `DWH_DEV`, `WH_DEV`, grants, memberships | `SYSADMIN` + `SECURITYADMIN` |
| `test` | `snowflake-sandbox-test` | `DWH_TEST`, `WH_TEST`, grants, memberships | `SYSADMIN` + `SECURITYADMIN` |
| `prod` | `snowflake-sandbox-prod` | `DWH_PROD`, `WH_PROD`, grants, memberships | `SYSADMIN` + `SECURITYADMIN` |

Each env's `providers.tf` declares **two** providers against the same `TERRAFORM_USER`:
the default one assuming `SYSADMIN` (databases/warehouses) and an aliased `securityadmin`
one assuming `SECURITYADMIN` (roles/grants). The `role` and `grants` modules are passed the
`securityadmin` provider explicitly.

---

## Apply order (important)

Roles are created in `account`, but they are **referenced by name** in the database
environments (which grant them privileges and assign users). Because these are separate states,
Terraform cannot infer the dependency — you must apply in order:

```text
1. account   →  creates ENGINEER / ANALYST
2. dev       →  grants those roles on DWH_DEV,  assigns members
3. test      →  grants those roles on DWH_TEST, assigns members
4. prod      →  grants those roles on DWH_PROD, assigns members
```

Applying a database environment before `account` fails with *"Requested role 'ANALYST' is not
assigned / does not exist."* The CI/CD workflow enforces this order automatically (see below).

---

## One-time setup

### 1. Prerequisites

- Terraform CLI installed (`terraform -version`).
- `TERRAFORM_USER` service account created in Snowflake with key-pair auth and the `SYSADMIN`
  and `SECURITYADMIN` roles — see the repository root `README.md`, step 4.
- The private key file (`rsa_key.p8`) on disk, outside the repo.

### 2. Create an HCP Terraform organization

1. Sign up at <https://app.terraform.io> (free tier is sufficient).
2. Create an **organization**. This project's `cloud {}` blocks use `escoates1-org` — either
   reuse that name or change the `organization` value in each env's `versions.tf` to match yours.

### 3. Create the four workspaces

For each environment, create a workspace using the **CLI-Driven Workflow**:

1. **New → Workspace → CLI-Driven Workflow.**
2. Name it exactly as referenced in `versions.tf`:
   - `snowflake-sandbox-account`
   - `snowflake-sandbox-dev`
   - `snowflake-sandbox-test`
   - `snowflake-sandbox-prod`
3. After creation, open **Settings → General** and set **Execution Mode = Local**, then save.

> **Why Local execution?** The provider authenticates with `private_key = file(var.private_key_path)`,
> reading a key file from the machine running Terraform. Remote execution runs on HCP's servers,
> where that file doesn't exist, so auth would fail. Local execution keeps runs on your machine
> (and on the GitHub runner in CI, which writes the key to `/tmp`) while still storing/locking
> state in HCP. Moving to Remote execution later requires supplying the key as a sensitive
> workspace variable instead of a path (see "Future hardening").

The workspace name is wired in each env's `versions.tf`, e.g.:

```hcl
terraform {
  cloud {
    organization = "escoates1-org"
    workspaces {
      name = "snowflake-sandbox-dev"
    }
  }
}
```

### 4. Authenticate the CLI to HCP

```powershell
terraform login          # opens a browser, stores an API token in ~/.terraform.d
```

### 5. Provide connection variables

Under Local execution, variables come from the machine running Terraform (not the HCP workspace
UI). Each env declares `organization_name`, `account_name`, `user`, `role`, and
`private_key_path`. Supply the ones without defaults (`organization_name`, `account_name`,
`private_key_path`) either way:

**Option A — `terraform.tfvars`** (gitignored) in each env directory:

```hcl
organization_name = "TNNCLFB"
account_name      = "VE48887"
private_key_path  = "C:/Users/you/Dev/rsa_key.p8"   # forward slashes in HCL
```

**Option B — `TF_VAR_*` environment variables** (shared across all envs, nothing on disk):

```powershell
$env:TF_VAR_organization_name = "TNNCLFB"
$env:TF_VAR_account_name      = "VE48887"
$env:TF_VAR_private_key_path  = "C:/Users/you/Dev/rsa_key.p8"
```

`user` (`TERRAFORM_USER`) and `role` have defaults, so they need no value.

---

## Day-to-day usage

From an environment directory (start with `account`):

```powershell
cd terraform\environments\account
terraform init       # connects to the HCP workspace + downloads the provider (first run)
terraform fmt        # canonical formatting
terraform validate   # syntax / reference check, no Snowflake call
terraform plan       # preview changes
terraform apply      # create/update objects; state is written to HCP
```

Then repeat in `dev`, `test`, and `prod`. A clean environment reports **No changes** on a
second `plan`.

> **Tip:** if `plan` shows *no* changes when you expected a grant or membership, a variable is
> probably not wired through the module call — check the `module "grants"` block passes what you
> changed (e.g. `role_members = var.role_members`).

---

## CI/CD (`.github/workflows/terraform.yml`)

The workflow runs whenever anything under `terraform/**` changes:

- **On a PR to `main`** — a `plan` job runs across all four environments (matrix), doing
  `fmt -check` → `init` → `validate` → `plan`, and posts each plan as a PR comment for review.
- **On merge to `main`** — sequential, gated `apply` jobs run in dependency order
  (`account → dev → test → prod`), chained with `needs:`. Each targets a GitHub
  **Environment** (`snowflake-account`, `snowflake-dev`, …) so you can require manual approval
  before an apply proceeds.

It authenticates the same way as local runs (Local execution): it writes the base64 key secret
to `/tmp/rsa_key.p8` and points `TF_VAR_private_key_path` at it.

### Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `TF_API_TOKEN` | HCP Terraform API token (from `terraform login` or a team/user token) so the `cloud {}` block can reach remote state |
| `TERRAFORM_PRIVATE_KEY` | Base64-encoded `rsa_key.p8` for `TERRAFORM_USER` |
| `SNOWFLAKE_ORG` | Organization half of the account identifier |
| `SNOWFLAKE_ACCOUNT_NAME` | Account half of the account identifier |

`user` and `role` are intentionally **not** set as `TF_VAR_*` in CI — their defaults
(`TERRAFORM_USER` / `SYSADMIN`) are correct, and `TERRAFORM_USER` must not be overwritten.

---

## Formatting on Windows

`terraform fmt -diff` shells out to a Unix `diff` binary that Windows lacks. To see what's
misformatted, either run `terraform fmt -recursive` and inspect with `git diff`, or run the
check without `-diff`:

```powershell
terraform fmt -check -recursive
```

CI runs `terraform fmt -check -recursive`, so match that locally before pushing.

---

## Future hardening

- **Sensitive variables:** mark `private_key_path` / `private_key` with `sensitive = true` so
  values are redacted in plan output and logs.
- **Remote execution:** to run plans/applies on HCP itself (and enable VCS-driven runs), switch
  each workspace to Remote execution and provide the key as a **sensitive** workspace variable
  (`private_key`) read directly, instead of `file(private_key_path)`.
- **Static analysis:** add `tflint` and a security scanner (`checkov`/`tfsec`) to the `plan` job.
- **Resource monitor:** add a `snowflake_resource_monitor` to cap credit usage on the trial
  account.
- **Least privilege:** replace the `ENGINEER` `ALL` table/view grants with an explicit
  privilege list.
