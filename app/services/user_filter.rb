class UserFilter
  class Error < StandardError; end

  TEXT_FIELDS = {
    "name" => "users.name",
    "email" => "users.email",
    "email_domain" => "split_part(users.email, '@', 2)",
    "job_position" => "users.job_position",
    "status" => "users.status"
  }.freeze
  DATE_FIELDS = { "last_login_at" => "users.last_login_at" }.freeze
  FIELDS = (TEXT_FIELDS.keys + DATE_FIELDS.keys).freeze

  TEXT_OPS = %w[equals not_equals contains not_contains starts_with ends_with regex is_null not_null].freeze
  DATE_OPS = %w[equals before after between is_null not_null].freeze
  NEGATIVE_OPS = %w[not_equals not_contains].freeze
  RELATIVE_TIME = /\A(\d+)\s+(minute|hour|day|week|month|year)s?\s+ago\z/

  def initialize(filter = nil)
    filter = (filter || {}).to_h.deep_stringify_keys
    @match = filter["match"] == "any" ? "any" : "all"
    @conditions = Array(filter["conditions"]).map { |condition| condition.to_h.stringify_keys }
  end

  def scope(relation = User.all)
    clauses = @conditions.map { |condition| condition_sql(condition) }
    return relation if clauses.empty?

    relation.where(clauses.map { |sql| "(#{sql})" }.join(@match == "any" ? " OR " : " AND "))
  end

  def ids
    scope.order(:id).pluck(:id)
  end

  private

  def condition_sql(condition)
    sql = field_sql(condition["field"].to_s, condition["op"].to_s, condition_values(condition))
    condition["negate"] ? "NOT COALESCE((#{sql}), FALSE)" : sql
  end

  def condition_values(condition)
    values = Array(condition["values"]).map(&:to_s)
    values.empty? && !condition["value"].nil? ? [ condition["value"].to_s ] : values
  end

  def field_sql(field, op, values)
    return text_condition(TEXT_FIELDS[field], op, values) if TEXT_FIELDS.key?(field)
    return date_condition(DATE_FIELDS[field], op, values) if DATE_FIELDS.key?(field)

    raise Error, "Unknown field '#{field}'. Allowed: #{FIELDS.join(', ')}"
  end

  def ensure_operator!(op, allowed, kind)
    raise Error, "Operator '#{op}' is not valid for #{kind}. Allowed: #{allowed.join(', ')}" unless allowed.include?(op)
  end

  def text_condition(column, op, values)
    ensure_operator!(op, TEXT_OPS, "text fields")
    return "#{column} IS NULL OR #{column} = ''" if op == "is_null"
    return "#{column} IS NOT NULL AND #{column} <> ''" if op == "not_null"
    raise Error, "Operator '#{op}' requires a value" if values.empty?

    values.map { |value| text_part(column, op, value) }.join(NEGATIVE_OPS.include?(op) ? " AND " : " OR ")
  end

  def text_part(column, op, value)
    like = ActiveRecord::Base.sanitize_sql_like(value)
    case op
    when "equals"       then sanitize("LOWER(#{column}) = LOWER(?)", value)
    when "not_equals"   then sanitize("LOWER(COALESCE(#{column}, '')) <> LOWER(?)", value)
    when "contains"     then sanitize("#{column} ILIKE ?", "%#{like}%")
    when "not_contains" then sanitize("COALESCE(#{column}, '') NOT ILIKE ?", "%#{like}%")
    when "starts_with"  then sanitize("#{column} ILIKE ?", "#{like}%")
    when "ends_with"    then sanitize("#{column} ILIKE ?", "%#{like}")
    when "regex"        then sanitize("#{column} ~* ?", validated_regex(value))
    end
  end

  def date_condition(column, op, values)
    ensure_operator!(op, DATE_OPS, "dates")
    return "#{column} IS NULL" if op == "is_null"
    return "#{column} IS NOT NULL" if op == "not_null"

    times = values.map { |value| parse_time(value) }
    case op
    when "before"  then sanitize("#{column} < ?", times.first)
    when "after"   then sanitize("#{column} > ?", times.first)
    when "between" then between_sql(column, times)
    when "equals"  then times.map { |time| day_sql(column, time) }.join(" OR ")
    end
  end

  def between_sql(column, times)
    raise Error, "Operator 'between' requires two values" if times.size < 2

    from, to = times.first(2).sort
    sanitize("#{column} BETWEEN ? AND ?", from, to)
  end

  def day_sql(column, time)
    sanitize("#{column} BETWEEN ? AND ?", time.beginning_of_day, time.end_of_day)
  end

  def parse_time(value)
    case value.to_s.strip.downcase
    when "now" then Time.current
    when "today" then Time.current.beginning_of_day
    when "yesterday" then 1.day.ago.beginning_of_day
    when RELATIVE_TIME then Regexp.last_match(1).to_i.public_send(Regexp.last_match(2)).ago
    else Time.zone.parse(value.to_s) || raise(ArgumentError)
    end
  rescue ArgumentError
    raise Error, "Cannot parse date '#{value}'. Use ISO 8601 (e.g. 2026-01-31) or 'N days ago'."
  end

  def validated_regex(value)
    Regexp.new(value)
    value
  rescue RegexpError => e
    raise Error, "Invalid regular expression '#{value}': #{e.message}"
  end

  def sanitize(sql, *binds)
    ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
  end
end
