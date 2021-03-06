# See LICENSE for license details.

ifndef XILINX_VIVADO
$(error Please set environment variable XILINX_VIVADO for Xilinx tools)
endif

#--------------------------------------------------------------------
# global define
#--------------------------------------------------------------------

default: project

top_dir = $(abspath ../../..)
base_dir = $(abspath ../../../rocket-chip)
proj_dir = $(abspath .)
mem_gen = $(abspath ../../..)/fpga/common/fpga_mem_gen
generated_dir = $(base_dir)/vsim/generated-src

glip_dir = $(abspath ../../..)/opensocdebug/glip/src
osd_dir = $(abspath ../../..)/opensocdebug/hardware
example_dir = $(abspath ../../..)/fpga/bare_metal/examples

project_name = lowrisc-chip-imp
BACKEND ?= v
CONFIG=DefaultConfig

VIVADO = vivado

# See LICENSE for license details.

# check RISCV environment variable
ifndef RISCV
$(error Please set environment variable RISCV. Please take a look at README)
endif

MODEL := TestHarness
PROJECT := freechips.rocketchip.system
CXX := g++
CXXFLAGS := -O1
JVM_MEMORY ?= 2G

SBT ?= java -Xmx$(JVM_MEMORY) -Xss8M -XX:MaxPermSize=256M -jar $(base_dir)/sbt-launch.jar
SHELL := /bin/bash

FIRRTL_JAR ?= $(base_dir)/firrtl/utils/bin/firrtl.jar
FIRRTL ?= java -Xmx$(JVM_MEMORY) -Xss8M -XX:MaxPermSize=256M -cp $(FIRRTL_JAR) firrtl.Driver

# specify source files
src_path := src/main/scala
default_submodules := . hardfloat chisel3

# translate trace files generated by C++/Verilog simulation
disasm := >
which_disasm := $(shell which spike-dasm 2> /dev/null)
ifneq ($(which_disasm),)
	disasm := | $(which_disasm) $(DISASM_EXTENSION) >
endif

# define time-out for different types of simulation
timeout_cycles       = 10000000
long_timeout_cycles  = 50000000
linux_timeout_cycles = 5000000000

# emacs local variable

# Local Variables:
# mode: makefile
# End:

.PHONY: default

#--------------------------------------------------------------------
# Sources
#--------------------------------------------------------------------

boot_mem = src/boot.mem
bootrom_img = $(base_dir)/bootrom/bootrom.img
fpga_srams = $(generated_dir)/$(PROJECT).$(CONFIG).fpga_srams.v
fpga_src = $(generated_dir)/$(PROJECT).$(CONFIG).v

lowrisc_srcs = \
	$(fpga_src) \
	$(fpga_srams)

lowrisc_headers = \
	$(abspath ../../..)/src/main/verilog/consts.vh \

verilog_srcs = \
	$(top_dir)/src/main/verilog/chip_top.sv \
	$(top_dir)/src/main/verilog/spi_wrapper.sv \
	$(top_dir)/vsrc/AsyncResetReg.v \
	$(top_dir)/vsrc/plusarg_reader.v \

verilog_headers = \
	$(top_dir)/src/main/verilog/config.vh \

test_verilog_srcs = \
	$(top_dir)/src/test/verilog/host_behav.sv \
	$(top_dir)/src/test/verilog/nasti_ram_behav.sv \
	$(top_dir)/src/test/verilog/chip_top_tb.sv \

test_cxx_srcs = \
	$(top_dir)/src/test/cxx/common/globals.cpp \
	$(top_dir)/src/test/cxx/common/loadelf.cpp \
	$(top_dir)/src/test/cxx/common/dpi_ram_behav.cpp \
	$(top_dir)/src/test/cxx/common/dpi_host_behav.cpp \

