require 'rubygems'
require 'bundler'
require 'uri'
require "digest/md5"
require 'ostruct'
require 'date'

OAUTH_CONSUMER_KEY = ENV['OAUTH_CONSUMER_KEY']
OAUTH_CONSUMER_SECRET = ENV['OAUTH_CONSUMER_SECRET']
OAUTH_AUTH_TOKEN = ENV['OAUTH_AUTH_TOKEN']

# Connect to Sandbox server?
SANDBOX = false

Bundler.require(:default, :script)
Mongo::Logger.logger.level = ::Logger::WARN

SMILEYS = {
  "icon_question" => "❓",
  "icon_wink" => "😉",
  "icon_exclaim" => "❗",
  "icon_biggrin" => "😄",
  "icon_smile" => "😊",
  "icon_sad" => "😞",
  "icon_fun" => "😄",
  "facepalm" => "😱",
  "icon_cool" => "😎",
  "icon_eek" => "😳",
  "icon_smile2" => "😃",
  "icon_doubt" => "😕",
  "icon_doubt2" => "😕",
  "icon_confused" => "😕",
  "icon_razz" => "😜",
  "icon_surprised" => "😲",
  "icon_silenced" => "🙊",
  "icon_neutral" => "😐",
  "icon_lol" => "😅",
  "fixme" => "FIXME",
  "delete" => "❌"
}

NAMESPACES = {
  "knowlegde_base" => "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  :default         => "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}

def client
  @client ||= EvernoteOAuth::Client.new(token: OAUTH_AUTH_TOKEN, consumer_key:OAUTH_CONSUMER_KEY, consumer_secret:OAUTH_CONSUMER_SECRET, sandbox: SANDBOX)
end

def user_store
  @user_store ||= client.user_store
end

def user
  @user ||= user_store.getUser(OAUTH_AUTH_TOKEN)
end

def note_store
  @note_store ||= client.note_store
end

def tag_list
  @tag_list ||= note_store.listTags(OAUTH_AUTH_TOKEN)
end

def extract_title page
  doc = Nokogiri::XML(page[:wiki_html])
  headlines = doc.css('h1').empty? ? doc.css('h2') : doc.css('h1')
  title = nil
  if (headlines.size == 1 and headlines.text.strip.size > 0)
    title = headlines.text.strip
  else
    title = page[:wiki_name]
  end
  title
end

def extract_tags page, namespaces

  wiki_tags = []
  if page[:wiki_text] =~ /{{tag\>(.+)}}/
    wiki_tags = $1.split(/\s+/)
  end

  [['dokuwiki-imported'], namespaces, wiki_tags].flatten
end

def extract_notebook_and_tags page
  root_namespace = page[:wiki_namespaces].first
  if NAMESPACES[root_namespace]
    return NAMESPACES[root_namespace], extract_tags(page, page[:wiki_namespaces].drop(1))
  else
    return NAMESPACES[:default], extract_tags(page, page[:wiki_namespaces])
  end
end

