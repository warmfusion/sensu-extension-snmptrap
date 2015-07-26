lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'date'

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
  require 'sensu-plugins-snmptrap-extension'
else
  require_relative 'lib/sensu-plugins-snmptrap-extension'
end

pvt_key = '~/.ssh/gem-private_key.pem'

Gem::Specification.new do |s|
  s.authors                = [ 'Toby Jackson <toby@warmfusion.co.uk>',
                               'Peter Daugavietis <pdaugavietis@gmail.com>']
  s.cert_chain             = ['certs/sensu-plugins.pem']
  s.date                   = Date.today.to_s
  s.description            = 'Sensu extension for trapping SNMP events and reemiting as templated events'
  s.email                  = '<toby@warmfusion.co.uk>'
  s.executables            = Dir.glob('bin/**/*.rb').map { |file| File.basename(file) }
  s.files                  = Dir.glob('{bin,lib}/**/*') + %w(LICENSE README.md CHANGELOG.md)
  s.homepage               = 'https://github.com/warmfusion/sensu-sensu-extension-snmptrap'
  s.license                = 'MIT'
  s.metadata               = { 'maintainer'         => '@warmfusion',
                               'development_status' => 'active',
                               'production_status'  => 'unstable - testing recommended',
                               'release_draft'      => 'false',
                               'release_prerelease' => 'false'
                              }
  s.name                   = 'sensu-plugins-snmptrap-extension'
  s.platform               = Gem::Platform::RUBY
  s.post_install_message   = 'You can use the embedded Ruby by setting EMBEDDED_RUBY=true in /etc/default/sensu'
  s.require_paths          = ['lib']
  s.required_ruby_version  = '>= 1.9.3'
  s.signing_key            = File.expand_path(pvt_key) if $PROGRAM_NAME =~ /gem\z/
  s.summary                = 'Sensu extension to capture SNMP trap events'
  s.test_files             = s.files.grep(%r{^(test|spec|features)/})
  s.version                = SensuPluginsSnmptrapExtension::Version::VER_STRING

  s.add_runtime_dependency 'snmp',  '1.2.0'
  s.add_runtime_dependency 'sensu-plugin',  '1.2.0'
  s.add_runtime_dependency 'net'
  s.add_runtime_dependency 'json'

  s.add_development_dependency 'bundler',                   '~> 1.7'
  s.add_development_dependency 'codeclimate-test-reporter', '~> 0.4'
  s.add_development_dependency 'github-markup',             '~> 1.3'
  s.add_development_dependency 'pry',                       '~> 0.10'
  s.add_development_dependency 'rake',                      '~> 10.0'
  s.add_development_dependency 'rspec',                     '~> 3.1'
  s.add_development_dependency 'rubocop',                   '0.32.1'
  s.add_development_dependency 'redcarpet',                 '~> 3.2'
  s.add_development_dependency 'yard',                      '~> 0.8'
end
