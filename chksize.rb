require_relative 'cartobench'

table = ARGV.shift

if table
  config = YAML.load(File.read('config/settings.yml')).inject({}){|settings, (k,v)| settings[k.to_sym] = v; settings}
  bench = CartoBench.new config

  puts "------------------------"
  puts "Table size:"
  puts bench.table_size(table)
  puts "Table + overviews size:"
  puts bench.dataset_size(table)
  puts "------------------------"
end
