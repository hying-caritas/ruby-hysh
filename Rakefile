# -*- ruby-indent-level: 2; -*-
require "rspec/core/rake_task"
require "rdoc/task"

task :default => 'spec'

desc "Run all specs"
RSpec::Core::RakeTask.new(:spec) { |t|
  t.rspec_opts = "--colour"
  t.pattern = "spec/*_spec.rb"
}

desc "Generate document"
RDoc::Task.new { |rdoc|
  rdoc.main = "README.rdoc"
  rdoc.rdoc_files.include "README.rdoc", "lib/*.rb"
}
