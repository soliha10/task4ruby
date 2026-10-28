module Assistant
  class Tools
    LIST_LIMIT = 50
    MAX_GROUPS = 200
    DEFAULT_LIMIT = 20
    TOP_STATS_LIMIT = 5
    SORT_FIELDS = %w[name email job_position status last_login_at created_at].freeze
    SORT_DIRECTIONS = %w[asc desc].freeze
    RECENT_LOGIN_WINDOWS = { logged_in_last_24h: 24.hours, logged_in_last_7d: 7.days, logged_in_last_30d: 30.days }.freeze
    GROUP_FIELDS = {
      "status" => UserFilter::TEXT_FIELDS.fetch("status"),
      "email_domain" => UserFilter::TEXT_FIELDS.fetch("email_domain"),
      "job_position" => "COALESCE(users.job_position, '(none)')",
      "last_login_month" => "COALESCE(to_char(users.last_login_at, 'YYYY-MM'), 'never')"
    }.freeze

    FILTER_SCHEMA = {
      type: "OBJECT",
      description: "Selects users. Omit or pass no conditions to match all users.",
      properties: {
        match: { type: "STRING", enum: %w[all any], description: "all = AND between conditions, any = OR. Default all." },
        conditions: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              field: { type: "STRING", enum: UserFilter::FIELDS },
              op: {
                type: "STRING",
                enum: (UserFilter::TEXT_OPS + UserFilter::DATE_OPS).uniq,
                description: "Text: equals, not_equals, contains, not_contains, starts_with, ends_with, regex (POSIX, case-insensitive), is_null, not_null. " \
                             "Dates (last_login_at): before, after, between (two values), equals (same day), is_null (never logged in), not_null."
              },
              value: { type: "STRING", description: "Single value. Dates: ISO 8601 or relative like '7 days ago', 'today'." },
              values: { type: "ARRAY", items: { type: "STRING" }, description: "Several values; for positive operators any of them matches, for not_* none may match. Use for 'starts with s or p'." },
              negate: { type: "BOOLEAN", description: "Invert this condition." }
            },
            required: %w[field op]
          }
        }
      }
    }.freeze

    class << self
      def declarations
        [
          function("get_current_user", "Returns the user who is chatting (the logged-in admin)."),
          function("count_users", "Exact number of users matching a filter.", filter_only),
          function("list_users", "Lists users matching a filter (at most #{LIST_LIMIT} rows) together with the total match count.",
                   object({ filter: FILTER_SCHEMA, sort_by: enum(SORT_FIELDS), sort_dir: enum(SORT_DIRECTIONS),
                            limit: integer("1..#{LIST_LIMIT}, default #{DEFAULT_LIMIT}.") })),
          function("user_stats", "Overall statistics: totals by status, recent logins, never logged in, top email domains and job positions, earliest/latest login."),
          function("group_count", "Counts users grouped by a field, optionally restricted by a filter. Sorted by count desc.",
                   object({ field: enum(GROUP_FIELDS.keys), filter: FILTER_SCHEMA, limit: integer("Maximum groups to return, default #{DEFAULT_LIMIT}.") }, required: %w[field])),
          function("select_users", "UI: checks the checkboxes of matching users in the table and unchecks all others.", filter_only),
          function("clear_selection", "UI: unchecks all checkboxes in the table."),
          function("filter_table", "UI: shows only matching users in the table (hides other rows).", filter_only),
          function("clear_filter", "UI: shows all rows in the table again."),
          function("sort_table", "UI: sorts the table by a column.",
                   object({ field: enum(User::TABLE_SORT_FIELDS), dir: enum(SORT_DIRECTIONS) }, required: %w[field])),
          function("perform_action", "Blocks, unblocks or permanently deletes the users matching a filter (same as the toolbar buttons). Use delete only when the user explicitly asked to delete.",
                   object({ action: enum(User::BULK_ACTIONS), filter: FILTER_SCHEMA }, required: %w[action filter]))
        ]
      end

      private

      def function(name, description, parameters = nil)
        { name: name, description: description, parameters: parameters }.compact
      end

      def object(properties, required: nil)
        { type: "OBJECT", properties: properties, required: required }.compact
      end

      def enum(values)
        { type: "STRING", enum: values }
      end

      def integer(description)
        { type: "INTEGER", description: description }
      end

      def filter_only
        object({ filter: FILTER_SCHEMA })
      end
    end

    attr_reader :ui_actions

    def initialize(user:)
      @user = user
      @ui_actions = []
    end

    def call(name, args)
      method_name = "tool_#{name}"
      return { error: "Unknown function #{name}" } unless respond_to?(method_name, true)

      send(method_name, (args || {}).deep_stringify_keys)
    rescue UserFilter::Error, ArgumentError => e
      { error: e.message }
    rescue ActiveRecord::StatementInvalid => e
      { error: "Query failed: #{e.message.lines.first&.strip}" }
    end

    private

    def filtered(args)
      UserFilter.new(args["filter"]).scope
    end

    def matching_ids(args)
      UserFilter.new(args["filter"]).ids
    end

    def limit_arg(args, max)
      args["limit"].present? ? args["limit"].to_i.clamp(1, max) : DEFAULT_LIMIT
    end

    def ensure_allowed!(value, allowed, message)
      raise ArgumentError, "#{message}. Allowed: #{allowed.join(', ')}" unless allowed.include?(value)
    end

    def record_ui(type, **data)
      @ui_actions << { type: type, **data }
    end

    def serialize_user(user)
      user.slice(:id, :name, :email, :job_position, :status).symbolize_keys.merge(last_login_at: user.last_login_at&.iso8601)
    end

    def tool_get_current_user(_args)
      serialize_user(@user)
    end

    def tool_count_users(args)
      { count: filtered(args).count }
    end

    def tool_list_users(args)
      scope = filtered(args)
      sort_by = SORT_FIELDS.include?(args["sort_by"]) ? args["sort_by"] : User::DEFAULT_SORT_FIELD
      rows = scope.sorted_by(sort_by, User.sort_direction(args["sort_dir"])).limit(limit_arg(args, LIST_LIMIT)).map { |user| serialize_user(user) }
      { total_matching: scope.count, returned: rows.size, users: rows }
    end

    def tool_user_stats(_args)
      now = Time.current
      logged_in = User.where.not(last_login_at: nil)
      {
        total: User.count,
        active: User.active.count,
        blocked: User.blocked.count,
        **RECENT_LOGIN_WINDOWS.transform_values { |window| User.where(last_login_at: window.ago(now)..now).count },
        never_logged_in: User.where(last_login_at: nil).count,
        earliest_login: logged_in.minimum(:last_login_at)&.iso8601,
        latest_login: logged_in.maximum(:last_login_at)&.iso8601,
        top_email_domains: grouped("email_domain", User.all, TOP_STATS_LIMIT),
        top_job_positions: grouped("job_position", User.all, TOP_STATS_LIMIT),
        now: now.iso8601
      }
    end

    def tool_group_count(args)
      field = args["field"].to_s
      ensure_allowed!(field, GROUP_FIELDS.keys, "Unknown group field '#{field}'")

      scope = filtered(args)
      total_groups = scope.distinct.count(Arel.sql(GROUP_FIELDS[field]))
      { field: field, total_users: scope.count, total_groups: total_groups, groups: grouped(field, scope, limit_arg(args, MAX_GROUPS)) }
    end

    def grouped(field, scope, limit)
      expression = Arel.sql(GROUP_FIELDS[field])
      scope.group(expression).order(Arel.sql("COUNT(*) DESC"), expression).limit(limit).count
           .map { |value, count| { value: value, count: count } }
    end

    def tool_select_users(args)
      ids = matching_ids(args)
      record_ui("select", ids: ids)
      { selected_count: ids.size, note: "Matching rows are now checked in the table; all other rows were unchecked." }
    end

    def tool_clear_selection(_args)
      record_ui("clear_selection")
      { ok: true }
    end

    def tool_filter_table(args)
      ids = matching_ids(args)
      record_ui("filter", ids: ids)
      { visible_rows: ids.size }
    end

    def tool_clear_filter(_args)
      record_ui("clear_filter")
      { ok: true, visible_rows: User.count }
    end

    def tool_sort_table(args)
      field = args["field"].to_s
      ensure_allowed!(field, User::TABLE_SORT_FIELDS, "Cannot sort by '#{field}'")

      dir = User.sort_direction(args["dir"])
      record_ui("sort", field: field, dir: dir)
      { ok: true, field: field, dir: dir }
    end

    def tool_perform_action(args)
      action = args["action"].to_s
      raise ArgumentError, "Unknown action '#{action}'" unless User::BULK_ACTIONS.include?(action)

      ids = matching_ids(args)
      affected = ids.empty? ? 0 : User.apply_bulk_action(action, ids)
      record_ui("reload") if affected.positive?
      { action: action, matched: ids.size, affected: affected, current_user_affected: User.locks_out?(action, ids, @user.id) }
    end
  end
end
