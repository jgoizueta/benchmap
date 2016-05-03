require 'fileutils'
require 'yaml'
require 'pp'
require 'sys_cmd'

# data: { dataset => { ov => { z => [values] } } }
data = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = Hash.new{|k,v| k[v] = []}}}

input_dir = 'results'
output_dir = 'reports/graphs'
FileUtils.mkdir_p output_dir

# times of error results (timeouts ususally)
# should be used for averages; otherwise cases when sometimes
# timeouts happen (but now always) are artificially averaged
# to low values.
avg_errors = true

# Map data
Dir["#{input_dir}/dataset_*/*.yml"].each do |fn|
  file = File.basename(fn)
  dir  = File.dirname(fn)
  match = /dataset_([^\/]+)/.match(dir)
  dataset = match[1]
  match = /\Atile_(\d+)_\d+_\d+_[^_]+_(no|ov)_(\d+)_timings.yml\Z/.match(file)
  if match
    errors_file = File.join(dir, file.sub('_timings.yml', '_errors.yml'))
    # TODO: paint errors in different color (timeout time)
    # idea: for each series an alternative with error points,
    # then paint this firt (below) in red
    if  avg_errors || !File.exists?(errors_file)
      z = match[1].to_i
      overviews = match[2] == 'ov'

      base_table = false
      last_ov = YAML.load(File.read(File.join(input_dir, "dataset_#{dataset}", 'ov.yml')))[:overviews].last
      if last_ov && ov_match=/\A_vovw_(\d+)_/.match(last_ov)
        last_ov_level = ov_match[1].to_i
        base_table = z > last_ov_level
      end

      tile_data = YAML.load File.read(fn)
      time = tile_data && tile_data['time_total']
      if time
        data[dataset][overviews][z].push time
        data[dataset][!overviews][z].push time if base_table
      end
    end
  end
end

# Reduce data
data.each do |dataset, ov_z_values|
  ov_z_values.each do |overviews, z_values|
    reduced = {}
    z_values.keys.sort.each do |z|
      values = z_values[z]
      if values.size > 0
        reduced[z] = values.inject(&:+)/values.size.to_f
      end
    end
    data[dataset][overviews] = reduced
  end
end

# Generate CSV files
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

def gnuplot(script)
  gnuplot = SysCmd.command 'gnuplot' do
    option '-' # read commands from standard input
  end
  macros = %{
    set macros
    png="set terminal png size 600,400 crop enhanced dashlength 2; set termoption linewidth 3"
    set style line 1 linecolor rgb '#de181f' linetype 1  # Red
    set style line 2 linecolor rgb '#0060ae' linetype 1  # Blue
    set style line 3 linecolor rgb '#228C22' linetype 1  # Forest green
    set style line 4 linecolor rgb '#18ded7' linetype 1  # opposite Red
    set style line 5 linecolor rgb '#ae4e00' linetype 1  # opposite Blue
    set style line 6 linecolor rgb '#8c228c' linetype 1  # opposite Forest green
  }
  gnuplot.run stdin_data: [macros, script]*"\n"
end

missing_value = "(-)"

# Gerate DAT files & PNG charts with gnuplot
data.each do |dataset, ov_z_values|
  dat = File.open("#{output_dir}/data_#{dataset}.dat", 'w')
  dat.puts '# overviews: t:overviews:no-overviews'
  dat.puts '# x y1 y2'
  series = Hash.new{|k,v| k[v]=[nil,nil]}
  ov_z_values.each do |overviews, z_value|
    z_value = z_value.sort_by{|z, value| z.to_i}
    z_value.each do |z, value|
      index = overviews ? 1 : 0
      series[z][index] = value
    end
  end
  series.each do |z, (v1, v2)|
    dat.puts [z,v1,v2].map{|v| v||missing_value}*' '
  end
  dat.close
  gnuplot %{
    @png
    set output '#{output_dir}/data_#{dataset}.png'
    set datafile missing "#{missing_value}"
    plot "#{output_dir}/data_#{dataset}.dat" using 1:2 with lines, '' using 1:3 with lines
  }
end
