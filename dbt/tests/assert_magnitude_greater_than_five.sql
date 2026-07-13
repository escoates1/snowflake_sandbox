-- All earthquakes in this workflow should have a magnitude of 5 or greater.
-- This test checks that the fact_seismic_event table does not contain any events with a magnitude less than 5.
select *
from {{ ref('fact_seismic_event') }}
where magnitude < 5