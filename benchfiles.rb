require_relative 'cartobench'

config = YAML.load(File.read('config/settings.yml')).inject({}){|settings, (k,v)| settings[k.to_sym] = v; settings}

NO_CREATION = true
NO_DESTRUCTION = true

datasets = Dir['config/datasets/*.yml'].map { |fn| YAML.load File.read(fn) }

puts datasets

def gb(size)
  size_in_gb = (size.to_f/1024/1024/1024).round(1)
  "#{size_in_gb}GB"
end

bench = CartoBench.new config

datasets.each do |dataset|
  dataset_name = dataset['tag']
  table = dataset['table']
  download_url = dataset['source']
  puts "#{dataset_name} (#{table})"
  options = {:sync => true}

  puts "================================"
  puts " Starting import for #{table} "
  puts "================================"

  bench.import(download_url, options)
  puts "================================"
  puts " IMPORT FINISHED "
  puts "================================"
  #TODO: get id to collect stats
end
