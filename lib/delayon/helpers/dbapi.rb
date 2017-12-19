module DelayOn
  module DBApiHelper
    def prepare_db_api_request(token, url, query)
      request = HTTPI::Request.new
      request.url = url
      request.headers['Authorization'] = 'Bearer ' + token
      request.headers['Accept'] = 'application/json'
      request.query = query
      request
    end
  end
end
