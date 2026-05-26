//==============================================================================
// File        : axi4_pkg.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Top-level SystemVerilog package for AXI4 VIP.
//               Imports UVM library and includes all core components:
//               transactions, sequencers, drivers, monitors, agents,
//               configs, coverage, scoreboard, and environment.
//
//               Note: axi4_if.sv (SystemVerilog interface) is NOT included
//               here — it must be compiled separately before this package.
//==============================================================================

package axi4_pkg;

    // =========================================================================
    // Imports & Macros
    // =========================================================================
    `include "uvm_macros.svh"
    import uvm_pkg::*;

    // =========================================================================
    // Core Types & Transaction Objects  (src/cfg/)
    // =========================================================================
    `include "cfg/axi4_types.sv"
    `include "cfg/axi4_agent_config.sv"
    `include "cfg/axi4_transaction.sv"

    // =========================================================================
    // Master-side Components  (src/master/)
    // =========================================================================
    `include "master/axi4_master_sequencer.sv"
    `include "master/axi4_master_driver.sv"
    `include "master/axi4_master_monitor.sv"
    `include "master/axi4_master_agent.sv"

    // =========================================================================
    // Slave-side Components  (src/slave/)
    // =========================================================================
    `include "slave/axi4_slave_sequencer.sv"
    `include "slave/axi4_slave_driver.sv"
    `include "slave/axi4_slave_monitor.sv"
    `include "slave/axi4_slave_agent.sv"

    // =========================================================================
    // Environment-level Components  (src/env/)
    // =========================================================================
    `include "env/axi4_coverage.sv"
    `include "env/axi4_scoreboard.sv"
    `include "env/axi4_vip_env_config.sv"
    `include "env/axi4_vip_env.sv"

endpackage : axi4_pkg