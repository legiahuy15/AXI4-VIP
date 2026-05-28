//==============================================================================
// File        : axi4_test_pkg.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Test package for AXI4 VIP.
//               Imports axi4_pkg (VIP core) and includes all test classes.
//               Separated from axi4_pkg to keep VIP reusable across projects.
//
//               Compile order:
//                 1. axi4_if.sv      (interface)
//                 2. axi4_pkg.sv     (VIP core)
//                 3. axi4_test_pkg.sv (this file)
//                 4. tb_top.sv       (testbench top)
//==============================================================================

`ifndef AXI4_TEST_PKG_INCLUDED_
`define AXI4_TEST_PKG_INCLUDED_

package axi4_test_pkg;

    `include "uvm_macros.svh"
    import uvm_pkg::*;
    import axi4_pkg::*;

    // =========================================================================
    // Tests  (src/test/)
    // =========================================================================
    `include "test/axi4_base_test.sv"
    `include "test/axi4_wr_rd_test.sv"

endpackage : axi4_test_pkg

`endif // AXI4_TEST_PKG_INCLUDED_