# Xilinx Vivado script
# Version: Vivado 2014.4
# Function:
#   Generate a vivado project for the loRISC SoC

set mem_data_width {128}
set axi_id_width {8}

set origin_dir "."
set project_name [lindex $argv 0]
set CONFIG [lindex $argv 1]
set common_dir "../../common"

# Set the directory path for the original project from where this script was exported
set orig_proj_dir [file normalize $origin_dir/$project_name]

# Create project
create_project $project_name $origin_dir/$project_name

# Set the directory path for the new project
set proj_dir [get_property directory [current_project]]

# Set project properties
set obj [get_projects $project_name]
set_property "board_part" "xilinx.com:kc705:part0:1.1" $obj
set_property "default_lib" "xil_defaultlib" $obj
set_property "simulator_language" "Mixed" $obj

# Create 'sources_1' fileset (if not found)
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

# Set 'sources_1' fileset object
set files [list \
               [file normalize $origin_dir/generated-src/Top.$CONFIG.v] \
               [file normalize $origin_dir/../../../vsrc/chip_top.sv] \
               [file normalize $origin_dir/../../../vsrc/axi_bram_ctrl_top.sv] \
               [file normalize $origin_dir/../../../vsrc/axi_crossbar_top.sv] \
               [file normalize $origin_dir/../../../socip/nasti/channel.sv] \
              ]
add_files -norecurse -fileset [get_filesets sources_1] $files

# add include path
set_property include_dirs [list \
                               [file normalize $origin_dir/src ]\
                               [file normalize $origin_dir/generated-src] \
                              ] [get_filesets sources_1]

set_property verilog_define FPGA [get_filesets sources_1]

# Set 'sources_1' fileset properties
set_property "top" "chip_top" [get_filesets sources_1]

#UART
create_ip -name axi_uart16550 -vendor xilinx.com -library ip -version 2.0 -module_name axi_uart16550_0
set_property -dict [list \
                        CONFIG.UART_BOARD_INTERFACE {Custom} \
                        CONFIG.C_S_AXI_ACLK_FREQ_HZ_d {200} \
                       ] [get_ips axi_uart16550_0]
generate_target {instantiation_template} \
    [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_uart16550_0/axi_uart16550_0.xci]

#BRAM Controller
create_ip -name axi_bram_ctrl -vendor xilinx.com -library ip -version 4.0 -module_name axi_bram_ctrl_0
set_property -dict [list \
                        CONFIG.DATA_WIDTH $mem_data_width \
                        CONFIG.ID_WIDTH $axi_id_width \
                        CONFIG.MEM_DEPTH {4096} \
                        CONFIG.PROTOCOL {AXI4} \
                        CONFIG.BMG_INSTANCE {EXTERNAL} \
                        CONFIG.SINGLE_PORT_BRAM {1} \
                        CONFIG.SUPPORTS_NARROW_BURST {1} \
                        CONFIG.ECC_TYPE {0} \
                       ] [get_ips axi_bram_ctrl_0]
generate_target {instantiation_template} \
    [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_bram_ctrl_0/axi_bram_ctrl_0.xci]

# Memory Controller
create_ip -name mig_7series -vendor xilinx.com -library ip -version 2.3 -module_name mig_7series_0
set_property CONFIG.XML_INPUT_FILE [file normalize $origin_dir/script/mig_config.prj] [get_ips mig_7series_0]
generate_target {instantiation_template} \
    [get_files $proj_dir/$project_name.srcs/sources_1/ip/mig_7series_0/mig_7series_0.xci]

# AXI Crossbar
create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name axi_crossbar_mem
set_property -dict [list \
                        CONFIG.STRATEGY {2} \
                        CONFIG.DATA_WIDTH $mem_data_width \
                        CONFIG.ID_WIDTH $axi_id_width \
                        CONFIG.S00_WRITE_ACCEPTANCE {2} \
                        CONFIG.S00_READ_ACCEPTANCE {2} \
                        CONFIG.M00_WRITE_ISSUING {1} \
                        CONFIG.M01_WRITE_ISSUING {2} \
                        CONFIG.M00_READ_ISSUING {1} \
                        CONFIG.M00_A00_ADDR_WIDTH {16} \
                        CONFIG.M01_READ_ISSUING {2} \
                        CONFIG.M01_A00_BASE_ADDR {0x0000000040000000} \
                        CONFIG.M01_A00_ADDR_WIDTH {30} \
                        CONFIG.CONNECTIVITY_MODE {SAMD} \
                        CONFIG.S00_THREAD_ID_WIDTH {8} \
                        CONFIG.S01_WRITE_ACCEPTANCE {4} \
                        CONFIG.S01_READ_ACCEPTANCE {4} \
                        CONFIG.S01_BASE_ID {0x00000100} ] \
    [get_ips axi_crossbar_mem]
