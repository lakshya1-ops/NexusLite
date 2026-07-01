`timescale 1ns/1ps

module tb_nexuslite_min;

    localparam ADDR_WIDTH = 4;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    logic                    ACLK;
    logic                    ARESETN;
    logic [ADDR_WIDTH-1:0]   AWADDR;
    logic                    AWVALID;
    logic                    AWREADY;
    logic [DATA_WIDTH-1:0]   WDATA;
    logic                    WVALID;
    logic                    WREADY;
    logic [1:0]              BRESP;
    logic                    BVALID;
    logic                    BREADY;
    logic [ADDR_WIDTH-1:0]   ARADDR;
    logic                    ARVALID;
    logic                    ARREADY;
    logic [DATA_WIDTH-1:0]   RDATA;
    logic [1:0]              RRESP;
    logic                    RVALID;
    logic                    RREADY;

    int pass_count = 0;
    int fail_count = 0;

    nexuslite_min #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .ACLK    (ACLK),
        .ARESETN (ARESETN),
        .AWADDR  (AWADDR),
        .AWVALID (AWVALID),
        .AWREADY (AWREADY),
        .WDATA   (WDATA),
        .WVALID  (WVALID),
        .WREADY  (WREADY),
        .BRESP   (BRESP),
        .BVALID  (BVALID),
        .BREADY  (BREADY),
        .ARADDR  (ARADDR),
        .ARVALID (ARVALID),
        .ARREADY (ARREADY),
        .RDATA   (RDATA),
        .RRESP   (RRESP),
        .RVALID  (RVALID),
        .RREADY  (RREADY)
    );

    initial ACLK = 0;
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    initial begin
        $dumpfile("nexuslite_min.vcd");
        $dumpvars(0, tb_nexuslite_min);
    end

    // Same-cycle write: AWVALID and WVALID asserted together
    task automatic write_same_cycle(input [ADDR_WIDTH-1:0] addr,
                                     input [DATA_WIDTH-1:0] data);
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
            if (BRESP !== 2'b00) begin
                $display("[FAIL] write_same_cycle: addr=%0h expected BRESP=OKAY got %0d", addr, BRESP);
                fail_count++;
            end else begin
                $display("[PASS] write_same_cycle: addr=%0h data=%0h", addr, data);
                pass_count++;
            end

            BREADY <= 1'b0;
            @(posedge ACLK);
        end
    endtask

    // Split-cycle write: AWVALID arrives, then WVALID arrives a few cycles later
    task automatic write_split_cycle(input [ADDR_WIDTH-1:0] addr,
                                      input [DATA_WIDTH-1:0] data);
        begin
            // Phase 1: send address only
            @(posedge ACLK);
            AWADDR  <= addr;
            AWVALID <= 1'b1;
            WVALID  <= 1'b0;
            BREADY  <= 1'b1;

            @(posedge ACLK);
            AWVALID <= 1'b0;  // AWREADY should have been seen high on this edge

            // idle gap - address is sitting captured, data hasn't arrived yet
            @(posedge ACLK);
            @(posedge ACLK);

            // Phase 2: now send data
            WDATA  <= data;
            WVALID <= 1'b1;

            @(posedge ACLK);
            WVALID <= 1'b0; // WREADY should have been seen high on this edge

            wait (BVALID == 1'b1);
            @(posedge ACLK);
            if (BRESP !== 2'b00) begin
                $display("[FAIL] write_split_cycle: addr=%0h expected BRESP=OKAY got %0d", addr, BRESP);
                fail_count++;
            end else begin
                $display("[PASS] write_split_cycle: addr=%0h data=%0h", addr, data);
                pass_count++;
            end

            BREADY <= 1'b0;
            @(posedge ACLK);
        end
    endtask

    // Read and check against expected data
    task automatic read_check(input [ADDR_WIDTH-1:0] addr,
                               input [DATA_WIDTH-1:0] expected_data);
        begin
            @(posedge ACLK);
            ARADDR  <= addr;
            ARVALID <= 1'b1;
            RREADY  <= 1'b1;

            @(posedge ACLK);
            ARVALID <= 1'b0;

            wait (RVALID == 1'b1);
            @(posedge ACLK);
            if (RDATA !== expected_data) begin
                $display("[FAIL] read_check: addr=%0h expected=%0h got=%0h", addr, expected_data, RDATA);
                fail_count++;
            end else if (RRESP !== 2'b00) begin
                $display("[FAIL] read_check: addr=%0h expected RRESP=OKAY got %0d", addr, RRESP);
                fail_count++;
            end else begin
                $display("[PASS] read_check: addr=%0h data=%0h", addr, RDATA);
                pass_count++;
            end

            RREADY <= 1'b0;
            @(posedge ACLK);
        end
    endtask

    initial begin
        ARESETN = 0;
        AWADDR  = 0; AWVALID = 0;
        WDATA   = 0; WVALID  = 0;
        BREADY  = 0;
        ARADDR  = 0; ARVALID = 0;
        RREADY  = 0;

        repeat (3) @(posedge ACLK);
        ARESETN = 1;
        @(posedge ACLK);

        write_same_cycle(4'h0, 32'hDEADBEEF);
        read_check(4'h0, 32'hDEADBEEF);

        write_split_cycle(4'h0, 32'hCAFEF00D);
        read_check(4'h0, 32'hCAFEF00D);

        #(CLK_PERIOD*5);
        $display("=== Testbench complete: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end

endmodule