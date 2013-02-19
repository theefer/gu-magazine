redis_uri_string = ENV['REDISTOGO_URL'] || begin
  config = YAML.load_file("config.yml")
  config[:redis_uri]
end
redis_uri = URI.parse redis_uri_string
REDIS = Redis.new(:host => redis_uri.host, :port => redis_uri.port, :password => redis_uri.password)


class Page < Erubis::Eruby

  def initialize(name)
    input = File.read("app/templates/pages/#{name}.erb")
    super(input)
  end

end


set :public_folder, 'app/public'

before '/api*' do
  @links = []
end

helpers do
  def link(rel, path_or_hash)
    hash = if path_or_hash.is_a?(Hash)
             path_or_hash
           else
             {:href => url(path_or_hash)}
           end
    @links.push hash.merge({:rel => rel})
  end
end

def serialize(object, is_wrapped=false)
  case object
  when Array
    object.map {|item| serialize(item)}
  when Hash
    Hash[ object.map {|key, value| [key, serialize(value)]} ]
  when String, Symbol, Fixnum, FalseClass, TrueClass, NilClass
    object
  else
    raise "Cannot serialize object of class #{object.class}"
  end
end

def return_json(data={})
  content_type "application/json"
  object = {
    :data => data
  }
  object.merge!({:links => @links}) if @links && ! @links.empty?
  serialize(object).to_json
end

def content_api_uri(id)
  # FIXME: api key for outside?
  "http://content.guardianapis.com/#{id}?format=json&show-fields=all&show-media=all&api-key=techdev-internal"
end

def content_from_cache(id)
  json = REDIS.get("content:" + id)
  JSON.parse(json) if json
end

def content_to_cache(id, content)
  REDIS.set("content:" + id, content.to_json)
end

def read_content(id)
  content = content_from_cache(id)
  if ! content
    content_uri = content_api_uri(id)
    response = HTTParty.get(content_uri)
    body = JSON.parse(response.body)
    resp = body["response"]
    content = resp["content"] if resp["status"] == "ok" && resp["total"] == 1
    if content
      content_to_cache(id, content)
    end
  end
  content
end


class Bundles
  def initialize(redis)
    @redis = redis
  end

  def list
    bundle_ids = @redis.smembers "bundles"
    bundle_ids.map do |id|
      get_by_id(id)
    end
  end

  def store(bundle)
    id = bundle["id"] or raise "Missing id"
    key = make_key(id)
    @redis.set key, bundle.to_json
    @redis.sadd "bundles", id
    bundle
  end

  def get_by_id(id)
    json = @redis.get make_key(id)
    JSON.parse json if json
  end

  def remove_by_id(id)
    key = make_key(id)
    @redis.del key
    @redis.srem "bundles", id
    nil
  end

  private

  def make_key(id)
    "bundles:#{id}"
  end
end


BUNDLES = Bundles.new(REDIS)


# PAGES

get '/' do
  eruby = Page.new('index')
  eruby.result()
end

get '/editor' do
  eruby = Page.new('editor')
  eruby.result()
end

get '/magazine' do
  eruby = Page.new('magazine')
  eruby.result(:bundles => BUNDLES.list)
end

get '/magazine/:id' do
  id = params[:id]
  bundle = BUNDLES.get_by_id(id) or halt 404
  eruby = Page.new('magazine-bundle')
  eruby.result(bundle)
end

get '/magazine/:id/*' do
  id = params[:id]
  content_id = params[:splat].first
  bundle = BUNDLES.get_by_id(id) or halt 404
  content = bundle["content"].find {|c| p c; c['id'] == content_id}
  eruby = Page.new('magazine-piece')
  eruby.result(:bundle => bundle, :content => content)
end

PROFILES = [
            { :name => 'Artsy Simon',
              :favouriteSections => ['culture', 'lifeandstyle'], :ignoredSections => []},
            { :name => 'Geeky Amy',
              :favouriteSections => ['technology', 'culture', 'travel'], :ignoredSections => ['sport']},
            { :name => 'Muscly Arnold',
              :favouriteSections => ['sport'], :ignoredSections => ['culture', 'news']},
]

