{% macro dialysis_chain_group(column) %}
    case
        when {{ column }} = 'DaVita' then 'DaVita'
        when {{ column }} = 'Fresenius Medical Care' then 'Fresenius'
        when {{ column }} = 'Independent' then 'Independent'
        else 'Other chain'
    end
{% endmacro %}
