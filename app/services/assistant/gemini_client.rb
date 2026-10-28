require "net/http"

module Assistant
  class GeminiClient
    class Error < StandardError; end

    ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
    DEFAULT_MODEL = "gemini-3.5-flash"
    OPEN_TIMEOUT_SECONDS = 10
    READ_TIMEOUT_SECONDS = 60
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED ].freeze

    def initialize(api_key: ENV["GEMINI_API_KEY"], model: ENV.fetch("GEMINI_MODEL", DEFAULT_MODEL))
      @api_key = api_key.presence
      @model = model.presence || DEFAULT_MODEL
    end

    def configured?
      @api_key.present?
    end

    def generate(payload)
      response = post(payload)
      body = parse(response.body)
      raise Error, body.dig("error", "message") || "Gemini API returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body.dig("candidates", 0, "content") || raise(Error, "Gemini returned no answer (#{no_answer_reason(body)})")
    rescue *NETWORK_ERRORS => e
      raise Error, "Could not reach Gemini: #{e.message}"
    end

    private

    def post(payload)
      uri = URI(format(ENDPOINT, @model))
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "x-goog-api-key" => @api_key)
      request.body = payload.to_json
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS) do |http|
        http.request(request)
      end
    end

    def parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def no_answer_reason(body)
      body.dig("candidates", 0, "finishReason") || body.dig("promptFeedback", "blockReason") || "empty response"
    end
  end
end
