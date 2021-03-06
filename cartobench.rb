require 'rubygems'
require 'bundler/setup'

require 'yaml'
require 'json'
require 'uri'
require 'fileutils'

class CartoBench

  def initialize(options = {})
    @username = options[:username]
    @api_key = options[:api_key]
    @tiler = options[:tiler]
    @overviews_tolerance_px = options[:overviews_tolerance_px] || 1

    output_dir = options[:output_dir] || 'results'
    @curl_mode = $DEBUG ? '-v' : '--silent'
  end

  attr_accessor :tiler
  attr_reader :username

  def sql(query, options = {})
    url = sql_api_url q: query
    timed(options) do
      JSON.load `curl --connect-timeout 60 -m 1800 --retry 0 #{@curl_mode} "#{url}"`
    end
  end

  def batch_sql(query, options = {})
    url = batch_sql_api_post_url
    data = { query: query, api_key: @api_key }
    data = data.to_json.gsub("'", "'\"'\"'")
    timed(options) do
      result = JSON.load `curl -X POST --connect-timeout 60 -m 1800 --retry 0 #{@curl_mode} -H "Content-Type: application/json" -d '#{data}'  "#{url}"`
      job_id = result['job_id']
      if job_id && result['status'] == 'pending'
        url = batch_sql_api_post_url(job_id)
        exponential_loop do
          result = JSON.load `curl -X GET --connect-timeout 60 -m 1800 --retry 0 #{@curl_mode} "#{url}"`
          unless result['status'] == 'pending'
            break
          end
        end
      end
      result
    end
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

  def create_map(map_config_template, table, options = {})
    mapconfig = tmp_config(map_config_template, table, options)
    result = `curl #{@curl_mode} 'https://#{@username}.cartodb.com/api/v1/map?api_key=#{@api_key}' -H 'Content-Type: application/json' -d @#{mapconfig}`
    result && JSON.load(result)['layergroupid']
  end

  def fetch_tile(basename, layergroupid, z, x, y)
    fetch_image basename, tile_url(layergroupid, z, x, y)
  end

  def tile_parent(z, x, y)
    if z > 0
      [z - 1, x >> 1, y >> 1]
    end
  end

  def each_tile_ancestor(z, x, y)
    tile = [z, x, y]
    while tile
      yield *tile
      tile = tile_parent *tile
    end
  end

  def import(file, options = {})
    privacy = options['privacy'] || 'public'
    sync = !!!options['sync']
    params = { privacy: privacy.to_s }

    t0 = Time.now

    if sync
      base_api_url = "https://#{@username}.cartodb.com/api/v1/synchronizations"
      params['interval'] = 900
      puts "Creating a new Sync table..."
    else
      base_api_url = "https://#{@username}.cartodb.com/api/v1/imports"
      puts "Creating a new table..."
    end

    api_url = base_api_url + "/?api_key=#{@api_key}"

    if /\A[a-z]+\:\/\// =~ file
      # url
      url = file
      params['url'] = url
      result = `curl #{@curl_mode} -H "Content-Type: application/json" -d '#{params.to_json}' #{api_url}`
    else
      # file
      result = `curl #{@curl_mode} -F file=@#{file} -d '#{params.to_json}' "#{api_url}"`
    end

    result = JSON.load result
    if result['success']
      id = result['item_queue_id']
      puts "Import process with ID #{id} has started."
      t = nil
      exponential_loop do
        result = `curl #{@curl_mode} --silent "#{base_api_url}/#{id}?api_key=#{@api_key}"`
        result = JSON.load result
        puts "Checking status for #{id}..."
        puts result
        case result['state']
        when 'failure'
          t = Time.now
          puts "ERROR AFTER #{t-t0}:"
          puts result
        when 'complete'
          t = Time.now
          puts "IMPORT TIME #{t-t0}"
          break
        end
      end
    elsif result['state'] == 'created'
      puts "Sync table created. Will sync again in 15 mins."
      sleep 900.0
      result = `curl #{@curl_mode} --silent "#{base_api_url}/#{id}/sync_now?api_key=#{@api_key}"`
    end
    [id, t]
  end

  def get_import_stats(id, config)
    #TODO
  end

  def drop_overviews(table)
    sql "SELECT CDB_DropOverviews('#{table}')"
  end

  def create_overviews(table, tolerance_px=@overviews_tolerance_px)
    sql "SELECT CDB_CreateOverviewsWithToleranceInPixels('#{table}', #{tolerance_px})", timing: true
  end

  def write_output_file(filename, output)
    FileUtils.mkdir_p File.dirname(filename)
    File.open(filename, 'w') do |file|
      file.write output
    end
    filename
  end

  def static_map(basename, layergroup_id, options)
    fetch_image basename, static_map_url(layergroup_id, options)
  end

  def overview_tables(table)
    result = sql "SELECT * FROM CDB_Overviews('#{table}'::regclass)"
    result && result['rows'].map{|row|  row['overview_table']}
  end

  private

  def fetch_image(basename, url)
    params = tile_url_curl_params
    timing = timed_curl(url, params)
    timing_file = "#{basename}_timings.yml"
    png_file = "#{basename}.png"
    write_output_file timing_file, timing.to_yaml
    `curl #{@curl_mode} "#{url}?api_key=#{@api_key}" #{params} -o #{png_file}`
    if File.exist? png_file
      if `file #{png_file}` =~ /PNG image data/
        nil
      else
        begin
          png_file = File.read(png_file)
          JSON.load png_file
        rescue
          { error: png_file || 'unknown error' }
        end
      end
    else
      { error: 'unknown error' }
    end
  end

  def exponential_loop(options = {})
    sleep_time = options[:time] || 0.1
    factor = options[:factor] || 2
    limit = options[:limit] || 5.0
    timeout = options[:timeout]
    start_t = Time.now
    loop do
      if timeout
        t = Timen.now - start_t
        break if t*1E-3 >= timeout
      end
      yield
      sleep sleep_time
      if sleep_time < limit
        sleep_time *= factor
        sleep_time = limit if sleep_time > limit
      end
    end
  end

  def timed(options)
    t0 = Time.now
    results = yield
    t = Time.now - t0
    if options[:timing]
      results ||= {}
      results = results.merge time: t
    end
    results
  end

  def tile_url(layergroup_id, z, x, y)
    if @tiler
      "#{@tiler}/api/v1/map/#{layergroup_id}/#{z}/#{x}/#{y}.png"
    else
      "https://#{@username}.cartodb.com/api/v1/map/#{layergroup_id}/#{z}/#{x}/#{y}.png"
    end
  end

  def tile_url_curl_params
    if @tiler
      %{ --header "Host: #{@username}.cartodb.com" }
    else
      ''
    end
  end

  def static_map_url(layergroup_id, options)
    width = options[:width] || 500
    height = options[:height] || 500
    if options[:bbox]
      endpoint = "api/v1/map/static/bbox/#{layergroup_id}/#{bbox*','}/#{width}/#{height}.png"
    else
      lng, lat = options[:center]
      z = options[:z]
      endpoint = "api/v1/map/static/center/#{layergroup_id}/#{z}/#{lat}/#{lng}/#{width}/#{height}.png"
    end
    "https://#{@username}.cartodb.com/#{endpoint}"
  end

  def tmp_config(mapconfig_template, table, options = {})
    invalidator = Time.now.to_f.round(6).to_s + (1..6).map{rand(10)}*''
    config = mapconfig_template.gsub('{{TABLE}}', table).gsub('{{INVALIDATOR}}', invalidator)
    filename = options[:pathname] || 'tmp'
    if File.directory?(filename)
      filename = File.join(filename, "mapconfig_tmp.json")
    end
    write_output_file(filename, config)
  end

  def timed_curl(url, params = nil)
    result = `curl #{@curl_mode} #{params} -w "@config/timeformat.json" -o /dev/null -s "#{url}"`
    JSON.load(result)
  end

  def sql_api_url(params)
    "https://#{@username}.cartodb.com/api/v2/sql?#{hash_to_params(params.merge(api_key: @api_key))}"
  end

  def batch_sql_api_post_url(params = {})
    url = "https://#{@username}.cartodb.com/api/v2/sql/job"
  end

  def batch_sql_api_get_url(job_id, params = {})
    url = "https://#{@username}.cartodb.com/api/v2/sql/job/#{job_id}"
    url << "?#{hash_to_params(params.merge(api_key: @api_key))}"
    url
  end

  def hash_to_params(hash)
    hash.collect do |key, value|
      unless (value.is_a?(Hash) || value.is_a?(Array)) && value.empty?
        "#{key}=#{URI.encode value.to_s}"
      end
    end.compact.sort! * '&'
  end
end
