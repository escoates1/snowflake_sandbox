select
    event_class_key,
    event_type,
    magnitude_type_code,
    magnitude_type_desc,
    magnitude_band
from {{ ref('dim_event_classification') }}