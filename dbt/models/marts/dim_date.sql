with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2015-01-01' as date)",
        end_date="cast('2036-01-01' as date)"
    ) }}

),

dim_date as (

    select
        cast(date_day as date)                          as date_key,
        day(date_day)::int                              as day_of_month,
        decode(dayofweekiso(date_day),
            1, 'Monday',
            2, 'Tuesday',
            3, 'Wednesday',
            4, 'Thursday',
            5, 'Friday',
            6, 'Saturday',
            7, 'Sunday'
        )::varchar                                      as day_name,
        dayofweekiso(date_day)::int                     as day_of_week_iso,
        (dayofweekiso(date_day) >= 6)                   as is_weekend,
        weekiso(date_day)::int                          as iso_week,
        month(date_day)::int                            as month_number,
        decode(month(date_day),
            1,  'January',
            2,  'February',
            3,  'March',
            4,  'April',
            5,  'May',
            6,  'June',
            7,  'July',
            8,  'August',
            9,  'September',
            10, 'October',
            11, 'November',
            12, 'December'
        )::varchar                                      as month_name,
        quarter(date_day)::int                          as quarter,
        year(date_day)::int                             as year,
        to_char(date_day, 'YYYY-MM')                    as year_month,
        cast(current_timestamp() as timestamp_ntz(9))   as dwh_create_timestamp
    from spine

)

select * 
from dim_date