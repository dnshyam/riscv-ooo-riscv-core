# Speculative Out-of-Order RISC-V Processor Core
An advanced, speculative Out-of-Order (OoO) RISC-V processor core featuring a geometric TAGE Branch Predictor and an L2 Cache Coherency subsystem. Built with SystemVerilog and verified using Verilator.

## 🚀 Key Features & Microarchitecture

### 1. Speculative Out-of-Order Execution Engine
* **Dynamic Register Renaming:** Uses a hardware Map Table and an unallocated Free List manager to seamlessly translate architectural registers to physical tags (`PR0`-`PR63`), eradicating Write-After-Read (WAR) and Write-After-Write (WAW) false structural dependencies.
* **Oldest-First Reservation Station:** Features an Issue Queue (Reservation Station) with an active wakeup tag monitoring matrix and a select arbitration loop to execute ready instructions out-of-order.
* **Precise Commit Management:** Implements a circular 64-entry Reorder Buffer (ROB) tracking architectural state retirement to handle exceptions and speculative misprediction flushes cleanly.

### 2. Multi-Table TAGE Branch Predictor
* **Geometric History Lengths:** Implements an advanced TAGE prediction infrastructure mapping a bimodal base table alongside multiple tagged geometric component tables.
* **Folded History Compression:** Employs hardware folded registers to compress long-range Global History Registers (GHR) into compact, highly-correlated index hashes on the fly.

### 3. Coherent Memory Hierarchy & LSQ
* **Dynamic Load/Store Queue (LSQ):** Implements an 8-entry speculative LSQ supporting address resolution, load stalling, and low-latency Store-to-Load Data Forwarding.
* **L1 Data Cache Layer:** Direct-mapped write-through L1 cache block maximizing memory performance pipeline stages.
* **Snooping L2 Cache Coherency:** Features a dedicated L2 Coherent Controller driven by an invalidation state machine to continuously resolve cross-domain data consistency.

---

## 📂 Repository Structure
```text
riscv_ooo_core/
├── rtl/                    # Synthesizable SystemVerilog Hardware Sources
│   ├── core/
│   │   ├── fetch/          # Instruction fetch pipelines
│   │   ├── decode/         # RV32I opcode decoder matrices
│   │   ├── rename/         # Register Map Table & Free List allocations
│   │   ├── dispatch/       # Reorder Buffer (ROB) order handling
│   │   ├── issue/          # Issue Queue reservation station wakeup tags
│   │   └── execute/        # ALU matrices and Load/Store Queues
│   ├── bpu/                # TAGE branch prediction modules & folded registers
│   └── memory/             # L1 cache blocks and Coherent L2 controllers
├── tb/                     # End-to-End simulation testbench verification suite
└── scripts/                # Automated multi-core Verilator execution drivers
```

---

## 🛠️ Verification & Simulation Quickstart

### Prerequisites
Ensure you have the latest version of Verilator and a C++ compiler (`g++`) installed on your system.
```bash
# Ubuntu/Linux
sudo apt-get install verilator build-essential
```

### Running the End-to-End Simulation Pipeline
The automated shell script leverages multi-core compilation configurations to transpile the SystemVerilog hierarchy into optimized C++ models, run architectural loop instructions, and track runtime performance.

```bash
# Make driver executable and launch execution verification
chmod +x scripts/run_compile.sh
./scripts/run_compile.sh
```

### Sample Simulation Retirement Traces
Upon successful execution paths, the Reorder Buffer cleanly tracks speculative state commitments and outputs retirement validation data:
```text
=== Launching RISC-V Out-of-Order Core Verification Testbench ===
[COMMIT EVENT] Time: 135000 | PC: 0x00000000 | Freeing physical tag: PR1
[COMMIT EVENT] Time: 145000 | PC: 0x00000004 | Freeing physical tag: PR2
[COMMIT EVENT] Time: 165000 | PC: 0x00000008 | Freeing physical tag: PR3
=== Speculative Out-of-Order Verification Cycle Sequence Complete! ===
```
