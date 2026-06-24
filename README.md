# snowflake_sandbox

A personal learning sandbox for Snowflake, dbt, and CI/CD.

The guiding rule: **all Snowflake objects are created via code, never via Snowsight.**

- **Terraform** provisions account-level objects — databases, schemas, roles, and warehouses.
- **dbt** builds the models (staging/marts) on top of those objects.
- The single permitted Snowsight action is the one-time registration of an RSA public key for key-pair auth (an account operation Terraform can't bootstrap for itself).

Terraform replaces the earlier `scripts/setup_snowflake.py`, which is kept only for reference.

---

## Project structure

```text
.
├── terraform/                  # Infrastructure as code — Snowflake account objects
│   ├── modules/                # Reusable building blocks
│   │   ├── database/           #   a database + its RAW/STAGING/MARTS schemas
│   │   ├── warehouse/          #   a warehouse with size/auto-suspend settings
│   │   └── role_grants/        #   roles and grants
│   └── environments/           # One directory + state file per environment
│       ├── dev/                #   DEV: versions/variables/providers/main + tfvars
│       └── prod/               #   PROD: same shape as dev
├── dbt/                        # dbt project
│   ├── dbt_project.yml
│   ├── profiles.yml            # Reads credentials from env vars (safe to commit)
│   ├── packages.yml
│   └── models/                 # Add staging/ and marts/ as you build
├── scripts/
│   └── setup_snowflake.py      # Legacy provisioning script — superseded by Terraform
├── .github/
│   └── workflows/
│       ├── ci.yml              # On every PR: ruff lint + dbt compile against DEV
│       └── cd.yml              # On merge to main: dbt run + dbt test against PROD
├── .env.example                # Credential template — copy to .env (gitignored)
└── pyproject.toml
```

**State and secrets** are deliberately kept out of git: each environment uses **local
state** (`terraform.tfstate` in its own directory), and machine-specific values live in a
gitignored `terraform.tfvars` (a committed `terraform.tfvars.example` shows the shape).
The private key file (`rsa_key.p8`) is also gitignored and kept outside the repo.

---

## Setup instructions

### 1. Tools

| Tool | Install (Windows) |
| --- | --- |
| Python 3.12 + `uv` | `pip install uv` |
| Terraform | `winget install Hashicorp.Terraform` (then reopen the shell so it's on `PATH`) |
| OpenSSL | `winget install ShiningLight.OpenSSL` |

Verify with `terraform -version` and `openssl version`.

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

### 5. Configure Terraform variables

Each environment reads connection details from a gitignored `terraform.tfvars`. Copy the
template and fill it in:

```powershell
cd terraform\environments\dev
Copy-Item terraform.tfvars.example terraform.tfvars
```

```dotenv
organization_name = "orgname"        # the part of orgname-accountname before the '-'
account_name      = "accountname"    # the part after the '-'
user              = "TERRAFORM_USER"
role              = "SYSADMIN"
private_key_path  = "C:/Users/you/Dev/rsa_key.p8"   # forward slashes in HCL
```

No secrets go in the committed `.tf` files — the provider reads these variables and loads the
private key from disk at run time.

### 6. Provision with Terraform

From the environment directory (e.g. `terraform\environments\dev`):

```powershell
terraform init      # downloads the snowflakedb/snowflake provider (first run only)
terraform fmt       # optional: canonical formatting
terraform validate  # optional: syntax/reference check, no Snowflake call
terraform plan      # preview the changes
terraform apply     # type "yes" to create the objects
```

`apply` writes `terraform.tfstate` into the environment directory — that's your local state.
Re-running `plan` afterward should report **No changes**. Repeat in
`terraform\environments\prod` for the PROD environment.

> If an object already exists in Snowflake (e.g. created earlier by the legacy script),
> adopt it instead of recreating it: `terraform import <resource_address> <object_name>`,
> then re-run `plan`.

### 7. Run dbt

```powershell
uv run dbt compile --profiles-dir dbt
uv run dbt run --profiles-dir dbt
uv run dbt test --profiles-dir dbt
```

Set `DBT_TARGET=prod` in `.env` to target PROD locally (use with care).

### 8. GitHub Actions secrets and branch protection

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
