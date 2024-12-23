#################################################
# aep_run.tcl
# ECE560 ABV
# I2C Verification
# ##############################################

set_fml_appmode AEP
set design i2c_master_slave
set_fml_var fml_aep_unique_name true

##enable VC Formal to dump FSM report
set_app_var fml_enable_fsm_report_complexity true
set_app_var fml_trace_auto_fsm_state_extraction true

## you could add one switch at a time to check for certain properties
read_file -top $design -format sverilog -aep all+fsm_deadlock -vcs {../RTL/i2c_gpt.sv}

create_clock clk -period 100 
create_reset rst -sense high

sim_run -stable 
sim_save_reset

