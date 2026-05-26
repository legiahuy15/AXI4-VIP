//==============================================================================
// File        : axi4_master_driver.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 master driver.
//               Receives transactions from the sequencer and drives them
//               onto the AXI4 bus via the master clocking block.
//               Write flow : AW + W (parallel) → wait B
//               Read flow  : AR → wait R (all beats)
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_master_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_master_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase — get virtual interface from config_db
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
            `uvm_fatal(get_type_name(), "Virtual interface not found in config_db")
    endfunction : build_phase

    // =========================================================================
    // Run phase — main driver loop
    // =========================================================================
    task run_phase(uvm_phase phase);
        // Outer loop: recover from reset at any time during operation.
        // If reset is asserted mid-transaction, the fork is killed and
        // the driver re-initialises cleanly.
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted — master driver active", UVM_MEDIUM)

            fork
                begin : drive_loop
                    forever begin
                        axi4_transaction tr;
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Driving %s  ID=0x%0h  ADDR=0x%08h  LEN=%0d",
                                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_MEDIUM)
                        drive_transaction(tr);
                        seq_item_port.item_done();
                    end
                end
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted — aborting", UVM_MEDIUM)
                end
            join_any
            disable fork;
        end
    endtask : run_phase

    // =========================================================================
    // Reset — deassert all master-driven VALID / READY signals
    // =========================================================================
    task reset_signals();
        @(vif.master_cb);
        vif.master_cb.AWVALID <= 1'b0;
        vif.master_cb.WVALID  <= 1'b0;
        vif.master_cb.BREADY  <= 1'b0;
        vif.master_cb.ARVALID <= 1'b0;
        vif.master_cb.RREADY  <= 1'b0;
        vif.master_cb.WLAST   <= 1'b0;
    endtask : reset_signals

    // =========================================================================
    // Drive transaction — dispatch to write or read flow
    // =========================================================================
    task drive_transaction(axi4_transaction tr);
        case (tr.dir)
            AXI4_WRITE: begin
                // AXI4 allows AW and W in parallel
                fork
                    drive_aw_channel(tr);
                    drive_w_channel(tr);
                join
                collect_b_channel(tr);
            end
            AXI4_READ: begin
                drive_ar_channel(tr);
                collect_r_channel(tr);
            end
        endcase
    endtask : drive_transaction

    // =========================================================================
    // AW Channel — Write Address phase
    //   Assert AWVALID with address info, wait for AWREADY handshake.
    // =========================================================================
    task drive_aw_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.AWVALID  <= 1'b1;
        vif.master_cb.AWID     <= tr.id;
        vif.master_cb.AWADDR   <= tr.addr;
        vif.master_cb.AWLEN    <= tr.len;
        vif.master_cb.AWSIZE   <= tr.size;
        vif.master_cb.AWBURST  <= tr.burst;
        vif.master_cb.AWLOCK   <= tr.lock;
        vif.master_cb.AWCACHE  <= tr.cache;
        vif.master_cb.AWPROT   <= tr.prot;
        vif.master_cb.AWQOS    <= tr.qos;
        vif.master_cb.AWREGION <= tr.region;

        // Wait for AWREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.AWREADY);

        // Handshake complete — deassert VALID
        vif.master_cb.AWVALID <= 1'b0;
    endtask : drive_aw_channel

    // =========================================================================
    // W Channel — Write Data phase
    //   Drive data beats one by one, assert WLAST on the final beat.
    // =========================================================================
    task drive_w_channel(axi4_transaction tr);
        for (int i = 0; i <= tr.len; i++) begin
            @(vif.master_cb);
            vif.master_cb.WVALID <= 1'b1;
            vif.master_cb.WDATA  <= tr.data[i];
            vif.master_cb.WSTRB  <= tr.strb[i];
            vif.master_cb.WLAST  <= (i == tr.len) ? 1'b1 : 1'b0;

            // Wait for WREADY handshake
            do @(vif.master_cb);
            while (!vif.master_cb.WREADY);
        end

        // All beats sent — deassert
        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;
    endtask : drive_w_channel

    // =========================================================================
    // B Channel — Collect Write Response
    //   Assert BREADY, wait for BVALID, capture BRESP.
    // =========================================================================
    task collect_b_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.BREADY <= 1'b1;

        // Wait for BVALID handshake
        do @(vif.master_cb);
        while (!vif.master_cb.BVALID);

        // Capture response
        tr.resp = axi4_resp_e'(vif.master_cb.BRESP);

        vif.master_cb.BREADY <= 1'b0;
        `uvm_info(get_type_name(),
                  $sformatf("Write response: %s", tr.resp.name()), UVM_HIGH)
    endtask : collect_b_channel

    // =========================================================================
    // AR Channel — Read Address phase
    //   Assert ARVALID with address info, wait for ARREADY handshake.
    // =========================================================================
    task drive_ar_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.ARVALID  <= 1'b1;
        vif.master_cb.ARID     <= tr.id;
        vif.master_cb.ARADDR   <= tr.addr;
        vif.master_cb.ARLEN    <= tr.len;
        vif.master_cb.ARSIZE   <= tr.size;
        vif.master_cb.ARBURST  <= tr.burst;
        vif.master_cb.ARLOCK   <= tr.lock;
        vif.master_cb.ARCACHE  <= tr.cache;
        vif.master_cb.ARPROT   <= tr.prot;
        vif.master_cb.ARQOS    <= tr.qos;
        vif.master_cb.ARREGION <= tr.region;

        // Wait for ARREADY handshake
        do @(vif.master_cb);
        while (!vif.master_cb.ARREADY);

        // Handshake complete — deassert VALID
        vif.master_cb.ARVALID <= 1'b0;
    endtask : drive_ar_channel

    // =========================================================================
    // R Channel — Collect Read Data
    //   Assert RREADY, receive each beat, verify RLAST on final beat.
    // =========================================================================
    task collect_r_channel(axi4_transaction tr);
        @(vif.master_cb);
        vif.master_cb.RREADY <= 1'b1;

        for (int i = 0; i <= tr.len; i++) begin
            // Wait for RVALID handshake
            do @(vif.master_cb);
            while (!vif.master_cb.RVALID);

            // Capture beat data + per-beat response
            tr.data[i]  = vif.master_cb.RDATA;
            tr.rresp[i] = axi4_resp_e'(vif.master_cb.RRESP);

            // Check RLAST on final beat
            if (i == tr.len && !vif.master_cb.RLAST)
                `uvm_error(get_type_name(),
                           $sformatf("RLAST not asserted on final beat %0d", i))
            if (i != tr.len && vif.master_cb.RLAST)
                `uvm_error(get_type_name(),
                           $sformatf("Unexpected RLAST on beat %0d of %0d", i, tr.len))
        end

        vif.master_cb.RREADY <= 1'b0;
        `uvm_info(get_type_name(),
                  $sformatf("Read complete: %0d beats received", tr.len + 1), UVM_HIGH)
    endtask : collect_r_channel

endclass : axi4_master_driver