require "test_helper"

class UserFilterTest < ActiveSupport::TestCase
  setup do
    @sam = create_user(name: "Dr. Sam Stone", email: "sam@alpha.test", job_position: "Engineer", last_login_at: 2.days.ago)
    @pat = create_user(name: "Pat Lee", email: "pat@beta.test", status: "blocked", last_login_at: 40.days.ago)
    @kim = create_user(name: "Kim Fox", email: "kim@alpha.test")
  end

  def ids(filter) = UserFilter.new(filter).scope.order(:id).pluck(:id)

  def condition(field, op, **options) = { field: field, op: op, **options }

  test "starts_with any of several values" do
    assert_equal [ @sam.id, @pat.id ], ids(conditions: [ condition("email", "starts_with", values: %w[s p]) ])
  end

  test "regex on name titles" do
    assert_equal [ @sam.id ], ids(conditions: [ condition("name", "regex", value: "^(dr|mr)\\. ") ])
  end

  test "match any, dates and null checks" do
    filter = { match: "any", conditions: [ condition("status", "equals", value: "blocked"), condition("last_login_at", "is_null") ] }
    assert_equal [ @pat.id, @kim.id ], ids(filter)
    assert_equal [ @sam.id ], ids(conditions: [ condition("last_login_at", "after", value: "7 days ago") ])
  end

  test "email domain and negation" do
    assert_equal [ @kim.id ], ids(conditions: [ condition("email_domain", "equals", value: "alpha.test"),
                                               condition("job_position", "contains", value: "engineer", negate: true) ])
  end

  test "rejects unknown fields" do
    assert_raises(UserFilter::Error) { ids(conditions: [ condition("password_digest", "equals", value: "x") ]) }
  end
end
