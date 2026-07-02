`timescale 1ns/1ps

// -----------------------------------------------------------------------
// Integrated testbench for nexuslite_top
//
// Drives the single external AXI-Lite slave interface (like a real
// CPU/master in an SoC would), and provides a small behavioral AXI-Lite
// SLAVE memory model on the DMA engine's master interface, since nothing
// in the design itself plays that role - in a real SoC this would be
// actual system memory or another peripheral.
//
// Test flow: configure DMA CSR registers through the top-level slave
// interface -> trigger START -> DMA engine reads from src, writes to
// dst inside the behavioral memory -> poll DMA_STATUS until DONE ->
// verify the memory model actually received the right data.
//
// Also exercises the regfile path through the same top-level interface,
// to confirm the address router correctly distinguishes the two.
// -----------------------------------------------------------------------

module tb_nexuslite_top;

    localparam ADDR_WIDTH = 8;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10;

    // Top-level (regfile/dma_csr) offsets
    localparam logic [ADDR_WIDTH-1:0] CTRL_OFFSET       = 8'h00;
    localparam logic [ADDR_WIDTH-1:0] CONFIG_OFFSET     = 8'h04;

    localparam logic [ADDR_WIDTH-1:0] SRC_ADDR_OFFSET   = 8'h20;
    localparam logic [ADDR_WIDTH-1:0] DST_ADDR_OFFSET   = 8'h24;
    localparam logic [ADDR_WIDTH-1:0] LENGTH_OFFSET     = 8'h28;
    localparam logic [ADDR_WIDTH-1:0] DMA_CTRL_OFFSET   = 8'h2C;
    localparam logic [ADDR_WIDTH-1:0] DMA_STATUS_OFFSET = 8'h30;

    logic                  ACLK;
    logic                  ARESETN;

    // External slave interface (driven by this testbench, acting as the master)
    logic [ADDR_WIDTH-1:0] AWADDR;
    logic                  AWVALID;
    logic                  AWREADY;
    logic [DATA_WIDTH-1:0] WDATA;
    logic                  WVALID;
    logic                  WREADY;
    logic [1:0]             BRESP;
    logic                  BVALID;
    logic                  BREADY;
    logic [ADDR_WIDTH-1:0] ARADDR;
    logic                  ARVALID;
    logic                  ARREADY;
    logic [DATA_WIDTH-1:0] RDATA;
    logic [1:0]             RRESP;
    logic                  RVALID;
    logic                  RREADY;

    // DMA engine's master interface (this testbench acts as the SLAVE/memory here)
    logic [ADDR_WIDTH-1:0] m_AWADDR;
    logic                  m_AWVALID;
    logic                  m_AWREADY;
    logic [DATA_WIDTH-1:0] m_WDATA;
    logic                  m_WVALID;
    logic                  m_WREADY;
    logic [1:0]             m_BRESP;
    logic                  m_BVALID;
    logic                  m_BREADY;
    logic [ADDR_WIDTH-1:0] m_ARADDR;
    logic                  m_ARVALID;
    logic                  m_ARREADY;
    logic [DATA_WIDTH-1:0] m_RDATA;
    logic [1:0]             m_RRESP;
    logic                  m_RVALID;
    logic                  m_RREADY;

    int pass_count = 0;
    int fail_count = 0;

    nexuslite_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .ACLK(ACLK), .ARESETN(ARESETN),
        .AWADDR(AWADDR), .AWVALID(AWVALID), .AWREADY(AWREADY),
        .WDATA(WDATA), .WVALID(WVALID), .WREADY(WREADY),
        .BRESP(BRESP), .BVALID(BVALID), .BREADY(BREADY),
        .ARADDR(ARADDR), .ARVALID(ARVALID), .ARREADY(ARREADY),
        .RDATA(RDATA), .RRESP(RRESP), .RVALID(RVALID), .RREADY(RREADY),
        .m_AWADDR(m_AWADDR), .m_AWVALID(m_AWVALID), .m_AWREADY(m_AWREADY),
        .m_WDATA(m_WDATA), .m_WVALID(m_WVALID), .m_WREADY(m_WREADY),
        .m_BRESP(m_BRESP), .m_BVALID(m_BVALID), .m_BREADY(m_BREADY),
        .m_ARADDR(m_ARADDR), .m_ARVALID(m_ARVALID), .m_ARREADY(m_ARREADY),
        .m_RDATA(m_RDATA), .m_RRESP(m_RRESP), .m_RVALID(m_RVALID), .m_RREADY(m_RREADY)
    );

    initial ACLK = 0;
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    initial begin
        $dumpfile("nexuslite_top.vcd");
        $dumpvars(0, tb_nexuslite_top);
        $monitor("t=%0t state=%0d aw_done=%b w_done=%b m_AWVALID=%b m_AWREADY=%b m_WVALID=%b m_WREADY=%b m_BVALID=%b words_rem=%0d",
          $time, dut.u_dma_engine.state, dut.u_dma_engine.aw_done, dut.u_dma_engine.w_done,
          dut.u_dma_engine.m_AWVALID, dut.u_dma_engine.m_AWREADY,
          dut.u_dma_engine.m_WVALID, dut.u_dma_engine.m_WREADY,
          dut.u_dma_engine.m_BVALID, dut.u_dma_engine.words_remaining);
    end

    // ---------------------------------------------------------------
    // Behavioral AXI-Lite SLAVE memory model, sitting on the DMA
    // engine's master interface. This is pure testbench infrastructure
    // - it is NOT synthesizable RTL, and in a real chip this role would
    // be played by actual memory or another real peripheral.
    // ---------------------------------------------------------------
    logic [DATA_WIDTH-1:0] behavioral_mem [0:255];

    // Write side of the memory model
    typedef enum logic [1:0] {MEM_W_IDLE, MEM_W_DATA, MEM_W_RESP} mem_w_state_t;
    mem_w_state_t mem_w_state;
    logic [ADDR_WIDTH-1:0] mem_w_addr_captured;

    always_ff @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            mem_w_state <= MEM_W_IDLE;
            m_AWREADY   <= 1'b0;
            m_WREADY    <= 1'b0;
            m_BVALID    <= 1'b0;
            m_BRESP     <= 2'b00;
        end else begin
            case (mem_w_state)
                MEM_W_IDLE: begin
                    m_AWREADY <= 1'b0;
                    m_WREADY  <= 1'b0;
                    m_BVALID  <= 1'b0;
                    if (m_AWVALID) begin
                        mem_w_addr_captured <= m_AWADDR;
                        m_AWREADY <= 1'b1;
                        mem_w_state <= MEM_W_DATA;
                    end
                end
                MEM_W_DATA: begin
                    m_AWREADY <= 1'b0;
                    if (m_WVALID) begin
                        behavioral_mem[mem_w_addr_captured] <= m_WDATA;
                        m_WREADY <= 1'b1;
                        m_BVALID <= 1'b1;
                        m_BRESP  <= 2'b00;
                        mem_w_state <= MEM_W_RESP;
                    end
                end
                MEM_W_RESP: begin
                    m_WREADY <= 1'b0;
                    if (m_BREADY) begin
                        m_BVALID <= 1'b0;
                        mem_w_state <= MEM_W_IDLE;
                    end
                end
            endcase
        end
    end

    // Read side of the memory model
    typedef enum logic [0:0] {MEM_R_IDLE, MEM_R_RESP} mem_r_state_t;
    mem_r_state_t mem_r_state;

    always_ff @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN) begin
            mem_r_state <= MEM_R_IDLE;
            m_ARREADY   <= 1'b0;
            m_RVALID    <= 1'b0;
            m_RRESP     <= 2'b00;
            m_RDATA     <= '0;
        end else begin
            case (mem_r_state)
                MEM_R_IDLE: begin
                    m_ARREADY <= 1'b0;
                    m_RVALID  <= 1'b0;
                    if (m_ARVALID) begin
                        m_ARREADY <= 1'b1;
                        m_RDATA   <= behavioral_mem[m_ARADDR];
                        m_RVALID  <= 1'b1;
                        m_RRESP   <= 2'b00;
                        mem_r_state <= MEM_R_RESP;
                    end
                end
                MEM_R_RESP: begin
                    if (m_RREADY) begin
                        m_RVALID <= 1'b0;
                        mem_r_state <= MEM_R_IDLE;
                    end
                end
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Low-level driver tasks for the EXTERNAL slave interface
    // (same pattern as previous testbenches)
    // ---------------------------------------------------------------
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

    // Poll DMA_STATUS until DONE (bit1) is set, or give up after a timeout
    task automatic wait_for_dma_done(output logic timed_out);
        logic [DATA_WIDTH-1:0] status;
        logic [1:0] resp;
        int timeout_cycles;
        begin
            timed_out = 1'b0;
            timeout_cycles = 0;
            do begin
                do_read(DMA_STATUS_OFFSET, status, resp);
                timeout_cycles++;
                if (timeout_cycles > 200) begin
                    timed_out = 1'b1;
                end
            end while (!status[1] && !timed_out);
        end
    endtask

    // ---------------------------------------------------------------
    // High-level tests
    // ---------------------------------------------------------------

    // Confirm the router correctly reaches the regfile through the
    // top-level interface (offsets below 0x20)
    task automatic test_regfile_reachable();
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata;
        begin
            do_write(CTRL_OFFSET, 32'hABCD_1234, wresp);
            do_read(CTRL_OFFSET, rdata, rresp);
            if (wresp !== 2'b00 || rresp !== 2'b00 || rdata !== 32'hABCD_1234) begin
                $display("[FAIL] test_regfile_reachable: wrote ABCD1234, read %0h, wresp=%0d rresp=%0d",
                          rdata, wresp, rresp);
                fail_count++;
            end else begin
                $display("[PASS] test_regfile_reachable: router correctly reaches regfile");
                pass_count++;
            end
        end
    endtask

    // Confirm the router correctly reaches the DMA CSR block (offsets 0x20+)
    task automatic test_dma_csr_reachable();
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata;
        begin
            do_write(LENGTH_OFFSET, 32'd4, wresp);
            do_read(LENGTH_OFFSET, rdata, rresp);
            if (wresp !== 2'b00 || rresp !== 2'b00 || rdata !== 32'd4) begin
                $display("[FAIL] test_dma_csr_reachable: wrote 4, read %0h, wresp=%0d rresp=%0d",
                          rdata, wresp, rresp);
                fail_count++;
            end else begin
                $display("[PASS] test_dma_csr_reachable: router correctly reaches dma_csr");
                pass_count++;
            end
        end
    endtask

    // The main event: configure a full DMA transfer and verify the data
    // actually moved inside the behavioral memory model
    task automatic test_full_dma_transfer();
        logic [1:0] wresp, rresp;
        logic [DATA_WIDTH-1:0] rdata;
        logic timed_out;
        int i;
        localparam int XFER_LEN = 4;
        localparam logic [ADDR_WIDTH-1:0] SRC_BASE = 8'h40;
        localparam logic [ADDR_WIDTH-1:0] DST_BASE = 8'h60;
        begin
            // Pre-load source memory with known, distinct values
            for (i = 0; i < XFER_LEN; i++) begin
                behavioral_mem[SRC_BASE + i] = 32'hCAFE_0000 + i;
            end
            // Clear destination memory so we can tell a real transfer happened
            for (i = 0; i < XFER_LEN; i++) begin
                behavioral_mem[DST_BASE + i] = 32'h0;
            end

            do_write(SRC_ADDR_OFFSET, SRC_BASE, wresp);
            do_write(DST_ADDR_OFFSET, DST_BASE, wresp);
            do_write(LENGTH_OFFSET,   XFER_LEN, wresp);
            do_write(DMA_CTRL_OFFSET, 32'h1,     wresp);   // bit0 = START

            wait_for_dma_done(timed_out);
            if (timed_out) begin
                $display("[FAIL] test_full_dma_transfer: timed out waiting for DMA_STATUS.DONE");
                fail_count++;
            end else begin
                $display("[PASS] test_full_dma_transfer: DMA_STATUS reported DONE");
                pass_count++;
            end

            // Confirm data actually landed correctly in the destination region
            for (i = 0; i < XFER_LEN; i++) begin
                if (behavioral_mem[DST_BASE + i] !== (32'hCAFE_0000 + i)) begin
                    $display("[FAIL] test_full_dma_transfer: word %0d mismatch, expected %0h got %0h",
                              i, 32'hCAFE_0000 + i, behavioral_mem[DST_BASE + i]);
                    fail_count++;
                end else begin
                    $display("[PASS] test_full_dma_transfer: word %0d correctly copied (%0h)",
                              i, behavioral_mem[DST_BASE + i]);
                    pass_count++;
                end
            end

            // Confirm DMA_STATUS.BUSY has cleared after completion
            do_read(DMA_STATUS_OFFSET, rdata, rresp);
            if (rdata[0] !== 1'b0) begin
                $display("[FAIL] test_full_dma_transfer: DMA_STATUS.BUSY still set after DONE");
                fail_count++;
            end else begin
                $display("[PASS] test_full_dma_transfer: DMA_STATUS.BUSY correctly cleared");
                pass_count++;
            end
        end
    endtask

    // ---------------------------------------------------------------
    // Main sequence
    // ---------------------------------------------------------------
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

        test_regfile_reachable();
        test_dma_csr_reachable();
        test_full_dma_transfer();

        #(CLK_PERIOD*10);
        $display("=== Testbench complete: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        $finish;
    end

endmodule