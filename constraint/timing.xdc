create_clock -period 10.000 -name clk_p -waveform {0.000 5.000} [get_ports clk_p]
create_clock -period 100.000 -name BSCANE2_inst1/TCK -waveform {0.000 50.000} [get_pins BSCANE2_inst1/TCK]
