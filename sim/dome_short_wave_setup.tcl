# Rebuild the short defense-demo wave view for every Behavioral Simulation launch.
# No saved .wcfg is loaded: Vivado creates an Untitled wave configuration,
# then this script populates the six presentation groups dynamically.

if {[llength [current_wave_config -quiet]] == 0} {
    create_wave_config
}

set existing [get_waves -quiet *]
if {[llength $existing]} {
    remove_wave $existing
}

proc add_demo_wave_group {label object_paths} {
    set group [add_wave_group $label]
    foreach path $object_paths {
        set objects [get_objects -quiet $path]
        if {[llength $objects]} {
            add_wave -into $group $objects
        }
    }
}

add_demo_wave_group top_debug {
    /dome_short_tb/clk
    /dome_short_tb/rst_n
    /dome_short_tb/dbg_pc
    /dome_short_tb/dbg_wb_we
    /dome_short_tb/dbg_wb_rd
    /dome_short_tb/dbg_wb_data
}

add_demo_wave_group pipeline_internal {
    /dome_short_tb/dut/if_pc
    /dome_short_tb/dut/if_inst
    /dome_short_tb/dut/id_pc
    /dome_short_tb/dut/id_inst
    /dome_short_tb/dut/x_pc
    /dome_short_tb/dut/x_alu_op
    /dome_short_tb/dut/alu_a
    /dome_short_tb/dut/alu_b
    /dome_short_tb/dut/alu_y
    /dome_short_tb/dut/ex_result
    /dome_short_tb/dut/branch_taken
    /dome_short_tb/dut/branch_target
    /dome_short_tb/dut/ex_busy
    /dome_short_tb/dut/div_busy
    /dome_short_tb/dut/div_done
    /dome_short_tb/dut/stall_pc
    /dome_short_tb/dut/stall_if_id
    /dome_short_tb/dut/flush_if_id
    /dome_short_tb/dut/flush_id_ex
    /dome_short_tb/dut/m_alu_result
    /dome_short_tb/dut/m_store_data
    /dome_short_tb/dut/m_load_data
    /dome_short_tb/dut/wb_reg_write
    /dome_short_tb/dut/wb_rd
    /dome_short_tb/dut/wb_data
}

add_demo_wave_group register_file {
    /dome_short_tb/dut/u_rf/regs
}

add_demo_wave_group data_memory {
    /dome_short_tb/dut/u_dmem/mem
}

add_demo_wave_group instruction_memory_cache {
    /dome_short_tb/dut/u_imem/addr
    /dome_short_tb/dut/u_imem/inst
    /dome_short_tb/dut/u_imem/stall
    /dome_short_tb/dut/u_imem/mem
    /dome_short_tb/dut/u_imem/cache_data
    /dome_short_tb/dut/u_imem/cache_tag
    /dome_short_tb/dut/u_imem/cache_valid
    /dome_short_tb/dut/u_imem/busy
    /dome_short_tb/dut/u_imem/miss_count
    /dome_short_tb/dut/u_imem/miss_word_index
    /dome_short_tb/dut/u_imem/miss_index
    /dome_short_tb/dut/u_imem/miss_tag
    /dome_short_tb/dut/u_imem/word_index
    /dome_short_tb/dut/u_imem/index
    /dome_short_tb/dut/u_imem/tag
    /dome_short_tb/dut/u_imem/hit
    /dome_short_tb/dut/u_imem/miss
}

add_demo_wave_group data_memory_cache {
    /dome_short_tb/dut/u_dmem/addr
    /dome_short_tb/dut/u_dmem/we
    /dome_short_tb/dut/u_dmem/re
    /dome_short_tb/dut/u_dmem/width
    /dome_short_tb/dut/u_dmem/load_unsigned
    /dome_short_tb/dut/u_dmem/wdata
    /dome_short_tb/dut/u_dmem/rdata
    /dome_short_tb/dut/u_dmem/stall
    /dome_short_tb/dut/u_dmem/cache_data
    /dome_short_tb/dut/u_dmem/cache_tag
    /dome_short_tb/dut/u_dmem/cache_valid
    /dome_short_tb/dut/u_dmem/access
    /dome_short_tb/dut/u_dmem/word_addr
    /dome_short_tb/dut/u_dmem/index
    /dome_short_tb/dut/u_dmem/tag
    /dome_short_tb/dut/u_dmem/byte_off
    /dome_short_tb/dut/u_dmem/busy
    /dome_short_tb/dut/u_dmem/miss_count
    /dome_short_tb/dut/u_dmem/miss_addr
    /dome_short_tb/dut/u_dmem/miss_index
    /dome_short_tb/dut/u_dmem/miss_tag
    /dome_short_tb/dut/u_dmem/miss_we
    /dome_short_tb/dut/u_dmem/miss_width
    /dome_short_tb/dut/u_dmem/miss_wdata
    /dome_short_tb/dut/u_dmem/hit
    /dome_short_tb/dut/u_dmem/miss
    /dome_short_tb/dut/u_dmem/fill_word
    /dome_short_tb/dut/u_dmem/store_word
}

# Record every signal into the WDB, while keeping the visible wave view readable.
log_wave -recursive /dome_short_tb
set_property needs_save false [current_wave_config]
run 7000ns

