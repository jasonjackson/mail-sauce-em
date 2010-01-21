#!/usr/bin/env ruby

require "rubygems"
require "dbi"
require "enumerator"
require "json"
require File.dirname(__FILE__) + '/../../lib/redis-rb/lib/redis.rb' 
require File.dirname(__FILE__) + '/../../lib/nanite'
require File.dirname(__FILE__) + '/../../lib/tenjin'
require File.dirname(__FILE__) + '/../../lib/senderoptparse.rb'

@content_dir = File.dirname(__FILE__) + '/../../systems/mail_injection/content'
@test_listname = 'campaign_preview_test'

options = SenderOptparse.parse(ARGV)

@listname = options.listname
@test = options.test

# Format the content to insert tracking codes and unsub links  (we are CAN-SPAM compliant!)
def format_content(filename)
  buffer = []
  File.new("#{@content_dir}/original/#{filename}", 'r').each { |line| buffer << line }
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


dbh = DBI.connect("dbi:Mysql:sns:sfpmysql02","user","pass")

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
ENVELOPESIZE = 1000

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

html = IO.read(html_source)
chtml = IO.read(html_cache)
txt = IO.read(txt_source)
ctxt = IO.read(txt_cache)
sub = IO.read(sub_source)
csub = IO.read(sub_cache)


member_hash = Hash.new
content_hash = Hash.new
payload = Array.new

while row = list_data.fetch do
     member_hash = { "listid" => @listid, "email" => row[0], "mailid" => row[1], "memberid" => row[2], "fname" => row[3], "lname" => row[4], "status" => row[5], "hash" => ''  }
     @data << member_hash
end
list_data.finish

content_store = Redis.new

content_store.delete "#{@listname}-html"
content_store.delete "#{@listname}-chtml"
content_store.delete "#{@listname}-txt"
content_store.delete "#{@listname}-ctxt"
content_store.delete "#{@listname}-sub"
content_store.delete "#{@listname}-csub"

content_store["#{@listname}-html"] = html
content_store["#{@listname}-chtml"] = chtml
content_store["#{@listname}-txt"] = txt
content_store["#{@listname}-ctxt"] = ctxt
content_store["#{@listname}-sub"] = sub
content_store["#{@listname}-csub"] = csub


EM.run do

  Nanite.start_mapper_proxy(:host => 'localhost', :user => 'mapper', :pass => 'testing', :vhost => '/nanite', :log_level => 'debug', :redis => "127.0.0.1:6379", :prefetch => 1, :agent_timeout => 60, :offline_redelivery_frequency => 3600, :offline_failsafe => false, :ping_time => 15)
  
  # Wait 16 seconds to ensure that the agents have pinged the mapper
  EM.add_timer(16) do

    @data.each_slice(ENVELOPESIZE) do |envelope|

      content_hash = { "timestamp" => Time.now.to_i, "listname" => @listname }

      payload = Array[content_hash, envelope]

      Nanite.push("/injection/mailer", Marshal.dump(payload), :selector => :rr)
    end
    EM.add_timer(2) { EM.stop_event_loop }
  end
end

