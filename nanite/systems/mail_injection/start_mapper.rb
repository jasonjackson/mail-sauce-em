#!/usr/bin/env ruby

require "rubygems"
require File.dirname(__FILE__) + '/../../lib/redis-rb/lib/redis.rb' 
require File.dirname(__FILE__) + '/../../lib/nanite'

EM.run do

  # start up a new mapper with a ping time of 60 seconds
  Nanite.start_mapper(:host => 'sfqload01', :user => 'mapper', :pass => 'testing', :vhost => '/nanite', :log_level => 'info', :redis => "sfqload01:6379", :prefetch => 1, :agent_timeout => 120, :offline_redelivery_frequency => 600, :offline_failsafe => true, :ping_time => 15)

end


