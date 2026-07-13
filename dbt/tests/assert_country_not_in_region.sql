-- Checks that the COUNTRY field is not contained within the REGION field in the dim_location table.
select *
from {{ ref('dim_location') }}
where contains(region, country) = true