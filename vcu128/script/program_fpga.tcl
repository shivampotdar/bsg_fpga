
# open hardware manager
open_hw

# connect to local hardware server
connect_hw_server

# open hardware target
open_hw_target

# set programming file
set_property PROGRAM.FILE ./design_1_wrapper.bit [get_hw_devices xcvu37p_0]

# program FPGA
program_hw_devices -verbose [get_hw_devices xcvu37p_0]

# exit
close_hw_target
