WITH source AS (
    SELECT *
    FROM {{ source('usgs_earthquake', 'earthquakes') }}
),

cleaned AS (
    SELECT
        TRIM(ID) AS EVENT_ID,
        TRIM("TYPE") AS EVENT_TYPE,
        TRIM(UPPER(MAGTYPE)) AS MAGNITUDE_TYPE_CODE,
        CASE
            WHEN LOWER(MAGTYPE) = 'mww' THEN 'moment W-phase'
            WHEN LOWER(MAGTYPE) = 'mwr' THEN 'regional'
            WHEN LOWER(MAGTYPE) = 'mw' THEN 'moment'
            WHEN LOWER(MAGTYPE) = 'mwb' THEN 'body wave'
            WHEN LOWER(MAGTYPE) = 'mb' THEN 'short-period body wave'
            WHEN LOWER(MAGTYPE) = 'ml' THEN 'local'
            ELSE NULL
        END AS MAGNITUDE_TYPE_DESC,
        CASE
            WHEN MAG BETWEEN 5 AND 5.9 THEN 'Moderate'
            WHEN MAG BETWEEN 6 AND 6.9 THEN 'Strong'
            WHEN MAG BETWEEN 7 AND 7.9 THEN 'Major'
            WHEN MAG BETWEEN 8 AND 8.9 THEN 'Great'
            WHEN MAG BETWEEN 9 AND 9.9 THEN 'Extreme'
            ELSE NULL
        END AS MAGNITUDE_BAND
    FROM source
)

SELECT *
FROM cleaned