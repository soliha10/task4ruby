module Assistant
  class Chat
    MAX_ITERATIONS = 6
    TEMPERATURE = 0
    NO_ANSWER = "(no answer)".freeze

    def initialize(user:, client: GeminiClient.new)
      @user = user
      @client = client
      @tools = Tools.new(user: user)
    end

    def reply(message, history: [])
      return respond("Please type a question.") if message.blank?
      return respond("The assistant is not configured: the GEMINI_API_KEY environment variable is missing.", error: "missing_api_key") unless @client.configured?

      converse(history.map { |turn| history_content(turn) } << text_content("user", message))
    rescue GeminiClient::Error => e
      respond("Assistant error: #{e.message}", error: "api_error")
    end

    private

    def converse(contents)
      MAX_ITERATIONS.times do
        parts = Array(@client.generate(payload(contents))["parts"])
        calls = parts.filter_map { |part| part["functionCall"] }
        return respond(reply_text(parts)) if calls.empty?

        contents << { role: "model", parts: parts }
        contents << { role: "user", parts: calls.map { |call| function_response(call) } }
      end
      respond("Sorry, I could not finish this request in #{MAX_ITERATIONS} steps. Please rephrase it.")
    end

    def respond(text, error: nil)
      { reply: text, actions: @tools.ui_actions, error: error }.compact
    end

    def reply_text(parts)
      parts.filter_map { |part| part["text"] unless part["thought"] }.join.strip.presence || NO_ANSWER
    end

    def function_response(call)
      { functionResponse: { name: call["name"], response: { result: @tools.call(call["name"], call["args"]) } } }
    end

    def payload(contents)
      {
        systemInstruction: { parts: [ { text: system_prompt } ] },
        contents: contents,
        tools: [ { functionDeclarations: Tools.declarations } ],
        toolConfig: { functionCallingConfig: { mode: "AUTO" } },
        generationConfig: { temperature: TEMPERATURE }
      }
    end

    def history_content(turn)
      text_content(turn[:role] == "assistant" ? "model" : "user", turn[:text])
    end

    def text_content(role, text)
      { role: role, parts: [ { text: text.to_s } ] }
    end

    def system_prompt
      <<~PROMPT
        You are the assistant of a user management admin panel. Current date and time: #{Time.current.utc.iso8601} (UTC).
        The person chatting is #{@user.name} <#{@user.email}>, user id #{@user.id}; "me", "myself" and "my account" refer to this user.
        The table shows users with name, job position, e-mail, last login time and status (active or blocked).

        Rules:
        - ALWAYS call a tool to get any number, count, list, date or statistic. Never guess, estimate or compute numbers yourself; report the exact numbers returned by tools.
        - Express questions as a filter object. "E-mails starting with s or p" is one condition {field: "email", op: "starts_with", values: ["s", "p"]}.
          Names may contain titles/prefixes (Mr., Mrs., Ms., Miss, Dr., Rev., Fr., Msgr., Amb., Gov., Pres., Rep., Sen.) and suffixes (Jr., Sr., II, III, IV, MD, PhD, DDS, DVM, Esq.).
          Match them with op "regex": any prefix title "^[A-Za-z]+\\. |^Miss ", a specific one "^dr\\. ", suffixes " (jr|sr|esq)\\.$| (i|ii|iii|iv|md|phd|dds|dvm)$".
          "Never logged in" is last_login_at is_null. Relative dates like "7 days ago" are accepted as values.
        - For commands about the table (select, check, uncheck, show only, filter, sort, clear) call the UI tools: select_users, clear_selection, filter_table, clear_filter, sort_table.
        - To block, unblock or delete users call perform_action. Delete only when the user explicitly asks to delete. If the current user blocks or deletes themselves they will be logged out; mention it.
        - After a tool call, confirm briefly what was done with the exact number of affected users.
        - Answer concisely, in the same language the user writes in. Use plain text; short lists are fine.
      PROMPT
    end
  end
end
