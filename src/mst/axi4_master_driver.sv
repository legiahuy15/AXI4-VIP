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

    // Semaphores for channel serialization to prevent multi-driver conflict
    protected semaphore aw_sem;
    protected semaphore w_sem;
    protected semaphore ar_sem;

    // Queues and tables for tracking outstanding transactions
    protected axi4_transaction pending_b_tr[bit[AXI4_ID_WIDTH-1:0]][$];
    protected axi4_transaction pending_r_tr[bit[AXI4_ID_WIDTH-1:0]][$];

    // Completion status maps to unblock finish_item threads
    protected bit wr_done_flag[axi4_transaction];
    protected bit rd_done_flag[axi4_transaction];

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
        aw_sem = new(1);
        w_sem  = new(1);
        ar_sem = new(1);
    endfunction : build_phase

    // =========================================================================
    // Run phase — main driver loop (supports parallel/pipelined outstanding transactions)
    // =========================================================================
    task run_phase(uvm_phase phase);
        // Outer loop: recover from reset at any time during operation.
        // If reset is asserted mid-transaction, the fork is killed and
        // the driver re-initialises cleanly.
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted - master driver active", UVM_MEDIUM)

            fork
                begin : drive_loop
                    forever begin
                        axi4_transaction tr;
                        seq_item_port.get_next_item(tr);
                        `uvm_info(get_type_name(),
                                  $sformatf("Driving %s  ID=0x%0h  ADDR=0x%08h  LEN=%0d",
                                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_MEDIUM)
                        fork
                            automatic axi4_transaction active_tr = tr;
                            begin
                                drive_transaction(active_tr);
                            end
                        join_none
                        seq_item_port.item_done();
                    end
                end
                receive_b_responses();
                receive_r_responses();
                begin : rst_watch
                    @(negedge vif.rst_n);
                    `uvm_info(get_type_name(), "Reset asserted - aborting", UVM_MEDIUM)
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

        pending_b_tr.delete();
        pending_r_tr.delete();
        wr_done_flag.delete();
        rd_done_flag.delete();
    endtask : reset_signals

    // =========================================================================
    // Drive transaction — dispatch to write or read flow
    //   Write channel ordering is controlled by tr.wr_order:
    //     PARALLEL    — AW and W start simultaneously (default)
    //     AW_BEFORE_W — AW handshake completes, then W data begins
    //     W_BEFORE_AW — W data begins first, AW follows after a short delay
    // =========================================================================
    task drive_transaction(axi4_transaction tr);
        case (tr.dir)
            AXI4_WRITE: begin
                pending_b_tr[tr.id].push_back(tr);
                wr_done_flag[tr] = 0;
                case (tr.wr_order)
                    AXI4_WR_PARALLEL: begin
                        `uvm_info(get_type_name(), "Write order: AW || W (parallel)", UVM_MEDIUM)
                        fork
                            drive_aw_channel(tr);
                            drive_w_channel(tr);
                        join
                    end
                    AXI4_WR_AW_BEFORE_W: begin
                        `uvm_info(get_type_name(), "Write order: AW -> W (sequential)", UVM_MEDIUM)
                        drive_aw_channel(tr);
                        drive_w_channel(tr);
                    end
                    AXI4_WR_W_BEFORE_AW: begin
                        `uvm_info(get_type_name(), "Write order: W -> AW (W first)", UVM_MEDIUM)
                        fork
                            drive_w_channel(tr);
                            begin
                                // Delay AW so W channel starts first (2-5 cycles gap)
                                repeat ($urandom_range(5, 2)) @(vif.master_cb);
                                drive_aw_channel(tr);
                            end
                        join
                    end
                    default: begin
                        fork
                            drive_aw_channel(tr);
                            drive_w_channel(tr);
                        join
                    end
                endcase
                wait (wr_done_flag[tr] == 1);
                wr_done_flag.delete(tr);
            end
            AXI4_READ: begin
                pending_r_tr[tr.id].push_back(tr);
                rd_done_flag[tr] = 0;
                drive_ar_channel(tr);
                wait (rd_done_flag[tr] == 1);
                rd_done_flag.delete(tr);
            end
        endcase
    endtask : drive_transaction

    // =========================================================================
    // AW Channel — Write Address phase
    //   Assert AWVALID with address info, wait for AWREADY handshake.
    // =========================================================================
    task drive_aw_channel(axi4_transaction tr);
        aw_sem.get(1);
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
        aw_sem.put(1);
    endtask : drive_aw_channel

    // =========================================================================
    // W Channel — Write Data phase
    //   Drive data beats one by one, assert WLAST on the final beat.
    // =========================================================================
    task drive_w_channel(axi4_transaction tr);
        w_sem.get(1);
        for (int i = 0; i <= tr.len; i++) begin
            @(vif.master_cb);
            vif.master_cb.WVALID <= 1'b1;
            vif.master_cb.WDATA  <= tr.data[i];
            vif.master_cb.WSTRB  <= tr.strb[i];
            vif.master_cb.WLAST   <= (i == tr.len) ? 1'b1 : 1'b0;

            // Wait for WREADY handshake
            do @(vif.master_cb);
            while (!vif.master_cb.WREADY);
        end

        // All beats sent — deassert
        vif.master_cb.WVALID <= 1'b0;
        vif.master_cb.WLAST  <= 1'b0;
        w_sem.put(1);
    endtask : drive_w_channel

    // =========================================================================
    // AR Channel — Read Address phase
    //   Assert ARVALID with address info, wait for ARREADY handshake.
    // =========================================================================
    task drive_ar_channel(axi4_transaction tr);
        ar_sem.get(1);
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
        ar_sem.put(1);
    endtask : drive_ar_channel

    // =========================================================================
    // B Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_b_responses();
        vif.master_cb.BREADY <= 1'b1;
        forever begin
            @(vif.master_cb);
            if (vif.master_cb.BVALID) begin
                bit [AXI4_ID_WIDTH-1:0] bid;
                bid = vif.master_cb.BID;
                if (pending_b_tr.exists(bid) && pending_b_tr[bid].size() > 0) begin
                    axi4_transaction tr;
                    tr = pending_b_tr[bid].pop_front();
                    tr.resp = axi4_resp_e'(vif.master_cb.BRESP);
                    wr_done_flag[tr] = 1;
                    `uvm_info(get_type_name(),
                              $sformatf("Master driver received B response: ID=0x%0h RESP=%s",
                                        tr.id, tr.resp.name()), UVM_HIGH)
                end else begin
                    `uvm_error(get_type_name(),
                               $sformatf("Master driver received unexpected B response ID=0x%0h", bid))
                end
            end
        end
    endtask : receive_b_responses

    // =========================================================================
    // R Channel response receiver (kept active in parallel)
    // =========================================================================
    task receive_r_responses();
        vif.master_cb.RREADY <= 1'b1;
        forever begin
            bit [AXI4_ID_WIDTH-1:0] rid;
            axi4_transaction tr;

            do @(vif.master_cb);
            while (!vif.master_cb.RVALID);

            rid = vif.master_cb.RID;

            if (pending_r_tr.exists(rid) && pending_r_tr[rid].size() > 0) begin
                tr = pending_r_tr[rid].pop_front();
                tr.data[0]  = vif.master_cb.RDATA;
                tr.rresp[0] = axi4_resp_e'(vif.master_cb.RRESP);

                if (tr.len == 0) begin
                    if (!vif.master_cb.RLAST)
                        `uvm_error(get_type_name(),
                                   $sformatf("RLAST not asserted on single-beat read (ID=0x%0h)", rid))
                end else begin
                    for (int i = 1; i <= tr.len; i++) begin
                        do @(vif.master_cb);
                        while (!vif.master_cb.RVALID);
                        
                        tr.data[i]  = vif.master_cb.RDATA;
                        tr.rresp[i] = axi4_resp_e'(vif.master_cb.RRESP);

                        if (i == tr.len && !vif.master_cb.RLAST)
                            `uvm_error(get_type_name(),
                                       $sformatf("RLAST not asserted on final beat %0d (ID=0x%0h)", i, rid))
                        if (i != tr.len && vif.master_cb.RLAST)
                            `uvm_error(get_type_name(),
                                       $sformatf("Unexpected RLAST on beat %0d of %0d (ID=0x%0h)", i, tr.len, rid))
                    end
                end
                
                rd_done_flag[tr] = 1;
                `uvm_info(get_type_name(),
                          $sformatf("Master driver received all R beats for ID=0x%0h", tr.id), UVM_HIGH)
            end else begin
                `uvm_error(get_type_name(),
                           $sformatf("Master driver received unexpected R response ID=0x%0h", rid))
                while (!vif.master_cb.RLAST) begin
                    do @(vif.master_cb);
                    while (!vif.master_cb.RVALID);
                end
            end
        end
    endtask : receive_r_responses

endclass : axi4_master_driver