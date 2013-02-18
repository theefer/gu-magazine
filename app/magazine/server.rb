uri = URI.parse(ENV["REDISTOGO_URL"])
REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

get '/' do
  "hello world"
end

get '/test-set' do
  REDIS.set("foo", "bar")
end

get '/test' do
  REDIS.get("foo")
end
