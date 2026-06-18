# AXI4 UVM Verification Intellectual Property (VIP)

This repository contains a functional, parameterized, and compliant AMBA AXI4 Verification Intellectual Property (VIP) implemented in SystemVerilog and the Universal Verification Methodology (UVM). It is designed to verify AXI4-compliant designs (Master, Slave, or Interconnect components) with high reliability, coverage collection, and protocol check assertions.

---

## Architecture Overview

The VIP consists of two main agents (Master and Slave) connected through a virtual interface to the Device Under Test (DUT).

The overall architecture is documented in the accompanying design diagram:
![AXI4 VIP Architecture](doc/axi4_vip.png)

### Key Components

- **axi4_if**: SystemVerilog interface defining all 5 AXI4 channels with clocking blocks (`master_cb`, `slave_cb`, `monitor_cb`) and modports (`master_mp`, `slave_mp`, `monitor_mp`) to avoid race conditions.
- **axi4_master_agent**: Active/Passive agent containing a sequencer, a clocking-block-compliant driver, and a monitor to observe write and read operations.
- **axi4_slave_agent**: Active/Passive agent simulating memory and handling responder rules. It is capable of generating responses (OKAY, EXOKAY, SLVERR, DECERR) and driving ready handshakes.
- **axi4_scoreboard**: Tracks transactions in progress, manages out-of-order responses, and maintains an internal reference memory model to verify read-after-write data integrity, including strobe routing verification.
- **axi4_coverage**: Functional coverage monitor capturing AXI4 transaction scenarios, address alignment, burst lengths, burst types, sizes, and channel back-pressures.
- **axi4_sva**: Comprehensive SystemVerilog Assertions module checking AXI4 protocol compliance directly on the interface.

---

## Directory Structure

```text
axi4_vip/
├── LICENSE
├── README.md
├── doc/
│   ├── axi4_vip.png
│   └── axi4_vip_vplan.xlsx
├── sim/
│   ├── Makefile
│   └── (simulation artifacts: logs, coverage, reports, etc.)
└── src/
    ├── axi4_if.sv
    ├── axi4_pkg.sv
    ├── axi4_test_pkg.sv
    ├── tb_top.sv
    ├── cfg/
    │   ├── axi4_agent_config.sv
    │   ├── axi4_transaction.sv
    │   └── axi4_types.sv
    ├── env/
    │   ├── axi4_coverage.sv
    │   ├── axi4_scoreboard.sv
    │   ├── axi4_vip_env.sv
    │   └── axi4_vip_env_config.sv
    ├── mst/
    │   ├── axi4_master_agent.sv
    │   ├── axi4_master_driver.sv
    │   ├── axi4_master_monitor.sv
    │   └── axi4_master_sequencer.sv
    ├── seq/
    │   └── (axi4 sequence library)
    ├── slv/
    │   ├── axi4_slave_agent.sv
    │   ├── axi4_slave_driver.sv
    │   ├── axi4_slave_monitor.sv
    │   └── axi4_slave_sequencer.sv
    ├── sva/
    │   └── axi4_sva.sv
    └── test/
        └── (axi4 test library)
```

---

## Features and Protocol Support

The AXI4 VIP supports standard AMBA AXI4 features:

- **Address & Data Width Configuration**: Independent parametrizable `ADDR_WIDTH`, `DATA_WIDTH`, and `ID_WIDTH` parameters.
- **Burst Types**: Support for FIXED, INCR, and WRAP transfers.
- **Burst Lengths**: Up to 256 beats per transaction for INCR burst type (complying with AXI4 specification).
- **Out-of-Order Execution**: Monitor and scoreboard track and match out-of-order read and write responses based on Transaction IDs.
- **Outstanding Transactions**: Test harness verifies multi-threaded outstanding reads and writes.
- **Read Data Interleaving Limitation**: Read data interleaving is not supported. Once a read data burst starts, all subsequent beats must share the same Transaction ID (RID) until the burst is completed with RLAST.
- **Exclusive Access**: Supports AXI4 locking mechanism (EXCLUSIVE/NORMAL) with address monitoring.
- **Strobe Routing**: Byte lane write enablement check via `WSTRB`.
- **SystemVerilog Assertions (SVA)**: Checks protocol stability, handshakes, payload stability, out-of-order data interleaving violations, and invalid/reserved configurations.

