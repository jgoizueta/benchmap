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
    t0 = Time.now
    results = JSON.load `curl --connect-timeout 60 -m 1800 --retry 0 #{@curl_mode} "#{url}"`
    t = Time.now - t0
    if options[:timing]
      results ||= {}
      results = results.merge time: t
    end
    results
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
    url = tile_url(layergroupid, z, x, y)
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
        JSON.load File.read(png_file)
      end
    else
      { error: 'unknown error' }
    end
  end

  def import(file, privacy = :public)
    t0 = Time.now
    api_url = "https://#{@username}.cartodb.com/api/v1/imports/?api_key=#{@api_key}"
    params = { 'privacy': privacy.to_s }
    if /\A[a-z]+:\/\// =~ file
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
      t = nil
      loop do
        sleep 5.0
        result = `curl #{@curl_mode} --silent "https://#{@username}.cartodb.com/api/v1/imports/#{id}?api_key=#{@api_key}"`
        result = JSON.load result
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
    end
    [id, t]
  end

  def drop_overviews(table)
    sql "SELECT CDB_DropOverviews('#{table}')"
  end

  def create_overviews(table, tolerance_px=@overviews_tolerance_px)
    # sql "SELECT CDB_CreateOverviewsWithToleranceInPixels('#{table}', #{tolerance_px})", timing: true
    sql "SELECT CDB_CreateOverviews('#{table}')", timing: true
  end

  def write_output_file(filename, output)
    FileUtils.mkdir_p File.dirname(filename)
    File.open(filename, 'w') do |file|
      file.write output
    end
    filename
  end

  # TODO: static maps

  private

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

  def tmp_config(mapconfig_template, table, options = {})
    invalidator = Time.now.to_f.round(6).to_s
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
