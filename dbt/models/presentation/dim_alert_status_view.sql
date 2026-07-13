select
    alert_status_key,
    pager_alert_level,
    pager_alert_rank,
    reviewed_by_human_flag,
    tsunami_flag,
    felt_by_human_flag
from {{ ref('dim_alert_status') }}