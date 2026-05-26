//==============================================================================
// File        : axi4_slave_driver.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 reactive slave driver.
//               Listens on the bus for incoming master requests and generates
//               responses automatically. Contains a built-in byte-addressable
//               memory model for data storage and retrieval.
//               Write flow : wait AW → collect W beats → store to mem → send B
//               Read flow  : wait AR → read from mem → send R beats
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_slave_driver extends uvm_driver #(axi4_transaction);

    `uvm_component_utils(axi4_slave_driver)

    // Virtual interface handle
    virtual axi4_if vif;

    // =========================================================================
    // Built-in memory model (byte-addressable)
    // =========================================================================
    bit [7:0] mem [bit [AXI4_ADDR_WIDTH-1:0]];

    // =========================================================================
    // Configurable delays — set via config_db or directly for back-pressure
    //   ready_delay : cycles before asserting xREADY (simulates slow slave)
    //   resp_delay  : cycles before driving B/R response
    //   When max = 0, no delay is inserted.
    // =========================================================================
    int unsigned ready_delay_min = 0;
    int unsigned ready_delay_max = 0;
    int unsigned resp_delay_min  = 0;
    int unsigned resp_delay_max  = 0;

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
        // Optional delay configuration — tests can set these via config_db
        void'(uvm_config_db#(int unsigned)::get(this, "", "ready_delay_min", ready_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "ready_delay_max", ready_delay_max));
        void'(uvm_config_db#(int unsigned)::get(this, "", "resp_delay_min",  resp_delay_min));
        void'(uvm_config_db#(int unsigned)::get(this, "", "resp_delay_max",  resp_delay_max));
    endfunction : build_phase

    // =========================================================================
    // Run phase — reactive slave: fork write & read handlers
    // =========================================================================
    task run_phase(uvm_phase phase);
        // Outer loop: recover from reset at any time during operation
        forever begin
            reset_signals();
            @(posedge vif.rst_n);
            `uvm_info(get_type_name(), "Reset deasserted — slave driver active", UVM_MEDIUM)

            fork
                begin : slave_loop
                    fork
                        handle_writes();
                        handle_reads();
                    join
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
    // Reset — deassert all slave-driven READY / VALID signals
    // =========================================================================
    task reset_signals();
        @(vif.slave_cb);
        vif.slave_cb.AWREADY <= 1'b0;
        vif.slave_cb.WREADY  <= 1'b0;
        vif.slave_cb.BVALID  <= 1'b0;
        vif.slave_cb.ARREADY <= 1'b0;
        vif.slave_cb.RVALID  <= 1'b0;
        vif.slave_cb.RLAST   <= 1'b0;
    endtask : reset_signals

    // =========================================================================
    // Delay helpers — insert random back-pressure / response latency
    // =========================================================================
    task rand_ready_delay();
        int unsigned delay;
        if (ready_delay_max > 0) begin
            delay = $urandom_range(ready_delay_max, ready_delay_min);
            repeat (delay) @(vif.slave_cb);
        end
    endtask : rand_ready_delay

    task rand_resp_delay();
        int unsigned delay;
        if (resp_delay_max > 0) begin
            delay = $urandom_range(resp_delay_max, resp_delay_min);
            repeat (delay) @(vif.slave_cb);
        end
    endtask : rand_resp_delay

    // =========================================================================
    // Handle Writes — forever loop processing write requests
    //   1. Wait for AW handshake, capture address info
    //   2. Collect all W beats, store to memory
    //   3. Send B response
    // =========================================================================
    task handle_writes();
        bit [AXI4_ID_WIDTH-1:0]   aw_id;
        bit [AXI4_ADDR_WIDTH-1:0] aw_addr;
        bit [7:0]                 aw_len;
        bit [2:0]                 aw_size;
        bit [1:0]                 aw_burst;

        forever begin
            // ----- AW handshake -----
            // Wait for AWVALID from master
            do @(vif.slave_cb);
            while (!vif.slave_cb.AWVALID);

            // Capture address info
            aw_id    = vif.slave_cb.AWID;
            aw_addr  = vif.slave_cb.AWADDR;
            aw_len   = vif.slave_cb.AWLEN;
            aw_size  = vif.slave_cb.AWSIZE;
            aw_burst = vif.slave_cb.AWBURST;

            // Assert AWREADY to complete handshake (with optional delay)
            rand_ready_delay();
            vif.slave_cb.AWREADY <= 1'b1;
            @(vif.slave_cb);
            vif.slave_cb.AWREADY <= 1'b0;

            `uvm_info(get_type_name(),
                      $sformatf("AW received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                aw_id, aw_addr, aw_len), UVM_HIGH)

            // ----- W beats -----
            for (int beat = 0; beat <= aw_len; beat++) begin
                bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
                bit [AXI4_DATA_WIDTH-1:0] wdata;
                bit [AXI4_STRB_WIDTH-1:0] wstrb;

                // Wait for WVALID
                do @(vif.slave_cb);
                while (!vif.slave_cb.WVALID);

                // Capture data
                wdata = vif.slave_cb.WDATA;
                wstrb = vif.slave_cb.WSTRB;

                // Check WLAST
                if (beat == aw_len && !vif.slave_cb.WLAST)
                    `uvm_error(get_type_name(),
                               $sformatf("WLAST not asserted on final beat %0d", beat))

                // Store data to memory (byte-level write with WSTRB)
                beat_addr = calc_beat_addr(aw_addr, beat, aw_size, aw_burst, aw_len);
                for (int b = 0; b < AXI4_STRB_WIDTH; b++) begin
                    if (wstrb[b])
                        mem[beat_addr + b] = wdata[b*8 +: 8];
                end

                // Assert WREADY to complete handshake (with optional delay)
                rand_ready_delay();
                vif.slave_cb.WREADY <= 1'b1;
                @(vif.slave_cb);
                vif.slave_cb.WREADY <= 1'b0;
            end

            // ----- B response (with optional delay) -----
            rand_resp_delay();
            @(vif.slave_cb);
            vif.slave_cb.BID    <= aw_id;
            vif.slave_cb.BRESP  <= AXI4_RESP_OKAY;
            vif.slave_cb.BVALID <= 1'b1;

            // Wait for BREADY handshake
            do @(vif.slave_cb);
            while (!vif.slave_cb.BREADY);

            vif.slave_cb.BVALID <= 1'b0;

            `uvm_info(get_type_name(),
                      $sformatf("Write complete: ID=0x%0h  %0d beats stored",
                                aw_id, aw_len + 1), UVM_MEDIUM)
        end
    endtask : handle_writes

    // =========================================================================
    // Handle Reads — forever loop processing read requests
    //   1. Wait for AR handshake, capture address info
    //   2. Read data from memory, send R beats with RLAST
    // =========================================================================
    task handle_reads();
        bit [AXI4_ID_WIDTH-1:0]   ar_id;
        bit [AXI4_ADDR_WIDTH-1:0] ar_addr;
        bit [7:0]                 ar_len;
        bit [2:0]                 ar_size;
        bit [1:0]                 ar_burst;

        forever begin
            // ----- AR handshake -----
            do @(vif.slave_cb);
            while (!vif.slave_cb.ARVALID);

            // Capture address info
            ar_id    = vif.slave_cb.ARID;
            ar_addr  = vif.slave_cb.ARADDR;
            ar_len   = vif.slave_cb.ARLEN;
            ar_size  = vif.slave_cb.ARSIZE;
            ar_burst = vif.slave_cb.ARBURST;

            // Assert ARREADY to complete handshake (with optional delay)
            rand_ready_delay();
            vif.slave_cb.ARREADY <= 1'b1;
            @(vif.slave_cb);
            vif.slave_cb.ARREADY <= 1'b0;

            `uvm_info(get_type_name(),
                      $sformatf("AR received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                ar_id, ar_addr, ar_len), UVM_HIGH)

            // ----- R beats -----
            for (int beat = 0; beat <= ar_len; beat++) begin
                bit [AXI4_ADDR_WIDTH-1:0] beat_addr;
                bit [AXI4_DATA_WIDTH-1:0] rdata;

                // Read data from memory (byte-by-byte)
                beat_addr = calc_beat_addr(ar_addr, beat, ar_size, ar_burst, ar_len);
                rdata = '0;
                for (int b = 0; b < (1 << ar_size); b++) begin
                    if (mem.exists(beat_addr + b))
                        rdata[b*8 +: 8] = mem[beat_addr + b];
                end

                // Drive R channel (with optional response delay)
                rand_resp_delay();
                @(vif.slave_cb);
                vif.slave_cb.RID    <= ar_id;
                vif.slave_cb.RDATA  <= rdata;
                vif.slave_cb.RRESP  <= AXI4_RESP_OKAY;
                vif.slave_cb.RLAST  <= (beat == ar_len) ? 1'b1 : 1'b0;
                vif.slave_cb.RVALID <= 1'b1;

                // Wait for RREADY handshake
                do @(vif.slave_cb);
                while (!vif.slave_cb.RREADY);

                vif.slave_cb.RVALID <= 1'b0;
                vif.slave_cb.RLAST  <= 1'b0;
            end

            `uvm_info(get_type_name(),
                      $sformatf("Read complete: ID=0x%0h  %0d beats sent",
                                ar_id, ar_len + 1), UVM_MEDIUM)
        end
    endtask : handle_reads

    // =========================================================================
    // calc_beat_addr — Calculate address for each beat in a burst
    //   Supports FIXED, INCR, and WRAP burst types per AXI4 spec.
    // =========================================================================
    function bit [AXI4_ADDR_WIDTH-1:0] calc_beat_addr(
        bit [AXI4_ADDR_WIDTH-1:0] start_addr,
        int unsigned              beat_idx,
        bit [2:0]                 size,
        bit [1:0]                 burst_type,
        bit [7:0]                 len
    );
        int unsigned num_bytes  = 1 << size;
        int unsigned burst_len  = len + 1;
        bit [AXI4_ADDR_WIDTH-1:0] aligned_addr;
        bit [AXI4_ADDR_WIDTH-1:0] addr;

        // Aligned start address (first beat may be unaligned for INCR)
        aligned_addr = (start_addr / num_bytes) * num_bytes;

        case (burst_type)
            // ---- FIXED: every beat uses the same address ----
            2'b00: begin
                addr = start_addr;
            end

            // ---- INCR: address increments by num_bytes each beat ----
            //   Beat 0 = start_addr (possibly unaligned)
            //   Beat N = aligned_addr + N * num_bytes
            2'b01: begin
                if (beat_idx == 0)
                    addr = start_addr;
                else
                    addr = aligned_addr + beat_idx * num_bytes;
            end

            // ---- WRAP: address wraps at boundary ----
            //   Wrap boundary = aligned to (num_bytes * burst_len)
            2'b10: begin
                int unsigned total_size   = num_bytes * burst_len;
                bit [AXI4_ADDR_WIDTH-1:0] wrap_boundary;
                wrap_boundary = (start_addr / total_size) * total_size;

                if (beat_idx == 0)
                    addr = start_addr;
                else begin
                    addr = aligned_addr + beat_idx * num_bytes;
                    // Wrap around if we exceed the upper boundary
                    if (addr >= wrap_boundary + total_size)
                        addr = addr - total_size;
                end
            end

            default: addr = start_addr;
        endcase

        return addr;
    endfunction : calc_beat_addr

endclass : axi4_slave_driver