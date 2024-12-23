set_fml_appmode FPV 
set design simple_router 

read_file -top i2c_master_slave -format sverilog -sva -vcs {-f ../RTL/filelist}

create_clock clk -period 100
create_reset rst -sense high

sim_run -stable
sim_save_reset