def evernote_note_body inner_html
  return %Q(<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note>#{inner_html}</en-note>)
end


def create_in_evernote page
  note = Evernote::EDAM::Type::Note.new
	note.title = page[:evernote_title]
	note.content = evernote_note_body('DUMMY')
  note.notebookGuid = page[:evernote_notebook_guid]

  begin
    print "creating #{page[:wiki_id]} ..."
    note = note_store.createNote(note)
    puts " done"
    return note.guid
  rescue Evernote::EDAM::Error::EDAMUserException => e
    puts "ERROR: #{e.message}, code: #{e.errorCode}, param: #{e.parameter}"
    puts page
    raise "abort"
  end
end

def insert_evernote_attachment(page, node, attachment)
   subpath = attachment.gsub(':', '/')
   filename = attachment.split(':').last
   path = File.expand_path("./data/media/#{subpath}")
   if File.exists?(path)
     data = File.open(path, "rb") { |io| io.read }
     hash = Digest::MD5.new.hexdigest(data)
     mimetype = MimeMagic.by_path(path).type
     page[:evernote_attachments][hash] = {
       :hash => hash,
       :path => path,
       :mime => mimetype,
       :filename => filename
     }
     node.replace("<en-media type=\"#{mimetype}\" hash=\"#{hash}\"/>")
  else
    node.replace("MISSING ATTACHMENT: #{attachment}")
  end
end

def process_anchor evernote_links, page, anchor
  case anchor['href']
  when /^(http|mailto|#|file)/
    return
  when /doku\.php\?id=([^#]+)/
    link=$1
    if evernote_links[link].nil?
      unless evernote_links[":#{link}"].nil?
        link=":#{link}"
      else
        link="#{page[:wiki_namespaces].join(':')}:#{link}"
      end
    end
    unless evernote_links[link].nil?
      anchor['href'] = evernote_links[link]
    else
      anchor.replace "<span style=\"color: red;\">UNRESOLVED LINK TO '#{link}'</span>"
    end
  when /\.\/lib\/exe\/detail\.php\?/
    anchor.remove # Remove detail links
  when /\.\/lib\/exe\/fetch\.php\?tok=\w+&media=(.*)$/
    anchor['href'] = URI.decode($1) # external link
  when /\.\/lib\/exe\/fetch\.php\?id=&media=([0-9a-z_:\-\.]+\.\w+)$/
    insert_evernote_attachment(page, anchor, $1)
  when /doku.php\?do=export_code/
    anchor.remove # code download link
  when /lib\/exe\/fetch\.php\?id=(&media=)?([A-Za-z0-9%_:\-\.]+)$/
    anchor.remove #tag links, blog/log listings -> delete
  else
    raise "Unhandled link on page #{page[:wiki_id]}: #{anchor['href']}"
  end

end


def process_image(page, img)
  case img['src']
  when /^(http)/
    return
  when /images\/smileys\/(.*).gif/
    img.replace(SMILEYS[$1])
  when /\.\/lib\/exe\/fetch\.php\?.*media=(http.*)$/
    img['src'] = URI.decode($1) # external link
  when /\.\/lib\/exe\/fetch\.php\?.*media=(.*)$/
    insert_evernote_attachment(page, img, $1)
  else
    raise "Unhandled image #{img['src']} on page #{page[:wiki_id]}"
  end
end


def process_wiki_html evernote_links, page
  page[:evernote_attachments] = {}

  doc = Nokogiri::HTML::DocumentFragment.parse(page[:wiki_html])
  doc.xpath('@id|.//@id').remove # weird because of nokogiri bug
  doc.xpath('@class|.//@class').remove # weird because of nokogiri bug
  doc.css('a').each do |anchor|
    process_anchor(evernote_links, page, anchor)
  end
  doc.css('img').each do |img|
    process_image(page, img)
  end

  return {:evernote_html => doc.to_xml, :evernote_attachments => page[:evernote_attachments] }
end

def create_evernote_attachment attachment
  binary = File.open(attachment[:path], "rb") { |io| io.read }

  data = Evernote::EDAM::Type::Data.new
  data.size = binary.size
  data.bodyHash = Digest::MD5.new.digest(binary)
  data.body = binary

  resource = Evernote::EDAM::Type::Resource.new
  resource.mime = attachment[:mime]
  resource.data = data
  resource.attributes = Evernote::EDAM::Type::ResourceAttributes.new
  resource.attributes.fileName = attachment[:filename]

  resource
end

def upload_content_to_evernote tag_guids, page
  begin
    note = note_store.getNote(OAUTH_AUTH_TOKEN, page[:evernote_guid], true, true, true, true)
    note.title = page[:wiki_name]
    note.resources = page[:evernote_attachments].map{|hash, attachment| create_evernote_attachment(attachment) }
    note.content = evernote_note_body(page[:evernote_html])
    note.tagGuids = page[:evernote_tags].map{|tag| tag_guids[tag] }.reject(&:nil?)

    print "updating #{page[:wiki_id]} ..."
    note_store.updateNote(note)
    puts " done"
  rescue Evernote::EDAM::Error::EDAMUserException => e
    puts "ERROR: #{e.message}, code: #{e.errorCode}, param: #{e.parameter}"
    # puts page[:evernote_html]
    raise "abort"
  end
end

def find_or_create_tag mongo_tag
  evernote_tag = tag_list.find{ |evernote_tag| mongo_tag[:evernote_tag] == evernote_tag.name }
  if evernote_tag
    return evernote_tag.guid
  else
    begin
      tag = Evernote::EDAM::Type::Tag.new
      tag.name = mongo_tag[:evernote_tag]

      print "creating tag #{mongo_tag[:evernote_tag]} ..."
      note_store.createTag(tag)
      puts " done"
    rescue Evernote::EDAM::Error::EDAMUserException => e
      puts "ERROR: #{e.message}, code: #{e.errorCode}, param: #{e.parameter}"
      raise "abort"
    end
  end
end

def find_tags_in_mongo(pages_collection)
  selectTags = { "$project" => { "evernote_tags" => 1 } }
  expandTags = { "$unwind" => "$evernote_tags" }
  uniqueTags = { "$group" => { "_id" => "$evernote_tags",	"count" => {	"$sum" => 1 }}}
  removeIrrelavant = { "$match" => { "_id" => /([a-z]|\d{4})/, "count" => { "$gt" => 2 } } }
  formatResponse= { "$project" => { "evernote_tag" => "$_id", "_id" => false } }
  out = { "$out" => "tags" }

  pages_collection.aggregate([selectTags, expandTags, uniqueTags, removeIrrelavant, formatResponse])
end


mongo = Mongo::Client.new([ '127.0.0.1:27016' ], :database => 'dokuwiki2evernote', :connect => :direct)
pages_collection = mongo[:pages]

query = {}

pages_collection.find(query).each do |page|
  title = extract_title(page)
  notebook_guid, tags = extract_notebook_and_tags(page)
  pages_collection.update_one({:wiki_id => page[:wiki_id]}, {"$set" => {
    :evernote_title => title,
    :evernote_notebook_guid => notebook_guid,
    :evernote_tags => tags
  }})
end

pages_collection.find(query).each do |page|
  pages_collection.update_one({:wiki_id => page[:wiki_id]}, {"$set" => {:evernote_guid => create_in_evernote(page), :evernote_created => DateTime.now()}}) if page[:evernote_guid].nil?
end

evernote_tags = {}
find_tags_in_mongo(pages_collection).each do |tag|
  evernote_guid = find_or_create_tag(tag)
  evernote_tags[tag[:evernote_tag]] = evernote_guid
end

evernote_links = {}
pages_collection.find(query).each do |page|
  evernote_links[page[:wiki_id]] = "evernote:///view/#{user.id}/#{user.shardId}/#{page[:evernote_guid]}/#{page[:evernote_guid]}"
end

pages_collection.find(query).each do |page|

  evernote_info = process_wiki_html(evernote_links, page)

  pages_collection.update_one({:wiki_id => page[:wiki_id]}, {"$set" => {
    :evernote_html => evernote_info[:evernote_html],
    :evernote_attachments => evernote_info[:evernote_attachments],
  }})
end

pages_collection.find(query).each do |page|
  if page[:evernote_uploaded].nil?
    upload_content_to_evernote(evernote_tags, page)
    pages_collection.update_one({:wiki_id => page[:wiki_id]}, {"$set" => {:evernote_uploaded => DateTime.now()}})
  end
end