test_cxx_headers = \
	$(top_dir)/src/test/cxx/common/globals.h \
	$(top_dir)/src/test/cxx/common/loadelf.hpp \
	$(top_dir)/src/test/cxx/common/dpi_ram_behav.h \
	$(top_dir)/src/test/cxx/common/dpi_host_behav.h \

#--------------------------------------------------------------------
# Build Verilog
#--------------------------------------------------------------------

verilog: $(lowrisc_headers)
	make -C ../../../rocket-chip/vsim verilog

$(fpga_srams): $(generated_dir)/$(PROJECT).$(CONFIG).conf $(mem_gen)
	$(mem_gen) $< > $@.tmp
	mv -f $@.tmp $@

$(fpga_src):

.SECONDARY: $(firrtl) $(verilog)

# emacs local variable

# Local Variables:
# mode: makefile
# End:

.PHONY: verilog
junk += $(generated_dir)

#--------------------------------------------------------------------
# Project generation
#--------------------------------------------------------------------

project = $(project_name)/$(project_name).xpr
project: $(project)
$(project): | $(lowrisc_srcs) $(lowrisc_headers)
	$(VIVADO) -mode batch -source script/make_project.tcl -tclargs $(project_name) $(CONFIG)
	ln -s $(proj_dir)/$(boot_mem) $(project_name)/$(project_name).runs/synth_1/boot.mem
	ln -s $(proj_dir)/$(boot_mem) $(project_name)/$(project_name).sim/sim_1/behav/boot.mem

vivado: $(project)
	$(VIVADO) $(project) &

bitstream = $(project_name)/$(project_name).runs/impl_1/chip_top.bit
bitstream: $(bitstream)
$(bitstream): $(lowrisc_srcs)  $(lowrisc_headers) $(verilog_srcs) $(verilog_headers) | $(project)
	$(VIVADO) -mode batch -source ../../common/script/make_bitstream.tcl -tclargs $(project_name)

program: $(bitstream)
	$(VIVADO) -mode batch -source ../../common/script/program.tcl -tclargs "xc7a100t_0" $(bitstream)

.PHONY: project vivado bitstream program

#--------------------------------------------------------------------
# DPI compilation
#--------------------------------------------------------------------
dpi_lib = $(project_name)/$(project_name).sim/sim_1/behav/xsim.dir/xsc/dpi.so
dpi: $(dpi_lib)
$(dpi_lib): $(test_verilog_srcs) $(test_cxx_srcs) $(test_cxx_headers)
	-mkdir -p $(project_name)/$(project_name).sim/sim_1/behav/xsim.dir/xsc
	cd $(project_name)/$(project_name).sim/sim_1/behav; \
	g++ -Wa,-W -fPIC -m64 -O1 -std=c++11 -shared -I$(XILINX_VIVADO)/data/xsim/include -I$(top_dir)/csrc/common \
	-DVERBOSE_MEMORY \
	$(test_cxx_srcs) $(XILINX_VIVADO)/lib/lnx64.o/librdi_simulator_kernel.so -o $(proj_dir)/$@

.PHONY: dpi

#--------------------------------------------------------------------
# FPGA simulation
#--------------------------------------------------------------------

sim-comp = $(project_name)/$(project_name).sim/sim_1/behav/compile.log
sim-comp: $(sim-comp)
$(sim-comp): $(lowrisc_srcs) $(lowrisc_headers) $(verilog_srcs) $(verilog_headers) $(test_verilog_srcs) $(test_cxx_srcs) $(test_cxx_headers) | $(project)
	cd $(project_name)/$(project_name).sim/sim_1/behav; source compile.sh > /dev/null
	@echo "If error, see $(project_name)/$(project_name).sim/sim_1/behav/compile.log for more details."

sim-elab = $(project_name)/$(project_name).sim/sim_1/behav/elaborate.log
sim-elab: $(sim-elab)
$(sim-elab): $(sim-comp) $(dpi_lib)
	cd $(project_name)/$(project_name).sim/sim_1/behav; source elaborate.sh > /dev/null
	@echo "If error, see $(project_name)/$(project_name).sim/sim_1/behav/elaborate.log for more details."

