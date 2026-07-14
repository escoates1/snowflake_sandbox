USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION USGS_EARTHQUAKE_ACCESS_INTEGRATION
    ALLOWED_NETWORK_RULES = (
        DWH_DEV.RAW.USGS_EARTHQUAKE_NETWORK_RULE,
        DWH_TEST.RAW.USGS_EARTHQUAKE_NETWORK_RULE,
        DWH_PROD.RAW.USGS_EARTHQUAKE_NETWORK_RULE
    )
    ENABLED = TRUE
    COMMENT = 'Allows stored procedures to query the USGS Earthquake FDSNWS API across all environments'
;

-- Grant usage rights to the transformations role so that the stored procedure can be called from dbt models
-- Not part of a Terraform plan as EXTERNAL ACCESS INTEGRATIONs are not supported (yet) by the Snowflake provider
GRANT USAGE ON INTEGRATION USGS_EARTHQUAKE_ACCESS_INTEGRATION TO ROLE DBT_TRANSFORMATIONS;