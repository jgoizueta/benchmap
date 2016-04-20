require_relative 'cartobench'

config = YAML.load(File.read('config/settings.yml')).inject({}){|settings, (k,v)| settings[k.to_sym] = v; settings}

config = config.merge username: 'iriberri', api_key: 'ed860f6f27320761f5c1cf4b005e7a352c34d3b9'
puts config

def gb(size)
  size_in_gb = (size.to_f/1024/1024/1024).round(1)
  "#{size_in_gb}GB"
end


test_tiles = [
  [6, 32, 23],
  [0, 0, 0],
  [2, 1, 1],
  [4, 4, 6],
  [9, 150, 192],

  [14, 4824, 6157],
  [17, 38598, 49265],

  [13, 2412, 3079],
  [16, 19299, 24635],
  [18, 77201, 98539],

  [13, 2413, 3080],
  [16, 19305, 24647],
  [18, 77216, 98593]
]

table = 'yellowcabs_tripdata_2015_pickups'

[
  ['good', 'http://api02.useb.cartodb.net:8181'],
  ['bad',  'http://api03.useb.cartodb.net:8181']
].each do |name, tiler|
  bench = CartoBench.new config.merge(tiler: tiler)
  puts "USER: #{bench.instance_variable_get('@username')}"
  tag = 'twkb_2px'
  style = 'bitmap'
  map_config_template = File.read("config/map_#{style}.json")

  test_tiles.each do |tile|
    puts "    tile: #{tile}"
    z, x, y = tile
    layergroupid = bench.create_map(map_config_template, table)
    if layergroupid
      path = File.join 'results', tag, "tile_#{z}_#{x}_#{y}_#{name}"
      bench.fetch_tile path, layergroupid, z, x, y
    else
      puts "MAP for #{table} FAILED"
      exit
    end
  end

end

# puts bench.sql('SHOW STATEMENT_TIMEOUT;')['rows'].first


# bench.import '/Users/jgoizueta/Downloads/cities_subset.zip'

# bench.drop_overviews 'cities'
# result = bench.create_overviews 'cities'
# puts result

# result = bench.create_overviews 'cities', 0.5
# puts result

# tag = 'test'
# style = 'bitmap'
# z, x, y = 9, 150, 192
# table = 'yellowcabs_tripdata_2015_pickups'
# layergroupid = bench.create_map(tag, style, table)
# puts layergroupid
# bench.fetch_tile tag, style, layergroupid, z, x, y
