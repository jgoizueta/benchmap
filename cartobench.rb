require 'yaml'
require 'json'
require 'uri'
require 'fileutils'

# Tables should be public (we just instantiate a mapconfig here)
# Timeout for user queries should be large enough

class CartoBench

  def initialize(options = {})
    @username = options[:username]
    @api_key = options[:api_key]
    @tiler = options[:tiler]
    @overviews_tolerance_px = options[:overviews_tolerance_px] || 1

    output_dir = options[:output_dir] || 'results'
    @directory = ->(tag) { File.join(output_dir, tag) }
    @filenaming = ->(tag, prefix, suffix) { "#{prefix}_#{tag}_#{sufffix}" }
    @curl_mode = $DEBUG ? '-v' : '--silent'
  end

  def sql(query, options = {})
    url = sql_api_url q: query
    t0 = Time.now
    results = JSON.load `curl #{@curl_mode} "#{url}"`
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

  # output directory namer
  def set_directory(&blk)
    @directory = blk
  end

  # output file namer
  def set_filenaming(&blk)
    @filenaming = blk
  end

  def directory(tag)
    @directory[tag]
  end

  def filenaming(tag, prefix, suffix)
    @filenaming[tag, prefix, suffix]
  end

  def create_map(tag, map_config_template, table)
    mapconfig = tmp_config(tag, map_config_template, table)
    result = `curl #{@curl_mode} 'https://#{@username}.cartodb.com/api/v1/map' -H 'Content-Type: application/json' -d @#{mapconfig}`
    result && JSON.load(result)['layergroupid']
  end

  def fetch_tile(tag, layergroupid, z, x, y)
    output_dir = File.join('results', tag)
    url = tile_url(layergroupid, z, x, y)
    params = tile_url_curl_params
    timing = timed_curl(url, params)
    timing_file = filenaming(tag, "tile_#{z}_#{x}_#{y}", "timings.yml")
    png_file = filenaming(tag, "tile_#{z}_#{x}_#{y}", ".png")
    write_output_file tag, timing_file, timing.to_yaml
    `curl #{@curl_mode} "#{url}" #{params} -o #{output_file(tag, png_file)}`
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
    "SELECT CDB_CreateOverviewsWithToleranceInPixels('#{table}', #{tolerance_px})"
    sql "SELECT CDB_CreateOverviewsWithToleranceInPixels('#{table}', #{tolerance_px})", timing: true
  end

  def write_output_file(tag, name, output)
    filename = output_file(tag, name)
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

  def tmp_config(tag, mapconfig_template, table)
    invalidator = Time.now.to_f.round(6).to_s
    config = mapconfig_template.gsub('{{TABLE}}', table).gsub('{{INVALIDATOR}}', invalidator)
    write_output_file(tag, "mapconfig_tmp.json", config)
  end

  def output_file(tag, name)
    dir = directory(tag)
    FileUtils.mkdir_p dir
    File.join(dir, name)
  end

  def timed_curl(url, params = nil)
    result = `curl #{@curl_mode} #{params} -w "@config/timeformat.json" -o /dev/null -s "#{url}"`
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
