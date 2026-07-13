WITH event AS (
    SELECT *
    FROM {{ ref('stg_earthquake__seismic_event') }}
),

event_cleaned as (
    select
        *,
        trim("TYPE") as event_type,
        trim(upper(magtype)) as magnitude_type_code,
        case
            when magnitude >= 5 and magnitude < 6 then 'Moderate'
            when magnitude >= 6 and magnitude < 7 then 'Strong'
            when magnitude >= 7 and magnitude < 8 then 'Major'
            when magnitude >= 8 and magnitude < 9 then 'Great'
            when magnitude >= 9 then 'Extreme'
            else null
        end as magnitude_band,
        alert as pager_alert_level,
        case 
            when tsunami = 1 then 'Y'
            else 'N'
        end as tsunami_flag,
        case
            when felt > 0 then 'Y'
            else 'N'
        end as felt_by_human_flag
    from event
),

foreign_keys AS (
    select 
        {{ dbt_utils.generate_surrogate_key(['EVENT_ID']) }} as event_key,
        event_id,
        to_date(dateadd('ms', unix_timestamp, '1970-01-01')) as date_key,
        {{ dbt_utils.generate_surrogate_key(['LOCATION']) }} AS location_key,
        {{ dbt_utils.generate_surrogate_key(['EVENT_TYPE', 'MAGNITUDE_TYPE_CODE', 'MAGNITUDE_BAND']) }} AS event_class_key,
        {{ dbt_utils.generate_surrogate_key(['PAGER_ALERT_LEVEL', 'TSUNAMI_FLAG', 'FELT_BY_HUMAN_FLAG']) }} AS alert_status_key,
        to_timestamp_ntz(dateadd('ms', unix_timestamp, '1970-01-01')) as event_timestamp,
        event_url,
        detail_url,
        latitude,
        longitude,
        depth_in_km,
        magnitude,
        REGEXP_SUBSTR(LOCATION, '^\\d+ km ([NSEW]+) of', 1, 1, 'e', 1) AS direction_from_place,
        REGEXP_SUBSTR(LOCATION, '^(\\d+ km)', 1, 1, 'e', 1) AS distance_from_place_km,
        felt as felt_count,
        cdi as cdi_max,
        mmi as mmi_max,
        significance,
        num_stations,
        dmin_deg,
        rms_sec,
        azimuthal_gap_deg,
        TO_TIMESTAMP_NTZ(DATEADD('ms', unix_timestamp, '1970-01-01')) AS ROW_EFFECTIVE_DATE
from event_cleaned
),

deduplicated AS (
    SELECT
        *,
        COALESCE(
            DATEADD(
                'ms',
                -1,
                LEAD(ROW_EFFECTIVE_DATE) OVER (
                    PARTITION BY event_key
                    ORDER BY ROW_EFFECTIVE_DATE
                )
            ),
            TO_TIMESTAMP_NTZ('9999-12-31')
        ) AS ROW_EXPIRY_DATE
    FROM foreign_keys
    QUALIFY ROW_EXPIRY_DATE = '9999-12-31'
),

result as (
    select *,
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ(9) AS DWH_CREATE_TIMESTAMP
    from deduplicated
)

select *
from result
