//==============================================================================
// File        : axi4_scoreboard.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 scoreboard.
//               Receives completed transactions from both master and slave
//               monitors, matches them by (dir, id, addr), and compares all
//               fields using axi4_transaction::compare() (which includes
//               the manual rresp[] comparison via do_compare).
//
//               Matching strategy:
//                 When a transaction arrives from one side, search the other
//                 side's queue for a match by (id, addr). If found, compare
//                 immediately. If not, queue for later matching.
//                 This handles out-of-order and timing-skewed arrivals.
//
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

// ---- Analysis port suffix declarations (must be outside class) ----
`uvm_analysis_imp_decl(_master)
`uvm_analysis_imp_decl(_slave)

class axi4_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axi4_scoreboard)

    // =========================================================================
    // Analysis imports — one per monitor side
    // =========================================================================
    uvm_analysis_imp_master #(axi4_transaction, axi4_scoreboard) master_export;
    uvm_analysis_imp_slave  #(axi4_transaction, axi4_scoreboard) slave_export;

    // =========================================================================
    // Unmatched transaction queues
    //   Separated by direction for efficient matching.
    //   When a transaction arrives from one side and no match exists on the
    //   other side, it is queued here until the counterpart arrives.
    // =========================================================================
    axi4_transaction master_wr_q[$];
    axi4_transaction master_rd_q[$];
    axi4_transaction slave_wr_q[$];
    axi4_transaction slave_rd_q[$];

    // =========================================================================
    // Statistics
    // =========================================================================
    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;
    int unsigned total_master   = 0;
    int unsigned total_slave    = 0;

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    // =========================================================================
    // Build phase — create analysis imports
    // =========================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        master_export = new("master_export", this);
        slave_export  = new("slave_export",  this);
    endfunction : build_phase

    // =========================================================================
    // write_master — called when master monitor broadcasts a completed txn
    // =========================================================================
    function void write_master(axi4_transaction t);
        axi4_transaction tr;
        total_master++;

        // Deep copy — the monitor may reuse the object
        tr = axi4_transaction::type_id::create("master_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Master %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, master_wr_q, slave_wr_q, "WRITE");
        else
            try_match(tr, master_rd_q, slave_rd_q, "READ");
    endfunction : write_master

    // =========================================================================
    // write_slave — called when slave monitor broadcasts a completed txn
    // =========================================================================
    function void write_slave(axi4_transaction t);
        axi4_transaction tr;
        total_slave++;

        // Deep copy
        tr = axi4_transaction::type_id::create("slave_tr");
        tr.copy(t);

        `uvm_info(get_type_name(),
                  $sformatf("Slave %s received: ID=0x%0h ADDR=0x%08h LEN=%0d",
                            tr.dir.name(), tr.id, tr.addr, tr.len), UVM_HIGH)

        if (tr.dir == AXI4_WRITE)
            try_match(tr, slave_wr_q, master_wr_q, "WRITE");
        else
            try_match(tr, slave_rd_q, master_rd_q, "READ");
    endfunction : write_slave

    // =========================================================================
    // try_match — search for matching transaction on the other side
    //   Match key: (id, addr)
    //   If found:  compare and consume both.
    //   If not:    push to own queue for future matching.
    //   FIFO ordering within same (id, addr) pairs is preserved.
    // =========================================================================
    function void try_match(
        axi4_transaction     new_tr,
        ref axi4_transaction own_q[$],
        ref axi4_transaction other_q[$],
        string               dir_str
    );
        // Search other side's queue for a matching transaction
        for (int i = 0; i < other_q.size(); i++) begin
            if (other_q[i].id == new_tr.id && other_q[i].addr == new_tr.addr) begin
                // Match found — compare and consume
                axi4_transaction ref_tr = other_q[i];
                other_q.delete(i);
                compare_transactions(ref_tr, new_tr, dir_str);
                return;
            end
        end

        // No match on other side — queue for later
        own_q.push_back(new_tr);
    endfunction : try_match

    // =========================================================================
    // compare_transactions — detailed comparison using do_compare
    //   Uses axi4_transaction::compare() which internally calls do_compare
    //   for all fields including the manually-handled rresp[] array.
    // =========================================================================
    function void compare_transactions(
        axi4_transaction expected,
        axi4_transaction actual,
        string           dir_str
    );
        if (expected.compare(actual)) begin
            match_count++;
            `uvm_info(get_type_name(),
                      $sformatf("[%s] MATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                dir_str, match_count,
                                actual.id, actual.addr, actual.len), UVM_MEDIUM)
        end else begin
            mismatch_count++;
            `uvm_error(get_type_name(),
                       $sformatf("[%s] MISMATCH #%0d: ID=0x%0h ADDR=0x%08h LEN=%0d",
                                 dir_str, mismatch_count,
                                 actual.id, actual.addr, actual.len))
            `uvm_info(get_type_name(),
                      {"Expected:\n", expected.sprint()}, UVM_LOW)
            `uvm_info(get_type_name(),
                      {"Actual:\n", actual.sprint()}, UVM_LOW)
        end
    endfunction : compare_transactions

    // =========================================================================
    // check_phase — flag errors for unmatched/mismatched transactions
    // =========================================================================
    function void check_phase(uvm_phase phase);
        int unsigned unmatched;
        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        if (mismatch_count > 0)
            `uvm_error(get_type_name(),
                       $sformatf("%0d transaction MISMATCHES detected", mismatch_count))

        if (unmatched > 0)
            `uvm_warning(get_type_name(),
                         $sformatf("%0d unmatched transactions at end of simulation",
                                   unmatched))
    endfunction : check_phase

    // =========================================================================
    // report_phase — print summary statistics
    // =========================================================================
    function void report_phase(uvm_phase phase);
        int unsigned unmatched;
        string result_str;

        unmatched = master_wr_q.size() + master_rd_q.size()
                  + slave_wr_q.size()  + slave_rd_q.size();

        result_str = (mismatch_count == 0 && unmatched == 0) ? "PASS" : "FAIL";

        `uvm_info(get_type_name(), $sformatf({
            "\n",
            "========================================\n",
            "         SCOREBOARD SUMMARY\n",
            "========================================\n",
            "  Master transactions : %0d\n",
            "  Slave transactions  : %0d\n",
            "  Matches             : %0d\n",
            "  Mismatches          : %0d\n",
            "  Unmatched master WR : %0d\n",
            "  Unmatched master RD : %0d\n",
            "  Unmatched slave  WR : %0d\n",
            "  Unmatched slave  RD : %0d\n",
            "========================================\n",
            "  RESULT : %s\n",
            "========================================"},
            total_master, total_slave,
            match_count, mismatch_count,
            master_wr_q.size(), master_rd_q.size(),
            slave_wr_q.size(), slave_rd_q.size(),
            result_str), UVM_NONE)
    endfunction : report_phase

endclass : axi4_scoreboard
