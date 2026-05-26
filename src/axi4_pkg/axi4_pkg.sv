//==============================================================================
// File        : axi4_pkg.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Top-level SystemVerilog package for AXI4 VIP.
//               Imports UVM library and includes all core components:
//               transactions, sequencers, drivers, monitors, agents, and configs.
//==============================================================================

package axi4_pkg;

    // =========================================================================
    // Imports & Macros
    // =========================================================================
    `include "uvm_macros.svh"
    import uvm_pkg::*;

    // =========================================================================
    // Core Types & Transaction Objects
    // =========================================================================
    `include "axi4_types.sv"
    `include "axi4_agent_config.sv"
    `include "axi4_transaction.sv"

    // =========================================================================
    // Master-side Components
    // =========================================================================
    `include "axi4_master_sequencer.sv"
    `include "axi4_master_driver.sv"
    `include "axi4_master_monitor.sv"
    `include "axi4_master_agent.sv"

    // =========================================================================
    // Slave-side Components
    // =========================================================================
    `include "axi4_slave_sequencer.sv"
    `include "axi4_slave_driver.sv"
    `include "axi4_slave_monitor.sv"
    `include "axi4_slave_agent.sv"

    // =========================================================================
    // Environment-level Components
    // =========================================================================
    `include "axi4_coverage.sv"
    `include "axi4_scoreboard.sv"

endpackage : axi4_pkg