class User < ApplicationRecord
  BULK_ACTIONS = %w[block unblock delete].freeze
  LOCKOUT_ACTIONS = %w[block delete].freeze
  STATUS_BY_ACTION = { "block" => "blocked", "unblock" => "active" }.freeze
  TABLE_SORT_FIELDS = %w[name email last_login_at status].freeze
  DEFAULT_SORT_FIELD = "last_login_at".freeze

  has_secure_password

  enum :status, { active: "active", blocked: "blocked" }, default: "active", validate: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :sorted_by, ->(field, dir) { order(arel_table[field].public_send(dir).nulls_last, :id) }

  def self.find_by_login(email)
    find_by(email: email.to_s)
  end

  def self.sort_direction(dir)
    dir.to_s == "asc" ? "asc" : "desc"
  end

  def self.table_sort_field(field)
    TABLE_SORT_FIELDS.include?(field) ? field : DEFAULT_SORT_FIELD
  end

  def self.locks_out?(action, ids, user_id)
    LOCKOUT_ACTIONS.include?(action.to_s) && ids.include?(user_id)
  end

  def self.apply_bulk_action(action, ids)
    scope = where(id: Array(ids))
    return scope.destroy_all.size if action.to_s == "delete"

    status = STATUS_BY_ACTION.fetch(action.to_s) { raise ArgumentError, "Unknown action: #{action}" }
    scope.update_all(status: status, updated_at: Time.current)
  end
end
