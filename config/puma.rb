max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "development" }
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }
# Worker mode (fork) is not supported on Windows; use 0 workers there
worker_count = ENV.fetch("WEB_CONCURRENCY", Gem.win_platform? ? "0" : "2").to_i
workers worker_count
preload_app! if worker_count > 0

plugin :tmp_restart
