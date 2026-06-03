//==============================================================================
// File        : tb_top.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Top-level testbench module for AXI4 VIP.
//               Generates clock and reset, instantiates the interface,
//               propagates the virtual interface to UVM config_db,
//               and starts the UVM phase execution via run_test().
//==============================================================================

`timescale 1ns/1ps

module tb_top;

    // =========================================================================
    // Imports & Macros
    // =========================================================================
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Import VIP and Test packages
    import axi4_pkg::*;
    import axi4_test_pkg::*;

    // =========================================================================
    // Parameters (Match standard values used across agents & tests)
    // =========================================================================
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 4;

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    bit clk;
    bit rst_n;

    // 100 MHz Clock (10ns period)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset assertion (Active low, held for 10 clock cycles)
    initial begin
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        `uvm_info("TOP_TB", "Reset de-asserted", UVM_MEDIUM)
    end

    // =========================================================================
    // Interface Instance
    // =========================================================================
    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) intf (
        .clk(clk),
        .rst_n(rst_n)
    );

    // =========================================================================
    // SVA — AXI4 protocol assertion checker
    //   Direct instantiation (QuestaSim 10.6b does not support bind-to-interface).
    //   All signals are connected via the interface instance `intf`.
    // =========================================================================
    axi4_sva #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_axi4_sva (
        .clk      (clk),
        .rst_n    (rst_n),
        // AW Channel
        .AWID     (intf.AWID),
        .AWADDR   (intf.AWADDR),
        .AWLEN    (intf.AWLEN),
        .AWSIZE   (intf.AWSIZE),
        .AWBURST  (intf.AWBURST),
        .AWLOCK   (intf.AWLOCK),
        .AWCACHE  (intf.AWCACHE),
        .AWPROT   (intf.AWPROT),
        .AWQOS    (intf.AWQOS),
        .AWREGION (intf.AWREGION),
        .AWVALID  (intf.AWVALID),
        .AWREADY  (intf.AWREADY),
        // W Channel
        .WDATA    (intf.WDATA),
        .WSTRB    (intf.WSTRB),
        .WLAST    (intf.WLAST),
        .WVALID   (intf.WVALID),
        .WREADY   (intf.WREADY),
        // B Channel
        .BID      (intf.BID),
        .BRESP    (intf.BRESP),
        .BVALID   (intf.BVALID),
        .BREADY   (intf.BREADY),
        // AR Channel
        .ARID     (intf.ARID),
        .ARADDR   (intf.ARADDR),
        .ARLEN    (intf.ARLEN),
        .ARSIZE   (intf.ARSIZE),
        .ARBURST  (intf.ARBURST),
        .ARLOCK   (intf.ARLOCK),
        .ARCACHE  (intf.ARCACHE),
        .ARPROT   (intf.ARPROT),
        .ARQOS    (intf.ARQOS),
        .ARREGION (intf.ARREGION),
        .ARVALID  (intf.ARVALID),
        .ARREADY  (intf.ARREADY),
        // R Channel
        .RID      (intf.RID),
        .RDATA    (intf.RDATA),
        .RRESP    (intf.RRESP),
        .RLAST    (intf.RLAST),
        .RVALID   (intf.RVALID),
        .RREADY   (intf.RREADY)
    );

    // =========================================================================
    // UVM Setup & Execution
    // =========================================================================
    initial begin
        uvm_config_db#(virtual axi4_if)::set(null, "*", "vif", intf);

        `uvm_info("TB_TOP", "Virtual interface set in config_db", UVM_LOW)

        // Kick off UVM phases. The active test is specified via +UVM_TESTNAME plusarg.
        run_test();
    end

    // =========================================================================
    // Simulation Control & Waveform Dumping
    // =========================================================================
    initial begin
        // Enable waveform dumping if requested by +DUMP_VCD plusarg
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("axi4_vip.vcd");
            $dumpvars(0, tb_top);
            `uvm_info("TB_TOP", "Waveform VCD dumping enabled (axi4_vip.vcd)", UVM_LOW)
        end
    end

/*
    // Safety simulation timeout watchdog (10 milliseconds backup)
    initial begin
        #10ms;
        `uvm_error("TB_TOP", "Simulation safety timeout reached! Hanging prevention triggered.")
        $finish;
    end
*/

endmodule : tb_top