simulation: $(sim-elab)
	cd $(project_name)/$(project_name).sim/sim_1/behav; xsim tb_behav -key {Behavioral:sim_1:Functional:tb} -tclbatch $(proj_dir)/script/simulate.tcl -log $(proj_dir)/simulate.log

.PHONY: sim-comp sim-elab simulation

#--------------------------------------------------------------------
# Debug helper
#--------------------------------------------------------------------

search-ramb: src/boot.bmm
src/boot.bmm: $(bitstream)
	$(VIVADO) -mode batch -source ../../common/script/search_ramb.tcl -tclargs $(project_name) > search-ramb.log
	python ../../common/script/bmm_gen.py search-ramb.log src/boot.bmm 128 65536

bit-update: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
$(project_name)/$(project_name).runs/impl_1/chip_top.new.bit: $(boot_mem) src/boot.bmm
	data2mem -bm $(boot_mem) -bd $< -bt $(bitstream) -o b $@

program-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
	$(VIVADO) -mode batch -source ../../common/script/program.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit

cfgmem: $(project_name)/$(project_name).runs/impl_1/chip_top.bit
	$(VIVADO) -mode batch -source ../../common/script/cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.bit

cfgmem-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit
	$(VIVADO) -mode batch -source ../../common/script/cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit

program-cfgmem: $(project_name)/$(project_name).runs/impl_1/chip_top.bit.mcs
	$(VIVADO) -mode batch -source ../../common/script/program_cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.bit.mcs

program-cfgmem-updated: $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit.mcs
	$(VIVADO) -mode batch -source ../../common/script/program_cfgmem.tcl -tclargs "xc7a100t_0" $(project_name)/$(project_name).runs/impl_1/chip_top.new.bit.mcs

etherboot: boot0001.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth1 boot0001.bin

ethertest: test0001.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth1 test0001.bin

ethersd: boot0000.bin ../../common/script/recvRawEth
	../../common/script/recvRawEth -r eth1 boot0000.bin

etherlocal: ../../../rocket-chip/riscv-tools/riscv-pk/build/bbl ../../common/script/recvRawEth
	cp $< boot.bin
	riscv64-unknown-elf-strip boot.bin
	../../common/script/recvRawEth -r -s 192.168.0.100 boot.bin

etherremote: ../../../rocket-chip/riscv-tools/riscv-pk/build/bbl ../../common/script/recvRawEth
	cp $< boot.bin
	riscv64-unknown-elf-strip boot.bin
	../../common/script/recvRawEth -r -s lowrisc5.sm.cl.cam.ac.uk boot.bin

../../common/script/recvRawEth: ../../common/script/recvRawEth.c
	make -C ../../common/script

test0001.bin: $(TOP)/riscv-tools/make_test.sh
	$(TOP)/riscv-tools/make_test.sh 0001

boot0001.bin: $(TOP)/riscv-tools/make_root.sh $(TOP)/riscv-tools/initial_0001 $(TOP)/riscv-tools/linux-4.6.2/.config $(TOP)/riscv-tools/busybox-1.21.1/.config
	$(TOP)/riscv-tools/make_root.sh 0001

boot0000.bin: $(TOP)/riscv-tools/make_root.sh $(TOP)/riscv-tools/initial_0000 $(TOP)/riscv-tools/linux-4.6.2/.config $(TOP)/riscv-tools/busybox-1.21.1/.config
	$(TOP)/riscv-tools/make_root.sh 0000

$(TOP)/riscv-tools/linux-4.6.2:
	$(TOP)/riscv-tools/fetch_and_patch_linux.sh

$(TOP)/riscv-tools/busybox-1.21.1:
	$(TOP)/riscv-tools/fetch_and_patch_busybox.sh

