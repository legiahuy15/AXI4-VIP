//==============================================================================
// File        : axi4_transaction.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 sequence item (transaction object).
//               Contains all fields for a single AXI4 read/write transaction,
//               constraints per AXI4 spec, and utility methods for debug.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_transaction extends uvm_sequence_item;

    // =========================================================================
    // Transaction fields
    // =========================================================================

    // Direction (VIP-internal)
    rand axi4_dir_e                         dir;

    // Address channel (shared between AW and AR)
    rand bit [AXI4_ID_WIDTH-1:0]            id;
    rand bit [AXI4_ADDR_WIDTH-1:0]          addr;
    rand bit [AXI4_LEN_WIDTH-1:0]           len;        // Burst length = len + 1 beats
    rand axi4_size_e                        size;
    rand axi4_burst_type_e                  burst;
    rand axi4_lock_e                        lock;
    rand bit [3:0]                          cache;
    rand bit [2:0]                          prot;
    rand bit [3:0]                          qos;
    rand bit [3:0]                          region;

    // Write data channel
    rand bit [AXI4_DATA_WIDTH-1:0]          data[];     // One entry per beat
    rand bit [AXI4_STRB_WIDTH-1:0]          strb[];     // One entry per beat

    // Response (B channel for write, R channel per beat for read)
    rand axi4_resp_e                        resp;

    // =========================================================================
    // UVM utility macro
    // =========================================================================
    `uvm_object_utils_begin(axi4_transaction)
        `uvm_field_enum(axi4_dir_e,        dir,    UVM_ALL_ON)
        `uvm_field_int(                    id,     UVM_ALL_ON)
        `uvm_field_int(                    addr,   UVM_ALL_ON)
        `uvm_field_int(                    len,    UVM_ALL_ON)
        `uvm_field_enum(axi4_size_e,       size,   UVM_ALL_ON)
        `uvm_field_enum(axi4_burst_type_e, burst,  UVM_ALL_ON)
        `uvm_field_enum(axi4_lock_e,       lock,   UVM_ALL_ON)
        `uvm_field_int(                    cache,  UVM_ALL_ON)
        `uvm_field_int(                    prot,   UVM_ALL_ON)
        `uvm_field_int(                    qos,    UVM_ALL_ON)
        `uvm_field_int(                    region, UVM_ALL_ON)
        `uvm_field_array_int(              data,   UVM_ALL_ON)
        `uvm_field_array_int(              strb,   UVM_ALL_ON)
        `uvm_field_enum(axi4_resp_e,       resp,   UVM_ALL_ON)
    `uvm_object_utils_end

    // =========================================================================
    // Constraints
    // =========================================================================

    // Data / strobe array size must match burst length
    constraint c_data_size {
        data.size() == len + 1;
    }

    constraint c_strb_size {
        strb.size() == len + 1;
    }

    // Burst size must not exceed data bus width
    // 2^size <= DATA_WIDTH / 8  →  size <= log2(DATA_WIDTH / 8)
    constraint c_size_max {
        (1 << size) <= (AXI4_DATA_WIDTH / 8);
    }

    // WRAP burst: len must be 2, 4, 8, or 16 beats (len = 1, 3, 7, 15)
    constraint c_wrap_len {
        (burst == AXI4_BURST_WRAP) -> len inside {1, 3, 7, 15};
    }

    // WRAP burst: start address must be aligned to transfer size
    constraint c_wrap_align {
        (burst == AXI4_BURST_WRAP) -> (addr % (1 << size)) == 0;
    }

    // FIXED burst: length must not exceed 16 beats (AXI4 spec)
    constraint c_fixed_len {
        (burst == AXI4_BURST_FIXED) -> len <= 15;
    }

    // Read transactions: strobe is not used, set to all-1s
    constraint c_read_strb {
        if (dir == AXI4_READ) {
            foreach (strb[i]) strb[i] == {AXI4_STRB_WIDTH{1'b1}};
        }
    }

    // Default distribution: favour common burst types
    constraint c_burst_dist {
        burst dist {
            AXI4_BURST_INCR  := 60,
            AXI4_BURST_FIXED := 20,
            AXI4_BURST_WRAP  := 20
        };
    }

    // Default distribution: favour shorter bursts for faster sim
    constraint c_len_dist {
        len dist {
            0       := 30,      // single beat
            [1:3]   := 30,      // 2-4 beats
            [4:15]  := 25,      // 5-16 beats
            [16:255]:= 15       // 17-256 beats
        };
    }

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name = "axi4_transaction");
        super.new(name);
    endfunction : new

    // =========================================================================
    // convert2string — human-readable transaction summary for debug
    // =========================================================================
    function string convert2string();
        string s;
        s = $sformatf("\n---------- AXI4 Transaction ----------");
        s = {s, $sformatf("\n DIR    = %s",     dir.name())};
        s = {s, $sformatf("\n ID     = 0x%0h",  id)};
        s = {s, $sformatf("\n ADDR   = 0x%08h", addr)};
        s = {s, $sformatf("\n LEN    = %0d (beats = %0d)", len, len + 1)};
        s = {s, $sformatf("\n SIZE   = %s (%0d bytes/beat)", size.name(), 1 << size)};
        s = {s, $sformatf("\n BURST  = %s",     burst.name())};
        s = {s, $sformatf("\n LOCK   = %s",     lock.name())};
        s = {s, $sformatf("\n RESP   = %s",     resp.name())};
        s = {s, $sformatf("\n DATA[%0d] = {",   data.size())};
        foreach (data[i]) begin
            s = {s, $sformatf("\n   [%0d] 0x%08h  STRB=0b%0b", i, data[i], strb[i])};
        end
        s = {s, "\n }"};
        s = {s, "\n---------------------------------------\n"};
        return s;
    endfunction : convert2string

endclass : axi4_transaction