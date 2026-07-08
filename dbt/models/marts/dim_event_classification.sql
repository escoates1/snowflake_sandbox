with event_classification as (
    select *
    from {{ ref('stg_earthquake__event_classification') }}
),

magnitude_types AS (
    SELECT *
    FROM {{ ref('magnitude_types') }}
),

cleaned AS (
    SELECT
        TRIM("TYPE") AS EVENT_TYPE,
        TRIM(UPPER(MAGTYPE)) AS MAGNITUDE_TYPE_CODE,
        magnitude_types.MAGNITUDE_TYPE_DESC,
        CASE
            WHEN MAG >= 5 AND MAG < 6 THEN 'Moderate'
            WHEN MAG >= 6 AND MAG < 7 THEN 'Strong'
            WHEN MAG >= 7 AND MAG < 8 THEN 'Major'
            WHEN MAG >= 8 AND MAG < 9 THEN 'Great'
            WHEN MAG >= 9 THEN 'Extreme'
            ELSE NULL
        END AS MAGNITUDE_BAND,
        TO_TIMESTAMP_NTZ(DATEADD('ms', TIME, '1970-01-01')) AS ROW_EFFECTIVE_DATE
    FROM event_classification
    LEFT JOIN magnitude_types
    ON TRIM(UPPER(event_classification.MAGTYPE)) = TRIM(UPPER(magnitude_types.MAGNITUDE_TYPE_CODE))
),

deduplicated AS (
    SELECT
        *,
        {{ dbt_utils.generate_surrogate_key(['EVENT_TYPE', 'MAGNITUDE_TYPE_CODE', 'MAGNITUDE_BAND']) }} AS EVENT_CLASS_KEY,
        COALESCE(
            DATEADD(
                'ms',
                -1,
                LEAD(ROW_EFFECTIVE_DATE) OVER (
                    PARTITION BY EVENT_TYPE, MAGNITUDE_TYPE_CODE, MAGNITUDE_BAND
                    ORDER BY ROW_EFFECTIVE_DATE
                )
            ),
            TO_TIMESTAMP_NTZ('9999-12-31')
        ) AS ROW_EXPIRY_DATE
    FROM cleaned
    QUALIFY ROW_EXPIRY_DATE = '9999-12-31'
),

result as (
    select *,
        CURRENT_TIMESTAMP() AS DWH_CREATE_TIMESTAMP
    from deduplicated
)

select *
from result