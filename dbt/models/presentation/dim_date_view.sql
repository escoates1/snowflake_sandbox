select
    date_key,
    day_of_month,
    day_name,
    day_of_week_iso,
    is_weekend,
    iso_week,
    month_number,
    month_name,
    quarter,
    year,
    year_month
from {{ ref('dim_date') }}