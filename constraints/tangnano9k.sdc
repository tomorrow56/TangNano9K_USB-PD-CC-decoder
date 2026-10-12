create_clock -name clk -period 37.037 [get_ports {clk}]
set_false_path -from [get_ports {cc_bmc}]
