#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Compiling RISC-V OoO Design ==="

# Added -j 0 flag to let Verilator use all available CPU cores for compiling C++ files
verilator --binary -j 0 \
  -Wall \
  -Wno-UNUSEDSIGNAL \
  -Wno-UNUSEDPARAM \
  -Wno-PINCONNECTEMPTY \
  -Wno-WIDTHEXPAND \
  -Wno-UNOPTFLAT \
  -Wno-BLKSEQ \
  --top-module tb_top \
  --timing \
  +incdir+rtl/core \
  rtl/core/riscv_pkg.sv \
  rtl/bpu/tage_base.sv \
  rtl/bpu/tage_folded_reg.sv \
  rtl/bpu/tage_tagged_table.sv \
  rtl/core/fetch/fetch_stage.sv \
  rtl/core/decode/decode_stage.sv \
  rtl/core/rename/rename_stage.sv \
  rtl/core/dispatch/rob.sv \
  rtl/core/issue/issue_queue.sv \
  rtl/core/execute/physical_register_file.sv \
  rtl/core/execute/alu_unit.sv \
  rtl/core/execute/load_store_queue.sv \
  rtl/memory/l1_dcache.sv \
  rtl/memory/l2_coherent_cache.sv \
  rtl/core/pipeline_top.sv \
  tb/tb_top.sv

echo "=== Compilation and Build Process Complete ==="
echo "=== Running Generated Out-of-Order Core Executable ==="
./obj_dir/Vtb_top
