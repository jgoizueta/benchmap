require_relative 'cartobench'

config = YAML.load(File.read('config/settings.yml')).inject({}){|settings, (k,v)| settings[k.to_sym] = v; settings}

scenarios = Dir['config/scenarios/*.yml'].map { |fn| YAML.load File.read(fn) }
styles = Dir['config/map_*.json'].map { |fn| fn.match(/\/map_(.*)\.json/)[1] }

test_tiles = [
  [14, 4824, 6157],
  [17, 38598, 49265],

  [6, 32, 23],
  [0, 0, 0],
  [2, 1, 1],
  [4, 4, 6],
  [9, 150, 192],

  [13, 2412, 3079],
  [16, 19299, 24635],
  [18, 77201, 98539],

  [13, 2413, 3080],
  [16, 19305, 24647],
  [18, 77216, 98593]
]

def gb(size)
  size_in_gb = (size.to_f/1024/1024/1024).round(1)
  "#{size_in_gb}GB"
end

NO_CREATION = true

bench = CartoBench.new config
# puts bench.sql('SHOW STATEMENT_TIMEOUT;')['rows'].first

scenarios.each do |scenario|
  tag = scenario['tag']
  table = scenario['table']
  puts "#{tag} (#{table})"

  [:no, :ov].each do |mode|

    next if NO_CREATION && mode == :no

    style = nil

    bench.set_directory do |tag|
      dir = File.join(results, tag)
      # dir = File.join(dir, mode.to_s)
      if style
        dir = File.join(dir, style)
      end
      dir
    end

    bench.set_filenaming do |tag, prefix, suffix|
      "#{prefix}_#{mode}_#{suffix}"
    end

    if mode == :no
      puts "NO OVERVIEWS"
      bench.drop_overviews table
      puts "   dropped"
    else
      puts "OVERVIEWS"
      unless NO_CREATION
        result = bench.create_overviews(table)
        t = result[:time]
        puts "  creation time: #{t}"
        filename = bench.filenaming(tag, nil, 'time', '.yml')
        bench.write_output_file tag, nil, filename, { time: t, overviews: result }.to_yaml
      end
    end

    table_size = bench.table_size(table)
    dataset_size = bench.dataset_size(table)
    puts "  Table size: #{gb(table_size)}"
    puts "  Table+Overviews size: #{gb(dataset_size)}"
    filename = bench.filenaming(tag, nil, 'size', '.yml')
    bench.write_output_file tag, nil, filename, { table: table_size, table_and_overviews: dataset_size }.to_yaml

    for style in styles # for and not each because we're using the outer x, bound to the directory proc
      puts "  style: #{style}"
      map_config_template = File.read("config/map_#{style}.json")
      test_tiles.each do |tile|
        puts "    tile: #{tile}"
        z, x, y = tile
        layergroupid = bench.create_map(tag, map_config_template, table)
        if layergroupid
          bench.fetch_tile tag, layergroupid, z, x, y
        else
          puts "MAP for #{table} FAILED"
          exit
        end
      end
    end
  end
end