---

## Configuration and Enumerations

### VIP Parameters

The parameters are configured in the interface and package files:

- **ADDR_WIDTH**: Width of the address buses (default is 32).
- **DATA_WIDTH**: Width of the data buses (default is 32).
- **ID_WIDTH**: Width of the transaction ID buses (default is 4).

### Key Typedefs and Enums

The enums are declared inside `cfg/axi4_types.sv`:

- **axi4_burst_type_e**:
  - `AXI4_BURST_FIXED` (2'b00)
  - `AXI4_BURST_INCR` (2'b01)
  - `AXI4_BURST_WRAP` (2'b10)
- **axi4_resp_e**:
  - `AXI4_RESP_OKAY` (2'b00)
  - `AXI4_RESP_EXOKAY` (2'b01)
  - `AXI4_RESP_SLVERR` (2'b10)
  - `AXI4_RESP_DECERR` (2'b11)
- **axi4_size_e**:
  - Defines the number of bytes in each transfer beat (from `AXI4_SIZE_1B` to `AXI4_SIZE_128B`).
- **axi4_lock_e**:
  - `AXI4_LOCK_NORMAL` (1'b0)
  - `AXI4_LOCK_EXCLUSIVE` (1'b1)
- **axi4_wr_order_e**:
  - Controls the interleaving order of AW and W channels: `AXI4_WR_PARALLEL`, `AXI4_WR_AW_BEFORE_W`, and `AXI4_WR_W_BEFORE_AW`.

---

## Verification Environment and Test Suite

The test package `axi4_test_pkg` provides test scenarios extending `axi4_base_test`:

- **axi4_sanity_test**: Standard single-beat/multi-beat transaction verification.
- **axi4_random_test**: Generates randomized burst sizes, types, and lengths.
- **axi4_outstanding_test**: Tests multiple parallel transactions on different threads.
- **axi4_out_of_order_test**: Validates out-of-order write responses and read-data returns.
- **axi4_exclusive_test**: Verifies atomic read-modify-write transactions and EXOKAY feedback.
- **axi4_unaligned_test**: Validates address alignment offset calculations.
- **axi4_cache_prot_test**: Sweeps cache and protection configurations.
- **axi4_strobe_test**: Randomizes strobe patterns to ensure correct byte lane write routing.
- **axi4_burst_sweep_test**: Exercises variable transfer lengths and sizes.

---

## How to Run Simulations

The `sim/` directory includes a Makefile configured for Mentor Graphics/Siemens QuestaSim.

### Requirements

- Siemens QuestaSim / ModelSim
- SystemVerilog compiler and UVM library installation

### Command Reference

To run simulations, navigate to the `sim/` directory and execute the following commands:

#### Print Help Information
Shows all make targets and parameters.
```bash
make help
```

#### Run a Single Test (CLI Mode)
Runs the default test (`axi4_sanity_test`) with a random seed.
```bash
make run
```

To run a specific test and override variables:
```bash
make run TESTNAME=axi4_random_test SEED=42 UVM_VERBOSITY=UVM_HIGH USE_COVERAGE=1
```

#### Run a Test in GUI Mode
Launches the simulator in graphic user interface (GUI) mode with default waveform displays configured for AXI4 channels.
```bash
make gui TESTNAME=axi4_outstanding_test
```

#### Run Regression
Executes the regression suite in parallel. You can customize the iteration count per test using `NUM_RUNS`.
```bash
make -j8 regress NUM_RUNS=5
```

#### Generate Coverage Reports
Merges all generated coverage database files (`.ucdb`) and produces an HTML report.
```bash
make cov_report
```
Once generated, the report can be viewed in your browser at `sim/report/cov_html/index.html`.

#### Clean Build Artifacts
Removes all generated compilation libraries, temporary wave files, and coverage directories.
```bash
make clean
```

---

## AI Disclaimer

This repository and its codebase have been developed and/or refactored with the assistance of Artificial Intelligence (AI) tools. These tools were used to assist in scaffolding boilerplate code and optimizing testbench components. All code logic, test suites, and simulation configurations have been reviewed and validated to ensure compliance with the AMBA AXI4 protocol specification.