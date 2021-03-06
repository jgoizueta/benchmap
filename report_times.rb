require 'fileutils'
require 'yaml'
require 'pp'

# data: { dataset => { ov => { z => [values] } } }
data = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = []}}}

input_dir = 'results'

output_dir = 'reports'
FileUtils.mkdir_p output_dir

# times of error results (timeouts ususally)
# should be used for averages; otherwise cases when sometimes
# timeouts happen (but now always) are artificially averaged
# to low values.
avg_errors = true

def zoom_bucket(z)
  if z <= 5
    0
  elsif z <= 10
    1
  else
    2
  end
end

# use this approach to detect outliers: http://mathworld.wolfram.com/Outlier.html
# * High outliers are anything beyond the 3rd quartile + 1.5 * the inter-quartile range (IQR)
# * Low outliers are anything beneath the 1st quartile - 1.5 * IQR
def filter_outliers(values)
  values = values.sort

  q1 = values[values.size / 4]
  q3 = values[(values.size * 3) / 4]
  iqr = q3 - q1;
  max_value = q3 + iqr * 1.5
  min_value = q1 - iqr * 1.5

  values.select { |v| v > min_value && v < max_value }
end

Dir["#{input_dir}/dataset_*/*.yml"].each do |fn|
  file = File.basename(fn)
  dir  = File.dirname(fn)
  match = /dataset_([^\/]+)/.match(dir)
  dataset = match[1]
  match = /\Atile_(\d+)_\d+_\d+_[^_]+_(no|ov)_(\d+)_timings.yml\Z/.match(file)
  if match
    errors_file = File.join(dir, file.sub('_timings.yml', '_errors.yml'))
    z = match[1].to_i
    overviews = match[2] == 'ov'

    base_table = false
    last_ov = YAML.load(File.read(File.join(input_dir, "dataset_#{dataset}", 'ov.yml')))[:overviews].last
    if last_ov && ov_match=/\A_vovw_(\d+)_/.match(last_ov)
      last_ov_level = ov_match[1].to_i
      base_table = z > last_ov_level
    end
    zb = zoom_bucket(z)

    tile_data = YAML.load File.read(fn)
    time = tile_data && tile_data['time_total']
    if time
      data[dataset][overviews][zb].push time
      data[dataset][!overviews][zb].push time if base_table
    end
  end
end


data.each do |dataset, ov_z_values|
  ov_z_values.each do |overviews, z_values|
    reduced = {}
    z_values.keys.sort.each do |z|
      values = filter_outliers z_values[z]
      if values.size > 0
        reduced[z] = values.inject(&:+)/values.size.to_f
      end
    end
    data[dataset][overviews] = reduced
  end
end

data.each do |dataset, ov_z_values|
  csv = File.open("#{output_dir}/data_#{dataset}.csv", 'w')
  csv.puts 'z,no_ov,overviews'
  series = Hash.new{|k,v| k[v]=[nil,nil]}
  ov_z_values.each do |overviews, z_value|
    z_value = z_value.sort_by{|z, value| z.to_i}
    z_value.each do |z, value|
      index = overviews ? 1 : 0
      series[z][index] = value
    end
  end
  series.each do |z, (v1, v2)|
    csv.puts [z,v1,v2]*','
  end
  csv.close
end
