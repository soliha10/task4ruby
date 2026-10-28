if User.exists? && ENV["RESEED"].blank?
  puts "Users already present (#{User.count}); skipping seeds. Set RESEED=1 to replace them."
  return
end

seed_password = "password"
records = JSON.parse(File.read(Rails.root.join("db/seeds/users.json")))
digest = BCrypt::Password.create(seed_password)
now = Time.current

rows = records.map do |record|
  {
    name: record.fetch("full_name"),
    email: User.normalize_value_for(:email, record.fetch("email")),
    job_position: record["job_position"],
    status: record.fetch("status"),
    last_login_at: record["last_seen"].presence && Time.zone.parse(record["last_seen"]),
    password_digest: digest,
    created_at: now,
    updated_at: now
  }
end

User.transaction do
  User.delete_all if ENV["RESEED"].present?
  User.insert_all!(rows)
end

puts "Seeded #{User.count} users (password: \"#{seed_password}\")."
