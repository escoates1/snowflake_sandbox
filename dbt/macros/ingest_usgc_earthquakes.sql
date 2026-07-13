  {% macro ingest_usgs_earthquakes() %}
    {% if execute %}
      {% set call_sql %}
        CALL {{ target.database }}.RAW.INGEST_USGS_EARTHQUAKES('{{ target.database }}', 'RAW')
      {% endset %}
      {% set result = run_query(call_sql) %}
      {{ log("INGEST_USGS_EARTHQUAKES: " ~ result.columns[0].values()[0], info=true) }}
    {% endif %}
  {% endmacro %}