generate_target {instantiation_template} [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_crossbar_mem/axi_crossbar_mem.xci]

# AXI clock converter due to the clock difference
create_ip -name axi_clock_converter -vendor xilinx.com -library ip -version 2.1 -module_name axi_clock_converter_0
set_property -dict [list \
                        CONFIG.ADDR_WIDTH {30} \
                        CONFIG.DATA_WIDTH $mem_data_width \
                        CONFIG.ID_WIDTH $axi_id_width \
                        CONFIG.ACLK_ASYNC {0} \
                        CONFIG.ACLK_RATIO {1:4}] \
    [get_ips axi_clock_converter_0]
generate_target {instantiation_template} [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_clock_converter_0/axi_clock_converter_0.xci]

# SPI interface for R/W SD card
create_ip -name axi_quad_spi -vendor xilinx.com -library ip -version 3.2 -module_name axi_quad_spi_0
set_property -dict [list \
                        CONFIG.C_USE_STARTUP {0} \
                        CONFIG.C_SCK_RATIO {4} \
                        CONFIG.C_NUM_TRANSFER_BITS {8}] \
    [get_ips axi_quad_spi_0]
generate_target {instantiation_template} [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_quad_spi_0/axi_quad_spi_0.xci]

# crossbar for IO space (AXI-Lite)
create_ip -name axi_crossbar -vendor xilinx.com -library ip -version 2.1 -module_name axi_crossbar_io
set_property -dict [list \
                        CONFIG.PROTOCOL {AXI4LITE} \
                        CONFIG.ADDR_WIDTH {28} \
                        CONFIG.CONNECTIVITY_MODE {SASD} \
                        CONFIG.R_REGISTER {0} \
                        CONFIG.S00_WRITE_ACCEPTANCE {1} \
                        CONFIG.S00_READ_ACCEPTANCE {1} \
                        CONFIG.M00_WRITE_ISSUING {1} \
                        CONFIG.M01_WRITE_ISSUING {1} \
                        CONFIG.M00_READ_ISSUING {1} \
                        CONFIG.M01_READ_ISSUING {1} \
                        CONFIG.M00_A00_ADDR_WIDTH {16} \
                        CONFIG.M01_A00_BASE_ADDR {0x0000000000010000} \
                        CONFIG.M01_A00_ADDR_WIDTH {16} \
                        CONFIG.S00_SINGLE_THREAD {1}] \
    [get_ips axi_crossbar_io]
generate_target {instantiation_template} [get_files $proj_dir/$project_name.srcs/sources_1/ip/axi_crossbar_io/axi_crossbar_io.xci]

# Create 'constrs_1' fileset (if not found)
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

# Set 'constrs_1' fileset object
set obj [get_filesets constrs_1]

# Add/Import constrs file and set constrs file properties
set file "[file normalize "$origin_dir/constraint/pin_plan.xdc"]"
set file_added [add_files -norecurse -fileset $obj $file]

# generate all IP source code
generate_target all [get_ips]

# force create the synth_1 path (need to make soft link in Makefile)
launch_runs -scripts_only synth_1


# Create 'sim_1' fileset (if not found)
if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

# Set 'sim_1' fileset object
set obj [get_filesets sim_1]
set files [list \
               [file normalize $origin_dir/../../../vsrc/chip_top_tb.sv] \
               [file normalize $proj_dir/$project_name.srcs/sources_1/ip/mig_7series_0/mig_7series_0/example_design/sim/ddr3_model.v] \
              ]
add_files -norecurse -fileset $obj $files

# add include path
set_property include_dirs [list \
                               [file normalize $origin_dir/src] \
                               [file normalize $origin_dir/generated-src] \
                               [file normalize $proj_dir/$project_name.srcs/sources_1/ip/mig_7series_0/mig_7series_0/example_design/sim] \
                              ] [get_filesets sim_1]
set_property verilog_define [list \
                                 FPGA \
                                ] [get_filesets sim_1]

set_property "top" "tb" $obj

# force create the sim_1/behav path (need to make soft link in Makefile)
launch_simulation -scripts_only

# suppress some not very useful messages
# warning partial connection
set_msg_config -id "\[Synth 8-350\]" -suppress
# info do synthesis
set_msg_config -id "\[Synth 8-256\]" -suppress
set_msg_config -id "\[Synth 8-638\]" -suppress
# BRAM mapped to LUT due to optimization
set_msg_config -id "\[Synth 8-3969\]" -suppress
# BRAM with no output register
set_msg_config -id "\[Synth 8-4480\]" -suppress
# DSP without input pipelining
set_msg_config -id "\[Drc 23-20\]" -suppress
# Update IP version
set_msg_config -id "\[Netlist 29-345\]" -suppress


# do not flatten design
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]


