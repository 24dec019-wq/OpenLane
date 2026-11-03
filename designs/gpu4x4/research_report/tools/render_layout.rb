layout_path = ENV["GPU_LAYOUT_GDS"]
image_path = ENV["GPU_LAYOUT_PNG"]
layer_props_path = ENV["GPU_LAYOUT_LYP"]
visible_metals = ENV.fetch("GPU_VISIBLE_METALS", "345")
layout_box = ENV["GPU_LAYOUT_BOX"]
raise "Set GPU_LAYOUT_GDS and GPU_LAYOUT_PNG" if layout_path.nil? || image_path.nil?

view = RBA::LayoutView.new
view.load_layout(layout_path, true)
view.load_layer_props(layer_props_path) unless layer_props_path.nil?
view.set_config("background-color", "#ffffff")
view.set_config("grid-visible", "false")
view.set_config("text-visible", "false")
view.each_layer do |layer|
  metal = layer.name[/\Amet([1-5])\.drawing/, 1]
  via = layer.name[/\Avia([2-5]?)\.drawing/, 1]
  layer.visible = (!metal.nil? && visible_metals.include?(metal)) ||
                  (!via.nil? && visible_metals.include?(via.empty? ? "1" : via))
end
view.max_hier
if layout_box.nil?
  view.zoom_fit
else
  x1, y1, x2, y2 = layout_box.split(",").map(&:to_f)
  view.zoom_box(RBA::DBox.new(x1, y1, x2, y2))
end
view.save_image(image_path, 2000, 2000)
