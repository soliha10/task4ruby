require "test_helper"

class AssistantChatTest < ActiveSupport::TestCase
  class ScriptedClient
    attr_reader :payloads

    def initialize(*responses)
      @responses = responses
      @payloads = []
    end

    def configured? = true

    def generate(payload)
      @payloads << payload.deep_dup
      @responses.shift
    end
  end

  setup do
    @me = create_user(name: "Admin", email: "admin@example.test")
    create_user(name: "Sara", email: "sara@example.test")
  end

  test "missing API key gives a friendly message" do
    chat = Assistant::Chat.new(user: @me, client: Assistant::GeminiClient.new(api_key: nil))
    result = chat.reply("How many users?")
    assert_equal "missing_api_key", result[:error]
    assert_match "GEMINI_API_KEY", result[:reply]
  end

  test "executes function calls and returns UI actions" do
    filter = { "conditions" => [ { "field" => "email", "op" => "starts_with", "value" => "s" } ] }
    client = ScriptedClient.new(
      { "role" => "model", "parts" => [ { "functionCall" => { "name" => "select_users", "args" => { "filter" => filter } } } ] },
      { "role" => "model", "parts" => [ { "text" => "Selected 1 user." } ] }
    )
    result = Assistant::Chat.new(user: @me, client: client).reply("select users starting with s")

    assert_equal "Selected 1 user.", result[:reply]
    assert_equal [ { type: "select", ids: [ User.find_by(email: "sara@example.test").id ] } ], result[:actions]

    second = client.payloads.last
    response = second[:contents].last[:parts].first[:functionResponse]
    assert_equal "select_users", response[:name]
    assert_equal 1, response[:response][:result][:selected_count]
    assert second[:tools].first[:functionDeclarations].any? { |d| d[:name] == "count_users" }
  end
end
