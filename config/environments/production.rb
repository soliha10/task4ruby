require "active_support/core_ext/integer/time"

Rails.application.configure do
  health_check_path = "/up"
  health_check_request = ->(request) { request.path == health_check_path }

  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: health_check_request } }

  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.silence_healthcheck_path = health_check_path
  config.active_support.report_deprecations = false

  config.cache_store = :memory_store
  config.active_job.queue_adapter = :async

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
  config.active_record.attributes_for_inspect = [ :id ]

  config.hosts << ".onrender.com"
  config.hosts << ENV["APP_HOST"] if ENV["APP_HOST"].present?
  config.host_authorization = { exclude: health_check_request }
end
