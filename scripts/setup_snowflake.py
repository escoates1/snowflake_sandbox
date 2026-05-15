"""
Idempotent setup script for Snowflake environments.
Creates DEV and PROD databases with standard dbt-layer schemas.

Run with SNOWFLAKE_PASSWORD for initial setup.
Run with SNOWFLAKE_PRIVATE_KEY_PATH after key-pair auth is configured.
"""
import os
import sys

import snowflake.connector
from dotenv import load_dotenv

load_dotenv()

DATABASES = ("DEV", "PROD")
SCHEMAS = ("RAW", "STAGING", "MARTS")


def _connect():
    params = {
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ["SNOWFLAKE_USER"],
        "role": "ACCOUNTADMIN",
    }
    if key_path := os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH"):
        params["private_key_file"] = key_path
    elif password := os.environ.get("SNOWFLAKE_PASSWORD"):
        params["password"] = password
    else:
        sys.exit("Set SNOWFLAKE_PRIVATE_KEY_PATH or SNOWFLAKE_PASSWORD in .env")
    return snowflake.connector.connect(**params)


def main():
    conn = _connect()
    cur = conn.cursor()
    try:
        cur.execute("""
            CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
            WAREHOUSE_SIZE = 'X-SMALL'
            AUTO_SUSPEND = 60
            AUTO_RESUME = TRUE
        """)
        print("[ok] warehouse: COMPUTE_WH")

        for db in DATABASES:
            cur.execute(f"CREATE DATABASE IF NOT EXISTS {db}")
            for schema in SCHEMAS:
                cur.execute(f"CREATE SCHEMA IF NOT EXISTS {db}.{schema}")
            print(f"[ok] database: {db} (schemas: {', '.join(SCHEMAS)})")
    finally:
        cur.close()
        conn.close()

    print("\nSnowflake environment ready.")


if __name__ == "__main__":
    main()
