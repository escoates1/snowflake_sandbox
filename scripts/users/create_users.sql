CREATE USER TERRAFORM_USER
    TYPE = SERVICE
    COMMENT = "Service user for Terraforming Snowflake"
    RSA_PUBLIC_KEY = "INSERT_PUBLIC_KEY_HERE"
;

CREATE USER DBT_USER
    TYPE = SERVICE
    COMMENT = "Service user for dbt models ran against Snowflake"
    RSA_PUBLIC_KEY = "INSERT_PUBLIC_KEY_HERE"
;