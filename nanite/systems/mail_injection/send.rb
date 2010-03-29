#!/usr/bin/env ruby

require "rubygems"
require "dbi"
require "enumerator"
require "json"
require File.dirname(__FILE__) + '/../../lib/redis-rb/lib/redis.rb' 
require File.dirname(__FILE__) + '/../../lib/nanite'
require File.dirname(__FILE__) + '/../../lib/tenjin'
require File.dirname(__FILE__) + '/../../lib/senderoptparse.rb'

DOMAIN = "monster.com"
DB_SERVER = "sfpmysql02"
DB_USER = "dbuser"
DB_PASSWD = "dbpass"
ENVELOPESIZE = 100


#@content_dir = '/data/distributed_email/nanite/systems/mail_injection/content'
@content_dir = '/mgr/newsletter/mail'
@test_listname = 'campaign_preview_test'

options = SenderOptparse.parse(ARGV)

@listname = options.listname
@test = options.test
@priority = options.priority

# Format the content to insert tracking codes and unsub links  (we are CAN-SPAM compliant!)
def format_content(filename)
  # Remove outdated content files.
  if File.exist?("#{@content_dir}/formatted/#{filename}")
    FileUtils.rm "#{@content_dir}/formatted/#{filename}", :force => true
  end

  buffer = []
  File.new("#{@content_dir}/#{filename}", 'r').each { |line| buffer << line }

  # Create the formatted content directory if it doesn't exist
  unless File.exist?("#{@content_dir}/formatted")
    FileUtils.mkdir_p "#{@content_dir}/formatted"
  end

  out_file = File.new("#{@content_dir}/formatted/#{filename}", 'w', 0644)
  buffer.each do |row|
    if (/monster\.com\/unsub/ =~ row)
      row.gsub!("monster.com/unsub",'monster.com/unsub?eml=#{hash}')
    elsif
      if ((/redlog\.cgi/ =~ row) || (/outlog\.cgi/ =~ row))
        if (/ESRC[^">]*code/ =~ row)
          row.gsub!(/(ESRC[^">]*)(code[^"'>]*)(["|'|>])/, '\1\2&eml=#{hash}\3')
        elsif (/url[^">]*code/ =~ row)
          row.gsub!(/(url[^">]*)(code[^"'>]*)(["|'|>])/, '\1\2&eml=#{hash}\3')
        end
      end
    end
    out_file.puts row
  end
  out_file.close
end

# Method to take a payload and push it to a nanite mapper.  We are also mapping 
# the class of the payload to the correct mapper.  This is so we can send test
# sends and priority sends to a different set of agents and a different queue in
# rabbit so that they are not backed up waiting on regular production sends.
@push_count = 0
def push_payload(data,listname)
  content_hash = { "timestamp" => Time.now.to_i, "listname" => listname }
  if @test
    payload = Array[content_hash, data]
    Nanite.push("/injection/tests", Marshal.dump(payload), :target => 'nanite-test-sends')
  elsif @priority
    data.each_slice(ENVELOPESIZE) do |envelope|
      payload = Array[content_hash, envelope]
      Nanite.push("/injection/priority", Marshal.dump(payload), :target => 'nanite-priority-sends')
    end
  else
    data.each_slice(ENVELOPESIZE) do |envelope|
      payload = Array[content_hash, envelope]
      #Nanite.push("/injection/mailer", Marshal.dump(payload), :selector => :rr)
      Nanite.push("/injection/mailer", Marshal.dump(payload), :target => 'nanite-normal-sends')
      #Nanite.push("/injection/mailer", Marshal.dump(payload), :target => 'nanite-agent1')
@push_count += 1
    end
  end
end


dbh = DBI.connect("dbi:Mysql:sns:#{DB_SERVER}","#{DB_USER}","#{DB_PASSWD}")

listid_sth = dbh.prepare("select listid from valid_lists where name = ?")

if options.test.is_a?(FalseClass)
  listid_sth.execute(@listname)
else
  listid_sth.execute(@test_listname)
end

listid_sth.fetch do |lid|
  @listid = lid.first
end
listid_sth.finish

list_data = dbh.prepare("select lower(addys.full_addy) as email, user_data.* from addys, mail_lists, user_data where mail_lists.listid = ? and addys.mailid = mail_lists.mailid and addys.mailid = user_data.mailid and addys.Black_list = 0 and addys.bounce = 0 and mail_lists.active = 1 order by addys.domain desc")

list_data.execute(@listid)

@data = Array.new

engine = Tenjin::Engine.new()
context = { :fname => '', :lname => '', :memberid => '', :mailid => '', :status => '', :hash => '' }

format_content("#{@listname}.htm")
format_content("#{@listname}.txt")
format_content("#{@listname}.sub")

html_source = "#{@content_dir}/formatted/#{@listname}.htm"
html_cache = "#{@content_dir}/formatted/#{@listname}.htm.cache"
txt_source = "#{@content_dir}/formatted/#{@listname}.txt"
txt_cache = "#{@content_dir}/formatted/#{@listname}.txt.cache"
sub_source = "#{@content_dir}/formatted/#{@listname}.sub"
sub_cache = "#{@content_dir}/formatted/#{@listname}.sub.cache"

engine.render(html_source, context)    
engine.render(txt_source, context)
engine.render(sub_source, context)

content_store = Redis.new :host => 'sfqload01.monster.com', :port => '6379'

content_store.delete "#{@listname}-html"
content_store.delete "#{@listname}-chtml"
content_store.delete "#{@listname}-txt"
content_store.delete "#{@listname}-ctxt"
content_store.delete "#{@listname}-sub"
content_store.delete "#{@listname}-csub"

content_store["#{@listname}-html"] = IO.read(html_source)
content_store["#{@listname}-chtml"] = IO.read(html_cache)
content_store["#{@listname}-txt"] = IO.read(txt_source)
content_store["#{@listname}-ctxt"] = IO.read(txt_cache)
content_store["#{@listname}-sub"] = IO.read(sub_source)
content_store["#{@listname}-csub"] = IO.read(sub_cache)


member_hash = Hash.new
content_hash = Hash.new
payload = Array.new


while row = list_data.fetch do
     member_hash = { "listid" => @listid, "email" => row[0], "mailid" => row[1], "memberid" => row[2], "fname" => row[3], "lname" => row[4], "status" => row[5], "hash" => ''  }
     @data << member_hash
end
list_data.finish

puts "list size: #{@data.size}"

EM.run do

  Nanite.start_mapper_proxy(:host => 'sfqload01', :user => 'mapper', :pass => 'testing', :vhost => '/nanite', :log_level => 'info', :redis => "sfqload01:6379", :prefetch => 1, :agent_timeout => 120, :offline_redelivery_frequency => 600, :offline_failsafe => true, :ping_time => 15)
  
  # Wait 16 seconds to ensure that the agents have pinged the mapper
  EM.add_timer(16) do

    push_payload(@data,@listname)

    EM.add_timer(30) { EM.stop_event_loop }

  end
end

puts "pushed: #{@push_count}"


