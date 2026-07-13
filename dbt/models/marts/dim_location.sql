WITH location AS (
    SELECT *
    FROM {{ ref('stg_earthquake__location') }}
),

location_extract AS (
    SELECT
        *,
        loc.LOCATION_INFO:response:region::STRING AS REGION,
        loc.LOCATION_INFO:response:country::STRING AS COUNTRY
    FROM location,
        LATERAL (
            SELECT AI_EXTRACT(
                text => PLACE,
                responseFormat => {
                    'region': 'The specific region, province, or city. Do not extract strings that represent the names of countries. Return a NULL if input is too vague like an ocean or general direction.',
                    'country': 'The country name only. Return a NULL if the input does not contain a recognised country name.'
                }
            ) AS LOCATION_INFO
        ) loc   
),

cleaned as (
    select
        {{ dbt_utils.generate_surrogate_key(['PLACE']) }} AS LOCATION_KEY,
        PLACE AS LOCATION,
        NULLIF(TRIM(REGEXP_REPLACE(REPLACE(REGION, COUNTRY, ''), ',\\s*$', '')),'') AS REGION,
        NULLIF(TRIM(COUNTRY), 'None') AS COUNTRY,
        CASE 
            WHEN LATITUDE > 0 THEN 'N'
            WHEN LATITUDE < 0 THEN 'S' 
            ELSE NULL
        END AS LAT_HEMISPHERE,
        CASE 
            WHEN LONGITUDE > 0 THEN 'E'
            WHEN LONGITUDE < 0 THEN 'W' 
            ELSE NULL
        END AS LON_HEMISPHERE,
        TO_TIMESTAMP_NTZ(DATEADD('ms', TIME, '1970-01-01')) AS ROW_EFFECTIVE_DATE
    from location_extract
),

deduplicated AS (
    SELECT
        *,
        COALESCE(
            DATEADD(
                'ms',
                -1,
                LEAD(ROW_EFFECTIVE_DATE) OVER (
                    PARTITION BY LOCATION
                    ORDER BY ROW_EFFECTIVE_DATE
                )
            ),
            TO_TIMESTAMP_NTZ('9999-12-31')
        ) AS ROW_EXPIRY_DATE,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(9) AS DWH_CREATE_TIMESTAMP
    FROM cleaned
    QUALIFY ROW_EXPIRY_DATE = '9999-12-31'
)

SELECT
    LOCATION_KEY,
    LOCATION,
    REGION,
    COUNTRY,
    LAT_HEMISPHERE,
    LON_HEMISPHERE,
    ROW_EFFECTIVE_DATE,
    ROW_EXPIRY_DATE,
    DWH_CREATE_TIMESTAMP
FROM deduplicated