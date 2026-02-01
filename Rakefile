require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  desc "Run PostgreSQL specs only"
  RSpec::Core::RakeTask.new(:postgresql) do |t|
    t.rspec_opts = "--tag postgresql"
  end

  desc "Run MySQL specs only"
  RSpec::Core::RakeTask.new(:mysql) do |t|
    t.rspec_opts = "--tag mysql"
  end
end

task default: :spec
