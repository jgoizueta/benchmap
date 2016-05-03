require 'fileutils'
require 'yaml'
require 'pp'

# data: { dataset => { ov => { z => [values] } } }
data = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = []}}}

base_dir = 'results'

# times of error results (timeouts ususally)
# should be used for averages; otherwise cases when sometimes
# timeouts happen (but now always) are artificially averaged
# to low values.
avg_errors = true

def gb(size)
  size_in_gb = (size.to_f/1024/1024/1024).round(1)
  if size_in_gb < 1
    size_in_mb = (size.to_f/1024/1024).round(1)
    "#{size_in_gb}MB"
  else
    "#{size_in_gb}GB"
  end
end


Dir["#{base_dir}/dataset_*"].each do |fn|
  dir  = File.basename(fn)
  match = /dataset_([^\/]+)/.match(dir)
  dataset = match[1]
  no = YAML.load(File.read(File.join(fn, 'no.yml')))[:size]
  ov = YAML.load(File.read(File.join(fn, 'ov.yml')))[:size]
  puts "#{dataset} #{gb no} -> #{gb ov} + #{gb ov-no}"
end
