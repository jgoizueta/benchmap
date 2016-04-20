require_relative 'cartobench'

config = YAML.load(File.read('config/settings.yml')).inject({}){|settings, (k,v)| settings[k.to_sym] = v; settings}

NO_CREATION = true
NO_DESTRUCTION = true

scenarios = {
  ov: ->(bench, table){
    puts "OVERVIEWS"
    unless NO_CREATION
      result = bench.create_overviews(table)
      t = result[:time]
      puts "  creation time: #{t}"
      { overviews: { time: t, overviews: result } }
    else
      result = bench.send :overview_tables, table
      { overviews: result }
    end
  } #,
  # no: ->(bench, table) {
  #   puts "NO OVERVIEWS"
  #   unless NO_DESTRUCTION
  #     bench.drop_overviews table
  #     puts "   dropped"
  #   end
  #   {}
  # }
}
datasets = Dir['config/datasets/*.yml'].map { |fn| YAML.load File.read(fn) }
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

bench = CartoBench.new config
# puts bench.sql('SHOW STATEMENT_TIMEOUT;')['rows'].first

datasets.each do |dataset|
  dataset_name = dataset['tag']
  table = dataset['table']
  puts "#{dataset_name} (#{table})"
  info = {}

  scenarios.each do |scenario_name, scenario|
    info.merge! scenario[bench, table]
    table_size = bench.table_size(table)
    dataset_size = bench.dataset_size(table)
    info.merge! size: dataset_size
    puts "  Table size: #{gb(table_size)}"
    puts "  Table+Overviews size: #{gb(dataset_size)}"

    info_filename = File.join('results', dataset_name, "#{scenario_name}.yml")
    bench.write_output_file info_filename, info.to_yaml

    styles.each do |style|
      puts "  style: #{style}"
      map_config_template = File.read("config/map_#{style}.json")
      test_tiles.each do |tile|
        puts "    tile: #{tile}"
        z, x, y = tile
        layergroupid = bench.create_map(map_config_template, table)
        tile_base_name = "tile_#{z}_#{x}_#{y}_#{style}_#{scenario_name}"
        path = File.join('results', dataset_name, tile_base_name)
        if layergroupid
          errors = bench.fetch_tile path, layergroupid, z, x, y
        else
          puts "MAP for #{table} FAILED"
          exit
        end
        if errors
            bench.write_output_file "#{path}_errors.yml", errors.to_yaml
        end
      end
    end
  end
end