$(TOP)/riscv-tools/linux-4.6.2/.config: $(TOP)/riscv-tools/linux-4.6.2/arch/riscv/configs/riscv64_lowrisc
	make -C $(TOP)/riscv-tools/linux-4.6.2 ARCH=riscv defconfig CONFIG_RV_LOWRISC=y

$(TOP)/riscv-tools/busybox-1.21.1/.config:
	$(TOP)/riscv-tools/fetch_and_patch_busybox.sh

.PHONY: search-ramb bit-update program-updated

#--------------------------------------------------------------------
# Load examples
#--------------------------------------------------------------------

EXAMPLES = hello trace boot dram sdcard jump flash selftest tag eth

examples/Makefile:
	-mkdir examples
	ln -s $(example_dir)/Makefile examples/Makefile

$(EXAMPLES):  $(lowrisc_headers) | examples/Makefile
	FPGA_DIR=$(proj_dir) BASE_DIR=$(example_dir) $(MAKE) -C examples $@.hex
	cp examples/$@.hex $(boot_mem) && $(MAKE) bit-update

.PHONY: $(EXAMPLES)

tests:  $(lowrisc_headers) | examples/Makefile
	FPGA_DIR=$(proj_dir) BASE_DIR=$(example_dir) $(MAKE) -C examples eth.hex
	riscv64-unknown-elf-size examples/eth.riscv
	riscv64-unknown-elf-objdump -d examples/eth.riscv > examples/eth.dis

empty:
	mkdir -p examples
	echo '	wfi' > examples/empty.s1
	cat examples/empty.s1 examples/empty.s1 examples/empty.s1 examples/empty.s1 > examples/empty.s2
	cat examples/empty.s2 examples/empty.s2 examples/empty.s2 examples/empty.s2 > examples/empty.s3
	cat examples/empty.s3 examples/empty.s3 examples/empty.s3 examples/empty.s3 > examples/empty.s4
	cat examples/empty.s4 examples/empty.s4 examples/empty.s4 examples/empty.s4 > examples/empty.s5
	cat examples/empty.s5 examples/empty.s5 examples/empty.s5 examples/empty.s5 > examples/empty.s6
	cat examples/empty.s6 examples/empty.s6 examples/empty.s6 examples/empty.s6 > examples/empty.s7
	cat examples/empty.s7 examples/empty.s7 examples/empty.s7 examples/empty.s7 | riscv64-unknown-elf-as - -o examples/empty.o
	riscv64-unknown-elf-ld -Ttext=0x40000000 examples/empty.o -o examples/empty.riscv
	riscv64-unknown-elf-objcopy -I elf64-little -O verilog examples/empty.riscv examples/cnvmem.mem
	iverilog script/cnvmem.v -o examples/cnvmem
	(cd examples; ./cnvmem)
	mv examples/cnvmem.hex examples/$@.hex
	cp examples/$@.hex $(boot_mem) && $(MAKE) bit-update

vm:
	make -C /local/scratch/jrrk2/riscv-test-env/v
	cp /local/scratch/jrrk2/riscv-test-env/v/cnvmem.hex examples/$@.hex
	cp examples/$@.hex $(boot_mem) && $(MAKE) bit-update

mmc:
	(make -C $(example_dir) mmc)
	riscv64-unknown-elf-objcopy -I elf64-little -O verilog $(example_dir)/mmc examples/cnvmem.mem
	iverilog script/cnvmem.v -o examples/cnvmem
	(cd examples; ./cnvmem)
	mv examples/cnvmem.hex examples/$@.hex
	cp examples/$@.hex $(boot_mem) && $(MAKE) bit-update

#--------------------------------------------------------------------
# Clean up
#--------------------------------------------------------------------

clean:
	$(info To clean everything, including the Vivado project, use 'make cleanall')
	-rm -rf *.log *.jou $(junk)
	-$(MAKE) -C examples clean

cleanall: clean
	-rm -fr $(project)
	-rm -fr $(project_name)
	-rm -fr examples

.PHONY: clean cleanall
