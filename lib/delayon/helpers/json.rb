# frozen_string_literal: true

module DelayOn
  module JSONHelper

    def get_unique_json_element(json, element)
      jsondata = JSON.parse(json)
      value = if jsondata['total'] == 1
                jsondata['result'][0][element]
              else
                false
              end
      value
    end
  end
end