# snowflake_sandbox

A sandbox for practising Snowflake, dbt, and CI/CD pipelines. All Snowflake objects are defined and created via code — never via Snowsight.

## Project structure

```text
.
├── scripts/
│   └── setup_snowflake.py   # Creates DEV/PROD databases and schemas from scratch
├── dbt/                     # dbt project
│   ├── dbt_project.yml
│   ├── profiles.yml         # Reads credentials from env vars (safe to commit)
│   ├── packages.yml
│   └── models/
├── .github/
│   └── workflows/
│       ├── ci.yml           # Runs on every PR: lint + dbt compile against DEV
│       └── cd.yml           # Runs on merge to main: dbt run + test against PROD
├── .env.example             # Credential template — copy to .env
└── pyproject.toml
```

---

## First-time setup

### 1. Python environment

```bash
pip install uv
uv venv
# Windows PowerShell:
.venv\Scripts\activate
# bash/zsh:
source .venv/bin/activate

uv sync
```

### 2. Configure credentials

```bash
cp .env.example .env
```

Edit `.env` with your Snowflake account identifier, username, and password. Your account identifier is in Snowsight under **Admin → Accounts** — copy the value in the format `orgname-accountname`.

### 3. Set up Snowflake environments

This script creates the `DEV` and `PROD` databases, their schemas (`RAW`, `STAGING`, `MARTS`), and the `COMPUTE_WH` warehouse. It is idempotent — safe to re-run.

```bash
uv run python scripts/setup_snowflake.py
```

### 4. Set up key-pair authentication

Key-pair auth is required for the CI/CD pipeline (GitHub Actions cannot use passwords). Follow these steps once.

#### Generate an RSA private key

**PowerShell (Windows):**

```powershell
# Requires OpenSSL — install via: winget install ShiningLight.OpenSSL
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8
```

**bash (Linux/macOS/WSL):**

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out rsa_key.p8
```

The file `rsa_key.p8` is gitignored — it must never be committed.

#### Extract the public key

**PowerShell:**

```powershell
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

**bash:**

```bash
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

#### Register the public key with your Snowflake user

Open `rsa_key.pub` and copy everything between (and excluding) the `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----` lines — this is the bare base64 body. Run the following SQL in a Snowsight worksheet (this is the one permitted use of Snowsight — key registration is a one-time account operation):

```sql
ALTER USER <your_username> SET RSA_PUBLIC_KEY='<paste bare key body here>';
```

Verify it worked:

```sql
DESC USER <your_username>;
```

You should see `RSA_PUBLIC_KEY` populated in the output.

#### Update your local .env

```dotenv
SNOWFLAKE_PRIVATE_KEY_PATH=rsa_key.p8
# You can now remove SNOWFLAKE_PASSWORD from .env
```

---

## Setting up GitHub Actions secrets

The CI/CD workflows need three secrets. Go to your GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**.

| Secret name | Value |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | Your account identifier (e.g. `orgname-accountname`) |
| `SNOWFLAKE_USER` | Your Snowflake username |
| `SNOWFLAKE_PRIVATE_KEY` | Base64-encoded private key (see below) |

### Encode the private key for the secret

**PowerShell:**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("rsa_key.p8")) | Set-Clipboard
```

This copies the encoded key to your clipboard. Paste it as the `SNOWFLAKE_PRIVATE_KEY` secret value.

**bash:**

```bash
base64 -i rsa_key.p8 | tr -d '\n' | pbcopy   # macOS
base64 -w 0 rsa_key.p8                         # Linux (prints to stdout)
```

### Enable branch protection

In GitHub → **Settings → Branches → Add rule** for `main`:

- Check **Require a pull request before merging**
- Check **Require status checks to pass before merging**
- Search for and add: `lint` and `dbt-validate`

This ensures no code reaches `main` without passing CI.

---

## Local development

```bash
# Activate venv and load .env, then run dbt against DEV:
uv run dbt compile --profiles-dir dbt
uv run dbt run --profiles-dir dbt
uv run dbt test --profiles-dir dbt
```

Set `DBT_TARGET=prod` in `.env` to target the PROD database locally (use with care).

---

## CI/CD flow

```text
feature branch → PR → CI checks (lint + dbt compile vs DEV) → merge to main → CD (dbt run + test vs PROD)
```

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `ci.yml` | Pull request to `main` | Runs `ruff` lint, then `dbt compile` against DEV |
| `cd.yml` | Push to `main` | Runs `dbt run` + `dbt test` against PROD |