get '/features' do
  profile = PROFILES.find {|p| p[:name] == params[:profile]} || PROFILES.first

  bundles = BUNDLES.list

  # prepend a favourite bundle, if there is one
  if fav_bundle = bundles.find {|b| profile[:favouriteSections].first == b["section"]}
    bundles.delete(fav_bundle)
    bundles = [fav_bundle] + bundles
  end

  eruby = Page.new('features')
  eruby.result(:bundles => bundles, :profiles => PROFILES, :profile => profile)
end

get '/features/:id' do
  id = params[:id]
  bundle = BUNDLES.get_by_id(id) or halt 404

  other_bundles = BUNDLES.list.reject {|b| b["id"] == bundle["id"]}
  related_bundles = other_bundles.select {|b| b["section"] == bundle["section"]}

  eruby = Page.new('features-bundle')
  eruby.result(:bundle => bundle, :related_bundles => related_bundles)
end

get '/features/:id/*' do
  id = params[:id]
  content_id = params[:splat].first
  bundle = BUNDLES.get_by_id(id) or halt 404

  other_bundles = BUNDLES.list.reject {|b| b["id"] == bundle["id"]}
  related_bundles = other_bundles.select {|b| b["section"] == bundle["section"]}

  content = bundle["content"].find {|c| p c; c['id'] == content_id}
  eruby = Page.new('features-piece')
  eruby.result(:bundle => bundle, :content => content, :related_bundles => related_bundles)
end


# API

# BUNDLES = [{
#     :id => 'gu-magazine-issue-1',
#     :title => 'Issue 1',
# # TODO: add publication date, section, hero image, description
#     :content => [
#       read_content("world/2013/feb/18/ecuador-president-heralds-citizen-revolution"),
#       read_content("film/2013/feb/18/harrison-ford-return-star-wars"),
#       read_content("music/2013/feb/18/david-bowie-new-single-album"),
#     ]
# }]


get '/api' do
  link :bundles, '/api/bundles'
  return_json
end

get '/api/bundles' do
  bundles = BUNDLES.list
  return_json bundles
end

post '/api/bundles' do
  id = params['id'] or halt 400
  title = params['title']
  bg_uri = params['background_uri']
  section = params['section']
  new_bundle = {
    "id" => id,
    "title" => title || id,
    "background_uri" => bg_uri,
    "section" => section || "global",
    "content" => [],
  }
  BUNDLES.store(new_bundle)
  return_json new_bundle
end

get '/api/bundles/:id' do
  id = params[:id]
  bundle = BUNDLES.get_by_id(id) or halt 404
  return_json bundle
end

patch '/api/bundles/:id' do
  id = params[:id]
  bundle = BUNDLES.get_by_id(id) or halt 404
  new_data = {}
  new_data["section"] = params[:section] if params[:section]
  new_data["background_uri"] = params[:background_uri] if params[:background_uri]
  bundle = bundle.merge(new_data)
  BUNDLES.store(bundle)
  return_json bundle
end

post '/api/bundles/:bundleId/content' do
  id = params[:bundleId]
  bundle = BUNDLES.get_by_id(id) or halt 404
  content_id = params[:id]
  content = read_content(content_id) or halt 400
  bundle["content"].push(content)
  BUNDLES.store(bundle)
  return_json content
end

delete '/api/bundles/:id' do
  id = params[:id]
  BUNDLES.remove_by_id(id)
  return_json nil
end

get '/api/bundles/:id/*' do
  id = params[:id]
  content_id = params[:splat].first
  bundle = BUNDLES.get_by_id(id) or halt 404
  return_json bundle["content"].find {|c| c['id'] == content_id}
end

delete '/api/bundles/:id/*' do
  id = params[:id]
  content_id = params[:splat].first
  bundle = BUNDLES.get_by_id(id) or halt 404
  bundle["content"].reject! {|c| p c; c['id'] == content_id}
  BUNDLES.store(bundle)
  return_json nil
end

get '/api/kill' do
  REDIS.flushall
end
