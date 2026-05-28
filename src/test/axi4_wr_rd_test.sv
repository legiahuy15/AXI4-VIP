//==============================================================================
// File        : axi4_wr_rd_test.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : Write-then-read-back test.
//               Sends multiple write bursts to different addresses, then
//               reads back from each address to verify data integrity
//               through the slave memory model and scoreboard.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

`ifndef AXI4_WR_RD_TEST_INCLUDED_
`define AXI4_WR_RD_TEST_INCLUDED_

class axi4_wr_rd_test extends axi4_base_test;

    `uvm_component_utils(axi4_wr_rd_test)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Run phase — execute write-read-back sequences
    // =========================================================================
    task run_phase(uvm_phase phase);
        axi4_write_read_back_seq wr_rd_seq;
        int unsigned num_iterations = 10;

        phase.raise_objection(this, "axi4_wr_rd_test: starting");

        `uvm_info(get_type_name(),
                  $sformatf("Starting %0d write-read-back iterations", num_iterations),
                  UVM_LOW)

        for (int i = 0; i < num_iterations; i++) begin
            wr_rd_seq = axi4_write_read_back_seq::type_id::create(
                            $sformatf("wr_rd_seq_%0d", i));

            // Randomise sequence-level fields (addr, len, size, burst)
            if (!wr_rd_seq.randomize())
                `uvm_fatal(get_type_name(),
                           $sformatf("Sequence randomization failed at iteration %0d", i))

            `uvm_info(get_type_name(),
                      $sformatf("[%0d/%0d] ADDR=0x%08h LEN=%0d BURST=%s",
                                i + 1, num_iterations,
                                wr_rd_seq.addr, wr_rd_seq.len,
                                wr_rd_seq.burst.name()), UVM_MEDIUM)

            wr_rd_seq.start(env.master_agent.sqr);
        end

        // Drain — wait for slave to finish outstanding responses
        repeat (50) @(posedge env_cfg.master_vif.clk);

        `uvm_info(get_type_name(),
                  $sformatf("%0d write-read-back iterations complete", num_iterations),
                  UVM_LOW)

        phase.drop_objection(this, "axi4_wr_rd_test: complete");
    endtask : run_phase

endclass : axi4_wr_rd_test
