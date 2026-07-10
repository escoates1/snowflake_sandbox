with alert_status as (
    select *
    from {{ ref('stg_earthquake__alert_status') }}
),

formatted as (
    select 
        alert as pager_alert_level,
        case
            when lower(alert) = 'green' then 1
            when lower(alert) = 'yellow' then 2
            when lower(alert) = 'orange' then 3
            when lower(alert) = 'red' then 4
            else null 
        end as pager_alert_rank,
        case
            when lower(status) = 'reviewed' then 'Y'
            when lower(status) = 'automatic' then 'N'
            else null
        end as reviewed_by_human_flag,
        case 
            when tsunami = 1 then 'Y'
            else 'N'
        end as tsunami_flag,
        case
            when felt > 0 then 'Y'
            else 'N'
        end as felt_by_human_flag,
        TO_TIMESTAMP_NTZ(DATEADD('ms', TIME, '1970-01-01')) AS ROW_EFFECTIVE_DATE
    from alert_status
),

deduplicated as (
    select
        *,
        {{ dbt_utils.generate_surrogate_key(['PAGER_ALERT_LEVEL', 'TSUNAMI_FLAG', 'FELT_BY_HUMAN_FLAG']) }} AS alert_status_key,
        COALESCE(
            DATEADD(
                'ms',
                -1,
                LEAD(ROW_EFFECTIVE_DATE) OVER (
                    PARTITION BY PAGER_ALERT_LEVEL, TSUNAMI_FLAG, FELT_BY_HUMAN_FLAG
                    ORDER BY ROW_EFFECTIVE_DATE
                )
            ),
            TO_TIMESTAMP_NTZ('9999-12-31')
        ) AS ROW_EXPIRY_DATE
    from formatted
    QUALIFY ROW_EXPIRY_DATE = '9999-12-31'
),

result as (
    select *,
        CURRENT_TIMESTAMP() AS DWH_CREATE_TIMESTAMP
    from deduplicated
)

select
    alert_status_key,
    pager_alert_level,
    pager_alert_rank,
    reviewed_by_human_flag,
    tsunami_flag,
    felt_by_human_flag,
    row_effective_date,
    row_expiry_date,
    dwh_create_timestamp
from result