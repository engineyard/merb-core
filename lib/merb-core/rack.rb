# encoding: UTF-8

require 'rack'
module Merb
  module Rack
    autoload :Application,         'merb-core/rack/application'
    autoload :Adapter,             'merb-core/rack/adapter'
    autoload :AbstractAdapter,     'merb-core/rack/adapter/abstract'
    autoload :Ebb,                 'merb-core/rack/adapter/ebb'
    autoload :EventedMongrel,      'merb-core/rack/adapter/evented_mongrel'    
    autoload :FastCGI,             'merb-core/rack/adapter/fcgi'
    autoload :Irb,                 'merb-core/rack/adapter/irb'
    autoload :Middleware,          'merb-core/rack/middleware'
    autoload :Mongrel,             'merb-core/rack/adapter/mongrel'
    autoload :Runner,              'merb-core/rack/adapter/runner'    
    autoload :SwiftipliedMongrel,  'merb-core/rack/adapter/swiftiplied_mongrel'
    autoload :Thin,                'merb-core/rack/adapter/thin'
    autoload :ThinTurbo,           'merb-core/rack/adapter/thin_turbo'
    autoload :WEBrick,             'merb-core/rack/adapter/webrick'
    autoload :PathPrefix,          'merb-core/rack/middleware/path_prefix'
    autoload :Static,              'merb-core/rack/middleware/static'
    autoload :Profiler,            'merb-core/rack/middleware/profiler'
    autoload :Tracer,              'merb-core/rack/middleware/tracer'
    autoload :ContentLength,       'merb-core/rack/middleware/content_length'
    autoload :ConditionalGet,      'merb-core/rack/middleware/conditional_get'
    autoload :Head,                'merb-core/rack/middleware/head'
    autoload :StreamWrapper,       'merb-core/rack/stream_wrapper'
    autoload :Helpers,             'merb-core/rack/helpers'

    autoload :MockSession,        'merb-core/rack/mock_session'
  end # Rack
end # Merb
