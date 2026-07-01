`timescale 1ns/1ps

module tb_nexuslite_regfile;

    localparam ADDR_WIDTH = 8;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    localparam logic [ADDR_WIDTH-1:0] CTRL_OFFSET     = 8'h00;
    localparam logic [ADDR_WIDTH-1:0] CONFIG_OFFSET   = 8'h04;
    localparam logic [ADDR_WIDTH-1:0] STATUS_OFFSET   = 8'h08;
    localparam logic [ADDR_WIDTH-1:0] INT_FLAG_OFFSET = 8'h0C;
    localparam logic [ADDR_WIDTH-1:0] DATA_IN_OFFSET  = 8'h10;
    localparam logic [ADDR_WIDTH-1:0] DATA_OUT_OFFSET = 8'h14;
    localparam logic [ADDR_WIDTH-1:0] INVALID_OFFSET  = 8'hFF;

    logic ACLK;
    logic                  ARESETN;
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic AWVALID;
    logic                  AWREADY;
    logic [DATA_WIDTH-1:0] WDATA;
    logic                  WVALID;
    logic                  WREADY;
    logic [1:0]            BRESP;
    logic                  BVALID;
    logic                  BREADY;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic                  ARVALID;
    logic                  ARREADY;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]            RRESP;
    logic                  RVALID;
    logic                  RREADY;

    int pass_count = 0;
    int fail_count = 0;

    nexuslite_regfile #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY)
    );

    initial ACLK = 0;
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    initial begin
        $dumpfile("nexuslite_regfile.vcd");
        $dumpvars(0, tb_nexuslite_regfile);
    end

    // ---- low-level driver tasks (same pattern as Stage 1) ----

    task automatic do_write(input [ADDR_WIDTH-1:0] addr,
                             input [DATA_WIDTH-1:0] data,
                             output [1:0] resp);
        begin
            @(posedge ACLK);
            AWADDR  <= addr;
            AWVALID <= 1'b1;
            WDATA   <= data;
            WVALID  <= 1'b1;
            BREADY  <= 1'b1;

            @(posedge ACLK);
            AWVALID <= 1'b0;
            WVALID  <= 1'b0;

            wait (BVALID == 1'b1);
            @(posedge ACLK);
            resp = BRESP;

            BREADY <= 1'b0;
            @(posedge ACLK);
        end
    endtask

    task automatic do_read(input [ADDR_WIDTH-1:0] addr,
                            output [DATA_WIDTH-1:0] data,
                            output [1:0] resp);
        begin
            @(posedge ACLK);
            ARADDR  <= addr;
            ARVALID <= 1'b1;
            RREADY  <= 1'b1;

            @(posedge ACLK);
            ARVALID <= 1'b0;

            wait (RVALID == 1'b1);
            @(posedge ACLK);
            data = RDATA;
            resp = RRESP;

            RREADY <= 1'b0;
            @(posedge ACLK);
        end
    endtask

    // ---- high-level test tasks ----

    task automatic test_rw_register(input [ADDR_WIDTH-1:0] addr,
                                     input [DATA_WIDTH-1:0] data,
                                     input string name);
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata;
        begin
            do_write(addr, data, wresp);
            do_read(addr, rdata, rresp);
            if (wresp !== 2'b00 || rresp !== 2'b00 || rdata !== data) begin
                $display("[FAIL] test_rw_register(%s): wrote %0h, read %0h, wresp=%0d rresp=%0d",
                          name, data, rdata, wresp, rresp);
                fail_count++;
            end else begin
                $display("[PASS] test_rw_register(%s): %0h round-tripped correctly", name, data);
                pass_count++;
            end
        end
    endtask

    task automatic test_status_changes();
        logic [DATA_WIDTH-1:0] status1, status2;
        logic [1:0] resp;
        begin
            do_read(STATUS_OFFSET, status1, resp);
            repeat (5) @(posedge ACLK);
            do_read(STATUS_OFFSET, status2, resp);
            if (status2 <= status1) begin
                $display("[FAIL] test_status_changes: status1=%0d status2=%0d (expected increase)", status1, status2);
                fail_count++;
            end else begin
                $display("[PASS] test_status_changes: status went %0d -> %0d", status1, status2);
                pass_count++;
            end
        end
    endtask

    task automatic test_int_flag_w1c();
        logic [DATA_WIDTH-1:0] rdata;
        logic [1:0] resp, wresp;
        begin
            // Part A: bit should currently be 0, writing 1 should have no visible effect
            do_read(INT_FLAG_OFFSET, rdata, resp);
            if (rdata[0] !== 1'b0) begin
                $display("[FAIL] test_int_flag_w1c Part A: expected bit0=0 before wrap, got %0d", rdata[0]);
                fail_count++;
            end
            do_write(INT_FLAG_OFFSET, 32'h1, wresp);
            do_read(INT_FLAG_OFFSET, rdata, resp);
            if (rdata[0] !== 1'b0) begin
                $display("[FAIL] test_int_flag_w1c Part A: clearing an already-0 bit changed it to %0d", rdata[0]);
                fail_count++;
            end else begin
                $display("[PASS] test_int_flag_w1c Part A: clear-on-zero is a no-op, as expected");
                pass_count++;
            end

            // Part B: force the counter to just-below-max using a hierarchical
            // deposit, so the wrap happens within a few real cycles instead of
            // waiting 2^32 cycles. This is a TESTBENCH-ONLY technique - it's not
            // synthesizable RTL, it directly pokes internal DUT state, and it's
            // only valid because Icarus allows hierarchical references from the
            // testbench into the DUT's internal signals for exactly this purpose.
            force dut.status_counter = {DATA_WIDTH{1'b1}} - 2;
            @(posedge ACLK);
            release dut.status_counter;

            // give it a couple cycles to actually wrap and for int_flag_reg to update
            repeat (3) @(posedge ACLK);

            do_read(INT_FLAG_OFFSET, rdata, resp);
            if (rdata[0] !== 1'b1) begin
                $display("[FAIL] test_int_flag_w1c Part B: expected bit0=1 after wrap, got %0d", rdata[0]);
                fail_count++;
            end else begin
                $display("[PASS] test_int_flag_w1c Part B: bit0 set after counter wrap");
                pass_count++;
            end

            // now confirm write-1-to-clear actually clears it
            do_write(INT_FLAG_OFFSET, 32'h1, wresp);
            do_read(INT_FLAG_OFFSET, rdata, resp);
            if (rdata[0] !== 1'b0) begin
                $display("[FAIL] test_int_flag_w1c Part B: bit0 did not clear after write-1");
                fail_count++;
            end else begin
                $display("[PASS] test_int_flag_w1c Part B: bit0 cleared correctly via write-1");
                pass_count++;
            end
        end
    endtask

    task automatic test_data_in_out();
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata_in, rdata_out;
        logic [DATA_WIDTH-1:0] test_val;
        begin
            test_val = 32'h0000_0055;
            do_write(DATA_IN_OFFSET, test_val, wresp);
            do_read(DATA_IN_OFFSET, rdata_in, rresp);
            do_read(DATA_OUT_OFFSET, rdata_out, rresp);

            if (rdata_in !== 32'h0) begin
                $display("[FAIL] test_data_in_out: DATA_IN read returned %0h, expected 0 (WO)", rdata_in);
                fail_count++;
            end else if (rdata_out !== (test_val + 1)) begin
                $display("[FAIL] test_data_in_out: DATA_OUT returned %0h, expected %0h", rdata_out, test_val + 1);
                fail_count++;
            end else begin
                $display("[PASS] test_data_in_out: DATA_IN reads 0, DATA_OUT = DATA_IN+1 correctly");
                pass_count++;
            end
        end
    endtask

    task automatic test_slverr();
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata;
        begin
            do_write(INVALID_OFFSET, 32'hABCD_1234, wresp);
            do_read(INVALID_OFFSET, rdata, rresp);

            if (wresp !== 2'b10) begin
                $display("[FAIL] test_slverr: write BRESP=%0d, expected SLVERR", wresp);
                fail_count++;
            end else if (rresp !== 2'b10 || rdata !== 32'h0) begin
                $display("[FAIL] test_slverr: read RRESP=%0d RDATA=%0h, expected SLVERR/0", rresp, rdata);
                fail_count++;
            end else begin
                $display("[PASS] test_slverr: invalid address correctly rejected on write and read");
                pass_count++;
            end
        end
    endtask

    // ---- main sequence ----
    initial begin
        ARESETN = 0;
        AWADDR = 0; AWVALID = 0;
        WDATA  = 0; WVALID  = 0;
        BREADY = 0;
        ARADDR = 0; ARVALID = 0;
        RREADY = 0;

        repeat (3) @(posedge ACLK);
        ARESETN = 1;
        @(posedge ACLK);

        test_rw_register(CTRL_OFFSET,   32'hAAAA_5555, "CTRL");
        test_rw_register(CONFIG_OFFSET, 32'h1234_5678, "CONFIG");
        test_status_changes();
        test_data_in_out();
        test_slverr();
        test_int_flag_w1c();   // last, since it forces internal state

        #(CLK_PERIOD*10);
        $display("=== Testbench complete: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end

endmodule