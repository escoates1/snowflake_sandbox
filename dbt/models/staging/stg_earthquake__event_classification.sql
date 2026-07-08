WITH source AS (
    SELECT *
    FROM {{ source('usgs_earthquake', 'earthquakes') }}
),

refined as (
    select
        type,
        magtype,
        mag,
        time
    from source
)

select *
from refined