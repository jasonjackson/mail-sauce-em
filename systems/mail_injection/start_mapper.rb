#!/usr/bin/env ruby

require "rubygems"
require File.dirname(__FILE__) + '/../../lib/redis-rb/lib/redis.rb' 
require File.dirname(__FILE__) + '/../../lib/nanite'

EM.run do

  # start up a new mapper with a ping time of 15 seconds
  Nanite.start_mapper(:host => 'localhost', :user => 'mapper', :pass => 'testing', :vhost => '/nanite', :log_level => 'debug', :redis => "127.0.0.1:6379", :prefetch => 1, :agent_timeout => 60, :offline_redelivery_frequency => 3600, :offline_failsafe => false, :ping_time => 15)

end


