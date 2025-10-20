OBJ_DIR=obj_dir
VERILATOR_DIR=/usr/share/verilator/include
HDL_FILES = cpu_cache_sdram_tb.v mt48lc16m16a2.v ../../rtl/sdram/cpu_dcache.v ../../rtl/sdram/cpu_icache.v ../../rtl/sdram/cpu_icache_ref.v ../../rtl/sdram/cpu_cache_new.v \
	../../rtl/soc/branch_target_buffer.v ../../rtl/sdram/sdram_ctrl.v ../../rtl/sdram/sdram_ctrl_splitcache.v \
	../../rtl/sdram/dpram_inf_256x32.v ../../rtl/sdram/dpram_inf_unreg_256x32.v ../../rtl/sdram/dpram_inf_be_1024x32.v ../../rtl/sdram/dpram_inf_generic.v

all: cpu_cache_sdram_tb

clean:
	-rm cpu_cache_sdram_tb
	-rm $(OBJ_DIR)/*

Vcpu_cache_sdram_tb.cpp: ${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp


${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp: ${HDL_FILES}
	verilator -cc -exe -MMD --trace --top-module cpu_cache_sdram_tb -cc cpu_cache_sdram_tb.cpp ${HDL_FILES}

cpu_cache_sdram_tb: ${OBJ_DIR}/Vcpu_cache_sdram_tb.cpp cpu_cache_sdram_tb.cpp
	$(MAKE) -j 4 -C obj_dir -f ../Makefile_obj
#	g++ -I $(OBJ_DIR) -I$(VERILATOR_DIR) $(VERILATOR_DIR)/verilated.cpp $(VERILATOR_DIR)/verilated_vcd_c.cpp cpu_cache_sdram_tb.cpp  $(OBJ_DIR)/Vcpu_cache_sdram_tb__Trace.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb__Trace__Slow.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb.cpp $(OBJ_DIR)/Vcpu_cache_sdram_tb__Syms.cpp -DOPT=-DVL_DEBUG -o cpu_cache_sdram_tb

