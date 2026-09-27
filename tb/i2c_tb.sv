

`timescale 1ns/1ps

// ==========================================================================
// 1. Interface
// ==========================================================================
interface i2c_if (
    input bit clk,
    input bit rst_n
);

    logic       start;
    logic [6:0] addr;
    logic [7:0] data_in;
    logic       scl;
    logic       sda;
    logic       busy;
    logic       done;

    clocking driver_cb @(posedge clk);
        output start, addr, data_in;
        input  busy, done;
    endclocking

    clocking monitor_cb @(posedge clk);
        input start, addr, data_in, scl, sda, busy, done;
    endclocking

    modport DRIVER  (clocking driver_cb);
    modport MONITOR (clocking monitor_cb, input scl, sda, busy, done);

    // ---- Blackbox protocol assertions (port-level contract only) ----

    property p_idle_levels;
        @(posedge clk) disable iff (!rst_n)
            (busy == 1'b0) |-> (scl == 1'b1 && sda == 1'b1);
    endproperty
    a_idle_levels: assert property (p_idle_levels)
        else $error("[ASSERT:i2c_if] SCL/SDA not idle-high while busy=0 (scl=%0b sda=%0b)", scl, sda);

    property p_no_start_while_busy;
        @(posedge clk) disable iff (!rst_n)
            (busy == 1'b1) |-> !$rose(start);
    endproperty
    a_no_start_while_busy: assert property (p_no_start_while_busy)
        else $error("[ASSERT:i2c_if] start asserted while busy=1");

    property p_no_x_on_bus;
        @(posedge clk) disable iff (!rst_n)
            !$isunknown({scl, sda, busy, done});
    endproperty
    a_no_x_on_bus: assert property (p_no_x_on_bus)
        else $error("[ASSERT:i2c_if] X/Z detected on scl/sda/busy/done");

endinterface


// ==========================================================================
// 2. Whitebox assertions (bound into i2c_master - sees internal FSM state)
// ==========================================================================
module i2c_assertions (
    input wire       clk,
    input wire       rst_n,
    input wire [2:0] state,
    input wire [3:0] bit_idx,
    input wire       scl,
    input wire       sda,
    input wire       busy,
    input wire       done
);
    // Mirrors i2c_master's state_t encoding (declaration order -> 0..4).
    localparam ST_IDLE       = 3'd0;
    localparam ST_START_COND = 3'd1;
    localparam ST_ADDR_BITS  = 3'd2;
    localparam ST_DATA_BITS  = 3'd3;
    localparam ST_STOP_COND  = 3'd4;

    property p_done_one_cycle;
        @(posedge clk) disable iff (!rst_n)
            done |=> !done;
    endproperty
    a_done_one_cycle: assert property (p_done_one_cycle)
        else $error("[ASSERT:whitebox] done stayed high for more than one cycle");

    property p_busy_drop_only_with_done;
        @(posedge clk) disable iff (!rst_n)
            $fell(busy) |-> done;
    endproperty
    a_busy_drop_only_with_done: assert property (p_busy_drop_only_with_done)
        else $error("[ASSERT:whitebox] busy dropped without done pulsing");

    property p_legal_state;
        @(posedge clk) disable iff (!rst_n)
            state inside {ST_IDLE, ST_START_COND, ST_ADDR_BITS, ST_DATA_BITS, ST_STOP_COND};
    endproperty
    a_legal_state: assert property (p_legal_state)
        else $error("[ASSERT:whitebox] FSM entered illegal state %0d", state);

    property p_bit_idx_range;
        @(posedge clk) disable iff (!rst_n)
            (state == ST_ADDR_BITS || state == ST_DATA_BITS) |-> (bit_idx <= 4'd7);
    endproperty
    a_bit_idx_range: assert property (p_bit_idx_range)
        else $error("[ASSERT:whitebox] bit_idx out of range: %0d in state %0d", bit_idx, state);

    property p_no_stuck_state;
        @(posedge clk) disable iff (!rst_n)
            (state != ST_IDLE) |-> ##[1:2048] (state == ST_IDLE);
    endproperty
    a_no_stuck_state: assert property (p_no_stuck_state)
        else $error("[ASSERT:whitebox] FSM appears stuck outside IDLE");

endmodule


// ==========================================================================
// 3. Verification package
// ==========================================================================
package i2c_pkg;

    // ---- Transaction ----
    class i2c_transaction;
        rand bit [6:0] addr;
        rand bit [7:0] data;
        bit            rw;   // filled in by monitor on decode; driver always writes (rw=0)

        constraint c_addr_dist {
            addr dist { 7'h00         :/ 5,
                        7'h7F         :/ 5,
                        [7'h01:7'h7E] :/ 90 };
        }
        constraint c_data_dist {
            data dist { 8'h00         :/ 5,
                        8'hFF         :/ 5,
                        [8'h01:8'hFE] :/ 90 };
        }

        function i2c_transaction copy();
            copy      = new();
            copy.addr = this.addr;
            copy.data = this.data;
            copy.rw   = this.rw;
        endfunction

        function string convert2string();
            return $sformatf("addr=0x%0h data=0x%0h rw=%0b", addr, data, rw);
        endfunction
    endclass

    // ---- Coverage ----
    // Manual bin tracking (no covergroup/xcrg) so it works on Vivado
    // Simulator BASIC tier - covergroup coverage is real, but reading it
    // back out via export_xsim_coverage/xcrg needs a PRO license.
    class i2c_coverage;
        bit hit[string];

        static string a_names[4] = '{"ZERO", "LOW", "HIGH", "MAX"};
        static string d_names[4] = '{"ZERO", "LOW", "HIGH", "MAX"};
        localparam int TOTAL_BINS = 16;   // 4 addr bins x 4 data bins

        function string classify_addr(bit [6:0] a);
            if (a == 7'h00)      return "ZERO";
            else if (a == 7'h7F) return "MAX";
            else if (a < 7'h40)  return "LOW";
            else                 return "HIGH";
        endfunction

        function string classify_data(bit [7:0] d);
            if (d == 8'h00)      return "ZERO";
            else if (d == 8'hFF) return "MAX";
            else if (d < 8'h80)  return "LOW";
            else                 return "HIGH";
        endfunction

        function void sample(i2c_transaction t);
            string key;
            key = {classify_addr(t.addr), "_", classify_data(t.data)};
            hit[key] = 1'b1;
        endfunction

        function real get_coverage();
            return (100.0 * hit.num()) / TOTAL_BINS;
        endfunction

        function void report();
            string key;
            $display("=== FUNCTIONAL COVERAGE (addr-bin x data-bin) ===");
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    key = {a_names[i], "_", d_names[j]};
                    $display("  addr=%-4s data=%-4s : %s",
                              a_names[i], d_names[j],
                              hit.exists(key) ? "HIT" : "miss");
                end
            end
            $display("=== TOTAL: %0d/%0d bins (%0.2f%%) ===",
                       hit.num(), TOTAL_BINS, get_coverage());
        endfunction
    endclass

    // ---- Generator ----
    class i2c_generator;
        mailbox #(i2c_transaction) gen2drv;
        int                        num_transactions = 20;

        // One representative value per addr-bin and per data-bin, matching
        // i2c_coverage's classify_addr()/classify_data() bucketing
        // (ZERO/LOW/HIGH/MAX). Driving all 16 combinations directly
        // guarantees 100% corner-case closure - relying on random dist
        // weighting alone to hit every corner x corner pair would need
        // on the order of a thousand+ transactions to be likely.
        static bit [6:0] addr_bin_vals[4] = '{7'h00, 7'h20, 7'h60, 7'h7F}; // ZERO,LOW,HIGH,MAX
        static bit [7:0] data_bin_vals[4] = '{8'h00, 8'h40, 8'hC0, 8'hFF}; // ZERO,LOW,HIGH,MAX

        function new(mailbox #(i2c_transaction) gen2drv);
            this.gen2drv = gen2drv;
        endfunction

        task run();
            i2c_transaction tr;

            // Directed phase: hit every addr-bin x data-bin corner combo.
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    tr      = new();
                    tr.addr = addr_bin_vals[i];
                    tr.data = data_bin_vals[j];
                    gen2drv.put(tr);
                end
            end

            // Random phase: constrained-random for everything else.
            repeat (num_transactions) begin
                tr = new();
                if (!tr.randomize())
                    $fatal(1, "[GENERATOR] Randomization failed");
                gen2drv.put(tr);
            end
        endtask
    endclass

    // ---- Driver ----
    class i2c_driver;
        virtual i2c_if              vif;
        mailbox #(i2c_transaction)  gen2drv;
        mailbox #(i2c_transaction)  drv2scb;
        i2c_coverage                cov;

        function new(virtual i2c_if              vif,
                     mailbox #(i2c_transaction)   gen2drv,
                     mailbox #(i2c_transaction)   drv2scb,
                     i2c_coverage                 cov);
            this.vif     = vif;
            this.gen2drv = gen2drv;
            this.drv2scb = drv2scb;
            this.cov     = cov;
        endfunction

        task run();
            i2c_transaction tr;

            vif.driver_cb.start   <= 1'b0;
            vif.driver_cb.addr    <= '0;
            vif.driver_cb.data_in <= '0;

            forever begin
                gen2drv.get(tr);
                cov.sample(tr);

                @(vif.driver_cb);
                vif.driver_cb.addr    <= tr.addr;
                vif.driver_cb.data_in <= tr.data;
                vif.driver_cb.start   <= 1'b1;

                @(vif.driver_cb);
                vif.driver_cb.start <= 1'b0;

                @(posedge vif.busy);
                @(posedge vif.done);

                drv2scb.put(tr);

                @(vif.driver_cb);
            end
        endtask
    endclass

    // ---- Monitor ----
    class i2c_monitor;
        virtual i2c_if             vif;
        mailbox #(i2c_transaction) mon2scb;

        function new(virtual i2c_if vif, mailbox #(i2c_transaction) mon2scb);
            this.vif     = vif;
            this.mon2scb = mon2scb;
        endfunction

        task run();
            i2c_transaction tr;
            bit [7:0] addr_rw;
            bit [7:0] data_byte;
            int       i;

            forever begin
                // START: SDA falls while SCL is high.
                @(negedge vif.sda iff (vif.scl == 1'b1));

                addr_rw = '0;
                for (i = 7; i >= 0; i--) begin
                    @(posedge vif.scl);
                    addr_rw[i] = vif.sda;
                end

                data_byte = '0;
                for (i = 7; i >= 0; i--) begin
                    @(posedge vif.scl);
                    data_byte[i] = vif.sda;
                end

                // STOP setup: SCL falls (end of last data bit) then rises
                // again unconditionally in STOP_COND - this toggle always
                // happens regardless of data value, so it's a reliable
                // anchor. SDA may already be sitting at '1' if the last
                // data bit driven was '1' (no fresh edge will ever occur
                // in that case), or may still need to rise. Handle both,
                // otherwise a posedge-only wait can miss STOP and desync
                // every transaction after it.
                @(negedge vif.scl);
                @(posedge vif.scl);
                if (vif.sda !== 1'b1)
                    @(posedge vif.sda);

                tr      = new();
                tr.addr = addr_rw[7:1];
                tr.rw   = addr_rw[0];
                tr.data = data_byte;
                mon2scb.put(tr);
            end
        endtask
    endclass

    // ---- Scoreboard ----
    class i2c_scoreboard;
        mailbox #(i2c_transaction) drv2scb;
        mailbox #(i2c_transaction) mon2scb;

        int pass_count = 0;
        int fail_count = 0;

        function new(mailbox #(i2c_transaction) drv2scb,
                     mailbox #(i2c_transaction) mon2scb);
            this.drv2scb = drv2scb;
            this.mon2scb = mon2scb;
        endfunction

        task run();
            i2c_transaction exp_tr, act_tr;
            forever begin
                drv2scb.get(exp_tr);
                mon2scb.get(act_tr);

                if (exp_tr.addr === act_tr.addr &&
                    exp_tr.data === act_tr.data &&
                    act_tr.rw   === 1'b0) begin
                    pass_count++;
                    $display("[SCOREBOARD] PASS  exp(%s)  got(%s)",
                              exp_tr.convert2string(), act_tr.convert2string());
                end else begin
                    fail_count++;
                    $error("[SCOREBOARD] FAIL  exp(%s)  got(%s)",
                            exp_tr.convert2string(), act_tr.convert2string());
                end
            end
        endtask

        function void report();
            $display("=== SCOREBOARD SUMMARY: PASS=%0d  FAIL=%0d  TOTAL=%0d ===",
                       pass_count, fail_count, pass_count + fail_count);
        endfunction
    endclass

    // ---- Environment ----
    class i2c_env;
        virtual i2c_if vif;
        int            num_transactions = 20;

        i2c_generator  gen;
        i2c_driver     drv;
        i2c_monitor    mon;
        i2c_scoreboard scb;
        i2c_coverage   cov;

        mailbox #(i2c_transaction) gen2drv;
        mailbox #(i2c_transaction) drv2scb;
        mailbox #(i2c_transaction) mon2scb;

        function new(virtual i2c_if vif);
            this.vif = vif;

            gen2drv = new();
            drv2scb = new();
            mon2scb = new();

            cov = new();
            gen = new(gen2drv);
            drv = new(vif, gen2drv, drv2scb, cov);
            mon = new(vif, mon2scb);
            scb = new(drv2scb, mon2scb);
        endfunction

        task run();
            int total_expected;

            gen.num_transactions = num_transactions;
            total_expected       = num_transactions + 16;   // +16 directed corner-case transactions

            fork
                gen.run();
                drv.run();
                mon.run();
                scb.run();
            join_none

            // Wait until the scoreboard has actually scored every
            // transaction (NOT join_any on gen.run() - that task returns
            // almost instantly since mailbox::put() doesn't block, long
            // before the driver/monitor/scoreboard have done real work).
            wait (scb.pass_count + scb.fail_count >= total_expected);

            // small settle time so the last scoreboard message finishes
            repeat (5) @(posedge vif.clk);

            scb.report();
            cov.report();
        endtask
    endclass

endpackage


// ==========================================================================
// 4. Top-level testbench
// ==========================================================================
import i2c_pkg::*;

module tb_top;

    bit clk;
    bit rst_n;

    always #5 clk = ~clk;   // 100 MHz testbench clock

    i2c_if vif (.clk(clk), .rst_n(rst_n));

    wire clk_div_tick;

    clk_div #(
        .DIVIDER (8)
    ) u_clk_div (
        .clk          (clk),
        .rst_n        (rst_n),
        .clk_div_tick (clk_div_tick)
    );

    i2c_master u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .clk_div_tick (clk_div_tick),
        .start        (vif.start),
        .addr         (vif.addr),
        .data_in      (vif.data_in),
        .scl          (vif.scl),
        .sda          (vif.sda),
        .busy         (vif.busy),
        .done         (vif.done)
    );

    bind i2c_master i2c_assertions u_i2c_assertions (
        .clk     (clk),
        .rst_n   (rst_n),
        .state   (state),
        .bit_idx (bit_idx),
        .scl     (scl),
        .sda     (sda),
        .busy    (busy),
        .done    (done)
    );

    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        i2c_env env;

        $display("=== I2C Master Testbench Starting ===");
        wait (rst_n === 1'b1);
        @(posedge clk);

        env = new(vif);
        env.num_transactions = 50;
        env.run();

        $display("=== I2C Master Testbench Complete ===");
        $finish;
    end

    initial begin
        #250000;
        $error("[TIMEOUT] Watchdog fired - simulation did not complete in time");
        $finish;
    end

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule