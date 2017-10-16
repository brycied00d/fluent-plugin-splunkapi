# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |gem|
  gem.name             = "fluent-plugin-splunk-http-eventcollector"
  gem.version          = "0.4.1"
  gem.authors          = ["Bryce Chidester"]
  gem.email            = ["bryce.chidester@calyptix.com"]
  gem.summary          = "Splunk output plugin for Fluentd"
  gem.description      = "Splunk output plugin (HTTP Event Collector) for Fluentd event collector"
  gem.homepage         = "https://github.com/brycied00d/fluent-plugin-splunk-http-eventcollector"
  gem.license          = 'BSD-2-Clause'
  gem.extra_rdoc_files = [ "LICENSE", "README.md" ]
  gem.files            = [ ".gitignore", "Gemfile", "LICENSE", "README.md",
                           "Rakefile", "test/helper.rb",
                           "fluent-plugin-splunk-http-eventcollector.gemspec",
                           "lib/fluent/plugin/out_splunk-http-eventcollector.rb",
                           "test/plugin/test_out_splunk-http-eventcollector.rb" ]
  gem.test_files       = [ "test/helper.rb",
                           "test/plugin/test_out_splunk-http-eventcollector.rb" ]
  gem.require_paths    = ["lib"]

  gem.add_development_dependency "rake"
  gem.add_development_dependency "test-unit", '~> 3.1'
  gem.add_development_dependency "webmock", '~> 2.3', '>= 2.3.2'
  gem.add_runtime_dependency "fluentd", '~> 0.12.12'
  gem.add_runtime_dependency "net-http-persistent", '~> 2.9'
end
