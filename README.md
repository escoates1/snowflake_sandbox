# snowflake_sandbox

A personal learning sandbox for Terraform, dbt, CI/CD and Snowflake.

The guiding rule: **all Snowflake objects are created via code, never via Snowsight.**

- **Terraform** provisions account-level objects — databases, schemas, roles, and warehouses.
- **dbt** builds the models (staging/marts) on top of those objects.
- The single permitted Snowsight action is the one-time registration of an RSA public key for key-pair auth (an account operation Terraform can't bootstrap for itself).
- For Snowflake objects not fully compatible with Terraform yet (e.g. tables, network rules, external access integrations), SQL scripts are maintained in the /scripts directory.

---

## Project structure

```text
.
├── terraform/                  # Infrastructure as code — Snowflake account objects
│   ├── README.md               # Full Terraform guide (modules, HCP workspaces, apply order)
│   ├── modules/                # Reusable building blocks
│   │   ├── database/           #   a database + its RAW/STAGING/MARTS/PRESENTATION schemas
│   │   ├── warehouse/          #   a warehouse with size/auto-suspend settings
│   │   ├── role/               #   account-level custom roles (ENGINEER, ANALYST)
│   │   └── grants/             #   privilege grants + role-to-user memberships
│   └── environments/           # One directory + one HCP workspace per environment
│       ├── account/            #   account-wide objects (custom roles) — apply FIRST
│       ├── dev/                #   DWH_DEV database + WH_DEV warehouse + grants
│       ├── test/               #   DWH_TEST database + WH_TEST warehouse + grants
│       └── prod/               #   DWH_PROD database + WH_PROD warehouse + grants
├── dbt/                        # dbt project
│   ├── dbt_project.yml
│   ├── profiles.yml            # Reads credentials from env vars (safe to commit)
│   ├── packages.yml
│   └── models/                 # Add staging/ and marts/ as you build
├── scripts/
│   └── setup_snowflake.py      # Legacy provisioning script — superseded by Terraform
├── .github/
│   └── workflows/
│       ├── terraform.yml       # PR: fmt/validate/plan (all envs); merge: gated apply
│       ├── ci.txt              # (inactive .txt) ruff lint + dbt compile against DEV
│       └── cd.txt              # (inactive .txt) dbt run + dbt test against PROD
├── .env.example                # Credential template — copy to .env (gitignored)
└── pyproject.toml
```

**State and secrets** are deliberately kept out of git. Terraform state lives in **HCP Terraform**
(one workspace per environment; see `terraform/README.md`), configured with **Local execution
mode** so runs happen on your machine and can read the local key file. Machine-specific connection
values are supplied locally via a gitignored `terraform.tfvars` or `TF_VAR_*` environment
variables — never committed. The private key file (`rsa_key.p8`) is gitignored and kept outside
the repo.

---

## Custom Roles

For simplicity in a sandbox environment, the below roles have access across all database environments. In a real-world scenario, there might be a separate role generated per environment to give finer grained permissions.

- ENGINEER - read/write across across all schemas.
- ANALYST - read access only in the `PRESENTATION` schema.

The roles themselves are created once in the **`account`** environment; each of `dev`/`test`
then grants those roles privileges on its own database and assigns them to users.

---

## Setup instructions

### 1. Tools

| Tool | Install (Windows) |
| --- | --- |
| Python 3.12 + `uv` | `pip install uv` |
| Terraform | `winget install Hashicorp.Terraform` (then reopen the shell so it's on `PATH`) |
| OpenSSL | `winget install ShiningLight.OpenSSL` |

Verify with `terraform -version` and `openssl version`.

You also need a free **HCP Terraform** account for remote state — see `terraform/README.md`.

### 2. Python environment

```powershell
uv venv
.venv\Scripts\activate
uv sync
```

### 3. Configure credentials

```powershell
Copy-Item .env.example .env
```

Edit `.env`. Find your account identifier in Snowsight under **Admin → Accounts** — it has
the form `orgname-accountname`. During first-time setup (before key-pair auth exists) you may
set `SNOWFLAKE_PASSWORD`; remove it once key-pair auth is working.

### 4. Set up key-pair auth and the Terraform service user

Terraform authenticates as a dedicated **`TERRAFORM_USER`** service account using an RSA
key pair — not your personal login.

**Generate the key pair** (keep `rsa_key.p8` outside the repo, e.g. one directory up):

```powershell
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

**Register it and create the service user.** Open `rsa_key.pub` and copy the base64 body
**between** (and excluding) the `-----BEGIN/END PUBLIC KEY-----` lines, then run this once in a
Snowsight worksheet (the single permitted Snowsight operation):

```sql
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS TERRAFORM_USER
    TYPE = SERVICE
    COMMENT = 'Service user for provisioning Snowflake via Terraform'
    RSA_PUBLIC_KEY = '<paste bare public key body here>';

-- SYSADMIN creates databases/schemas/warehouses; SECURITYADMIN creates roles and grants.
GRANT ROLE SYSADMIN TO USER TERRAFORM_USER;
GRANT ROLE SECURITYADMIN TO USER TERRAFORM_USER;
```

Verify with `DESC USER TERRAFORM_USER;` — the `RSA_PUBLIC_KEY_FP` row should be populated.

> **Troubleshooting `JWT token is invalid`:** the fingerprint registered on the user must
> match the private key Terraform uses, and `user`/`role` in `terraform.tfvars` must name the
> service user and a real role. Compute the local key's fingerprint and compare it to
> `RSA_PUBLIC_KEY_FP` from `DESC USER`:
>
> ```bash
> echo -n "SHA256:"; openssl pkey -in rsa_key.p8 -pubout -outform DER \
>   | openssl dgst -sha256 -binary | openssl enc -base64
> ```

### 5. Provision with Terraform

Full details — including the one-time HCP workspace creation, connection variables, and the
required apply order — live in **[`terraform/README.md`](terraform/README.md)**. In short:

```powershell
terraform login                       # once: authenticate the CLI to HCP Terraform

cd terraform\environments\account     # apply the ACCOUNT env first (creates the roles)
terraform init
terraform apply

cd ..\dev                             # then each database environment: dev, test, prod
terraform init
terraform apply
```

`account` must be applied before `dev`/`test`/`prod`, because those environments grant the roles
the `account` environment creates. Re-running `plan` afterward should report **No changes**.

You don't have to run these by hand: **`.github/workflows/terraform.yml`** plans all environments
on every PR (posting the plan as a PR comment) and, on merge to `main`, applies them in order
(`account → dev → test → prod`) behind GitHub Environment approval gates. See
[`terraform/README.md`](terraform/README.md) for the CI/CD details and required secrets.

### 6. Run dbt

```powershell
uv run dbt compile --profiles-dir dbt
uv run dbt run --profiles-dir dbt
uv run dbt test --profiles-dir dbt
```

Set `DBT_TARGET=prod` in `.env` to target PROD locally (use with care).

### 7. GitHub Actions secrets and branch protection

The CI/CD workflows need three repository secrets
(**Settings → Secrets and variables → Actions**):

| Secret | Value |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | Account identifier (`orgname-accountname`) |
| `SNOWFLAKE_USER` | Snowflake user for the workflow |
| `SNOWFLAKE_PRIVATE_KEY` | Base64-encoded `rsa_key.p8` |

Encode the key for the secret:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("rsa_key.p8")) | Set-Clipboard
```

Then protect `main` under **Settings → Branches → Add rule**: require a pull request and
require status checks (`lint`, `dbt-validate`) to pass before merging.
