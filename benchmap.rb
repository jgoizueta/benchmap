require 'yaml'
require 'json'
require 'uri'
require 'fileutils'

# Tables should be public (we just instantiate a mapconfig here)
# Timeout for user queries should be large enough

class BenchMap

  def initialize()
    @settings = YAML.load File.read('config/settings.yml')
    @username = @settings['username']
    @api_key = @settings['api_key']
    @tiler = @settings['tiler']
  end

  def sql(query)
    url = sql_api_url q: query
    puts url
    JSON.load `curl --silent "#{url}"`
  end

  def table_size(table)
    result = sql "SELECT pg_total_relation_size('#{table}')"
    result['rows'].first['pg_total_relation_size']
  end

  def dataset_size(table)
    size = table_size(table)
    for overview_table in overview_tables(table)
      size += table_size(overview_table)
    end
    size
  end

  def create_map(tag, style, table)
    mapconfig = tmp_config(tag, style, table)
    result = `curl --silent 'https://#{@username}.cartodb.com/api/v1/map' -H 'Content-Type: application/json' -d @#{mapconfig}`
    result && JSON.load(result)['layergroupid']
  end

  def fetch_tile(tag, style, layergroupid, z, x, y)
    output_dir = File.join('results', tag)
    url = tile_url(layergroupid, z, x, y)
    timing = timed_curl(url)
    write_output_file tag, "tile_#{style}_#{z}_#{x}_#{y}_timings.yml", timing.to_yaml
    `curl --silent "#{url}" #{tile_url_curl_params} -o #{output_file(tag, "tile_#{style}_#{z}_#{x}_#{y}.png")}`
  end
  end

  private

  def tmp_config(tag, style, table)
    invalidator = Time.now.to_f.round(6).to_s
    config = File.read("config/map_#{style}.json").gsub('{{TABLE}}', table).gsub('{{INVALIDATOR}}', invalidator)
    write_output_file(tag, "mapconfig_#{style}.json", config)
  end

  def output_file(tag, name)
    dir = File.join('results', tag)
    FileUtils.mkdir_p dir
    File.join(dir, name)
  end

  def write_output_file(tag, name, output)
    filename = output_file(tag, name)
    File.open(filename, 'w') do |file|
      file.write output
    end
    filename
  end

  def timed_curl(url)
    result = `curl --silent -w "@config/timeformat.json" -o /dev/null -s "#{url}"`
    JSON.load(result)
  end

  def sql_api_url(params)
    "http://#{@username}.cartodb.com/api/v2/sql?#{hash_to_params(params.merge(api_key: @api_key))}"
  end

  def hash_to_params(hash)
    hash.collect do |key, value|
      unless (value.is_a?(Hash) || value.is_a?(Array)) && value.empty?
        "#{key}=#{URI.encode value.to_s}"
      end
    end.compact.sort! * '&'
  end

  def overview_tables(table)
    result = sql "SELECT * FROM CDB_Overviews('#{table}'::regclass)"
    result['rows'].map{|row|  row['overview_table']}
  end
end

scenarios = Dir['config/scenarios/*.yml'].map { |fn| YAML.load File.read(fn) }
styles = Dir['config/map_*.json'].map { |fn| fn.match(/\/map_(.*)\.json/)[1] }
test_tiles = [
  [6, 32, 23]
]

bench = BenchMap.new
# puts bench.sql('SHOW STATEMENT_TIMEOUT;')['rows'].first

scenarios.each do |scenario|
  tag = scenario['tag']
  table = scenario['table']
  puts "#{tag} (#{table})"
  puts "Table size: #{bench.table_size(table)}"
  puts "Table+Overviews size: #{bench.dataset_size(table)}"
  styles.each do |style|
    puts "style: #{style}"
    test_tiles.each do |tile|
      puts "  tile: #{tile}"
      z, x, y = tile
      layergroupid = bench.create_map(tag, style, table)
      puts "  LGID: #{layergroupid}"
      bench.fetch_tile tag, style, layergroupid, z, x, y
    end
  end
end

bench.import '/Users/jgoizueta/Downloads/cities_subset.zip'
