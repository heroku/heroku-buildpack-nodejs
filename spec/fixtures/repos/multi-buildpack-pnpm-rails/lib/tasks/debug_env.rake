task :debug_env do
  puts "=== RUBY BUILDPACK ENV (before assets:precompile) ==="
  ENV.sort.each { |k, v| puts "#{k}=#{v}" }
end

Rake::Task["css:install"].enhance([:debug_env])
