# Generate output CSV from input points CSV creating multiple copies
# of each point (origin + `copies` copies).
# Uses longitude and latitude columns for the coordinates.

require 'rgeo'
gfactory = RGeo::Cartesian.method(:preferred_factory)[srid: 4326]
ewkb = RGeo::WKRep::WKBGenerator.new(hex_format: true, type_format: :ewkb, emit_ewkb_srid: true)

id_offset = 15000000
x_offset = 60.0
y_offset = -1.0
copies = 2
input_file = '/Users/jgoizueta/Downloads/yellow_tripdata_2015_pickups.csv'
output_file = 'multicabs.csv'
new_id = true

output = File.open(output_file, 'w')

n = 0
id = 0
t0 = Time.new
File.open(input_file, 'r').each_line do |line|
  n += 1
  if n == 1
    output.puts "cartodb_id,the_geom,total_amount"
  else
    fields = line.split(',')
    cartodb_id, the_geom, lon, lat, total_amount = fields.values_at(0,1,7,8,19)
    cartodb_id = cartodb_id.to_i
    id += 1
    if new_id
      cartodb_id = id
    end
    output.puts [cartodb_id, the_geom, total_amount]*','
    x = lon.to_f
    y = lat.to_f
    copies.times do |i|
      x += x_offset
      y += y_offset
      p = gfactory.point x, y
      the_geom = ewkb.generate p
      id += 1
      if new_id
        cartodb_id = id
      else
        cartodb_id += id_offset
      end
      output.puts [cartodb_id, the_geom, total_amount]*','
    end
  end
  # break if n == 10000
end

t = Time.new - t0
puts t
# puts (14.0E6/n)*t

output.close
