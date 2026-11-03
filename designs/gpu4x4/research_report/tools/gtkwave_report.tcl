set wanted [list \
    gpu_triangle_wave_tb.start \
    gpu_triangle_wave_tb.busy \
    gpu_triangle_wave_tb.done \
    gpu_triangle_wave_tb.x0 \
    gpu_triangle_wave_tb.dut.vertex_x0 \
    gpu_triangle_wave_tb.dut.pixel_x \
    gpu_triangle_wave_tb.dut.pixel_y]
set num_added [gtkwave::addSignalsFromList $wanted]
puts "GTKWave report traces added: $num_added"
gtkwave::/Edit/Set_Trace_Max_Hier 0
gtkwave::/Time/Zoom/Zoom_Full
gtkwave::/File/Print_To_File PS {Letter (8.5" x 11")} Full triangle_wave.ps
gtkwave::/File/Quit
