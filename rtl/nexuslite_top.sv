module nexuslite_top #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
)(
   input  logic ACLK,
    input  logic ARESETN,

    input  logic [ADDR_WIDTH-1:0] AWADDR,
    input  logic AWVALID,
    output logic AWREADY,

    input  logic [DATA_WIDTH-1:0] WDATA,
    input  logic WVALID,
    output logic WREADY,

    output logic [1:0] BRESP,
    output logic BVALID,
    input  logic BREADY,

    input  logic [ADDR_WIDTH-1:0] ARADDR,
    input  logic ARVALID,
    output logic ARREADY,

    output logic [DATA_WIDTH-1:0] RDATA,
    output logic [1:0] RRESP,
    output logic RVALID,
    input  logic RREADY,

    output logic [ADDR_WIDTH-1:0] m_AWADDR,
    output logic m_AWVALID,
    input  logic m_AWREADY,

    output logic [DATA_WIDTH-1:0] m_WDATA,
    output logic m_WVALID,
    input  logic m_WREADY,

    input  logic [1:0] m_BRESP,
    input  logic m_BVALID,
    output logic m_BREADY,

    output logic [ADDR_WIDTH-1:0] m_ARADDR,
    output logic m_ARVALID,
    input  logic m_ARREADY,

    input  logic [DATA_WIDTH-1:0] m_RDATA,
    input  logic [1:0] m_RRESP,
    input  logic m_RVALID,
    output logic m_RREADY
);
 // Address Decode
logic write_sel;
logic read_sel;

assign write_sel = AWADDR[5];
assign read_sel  = ARADDR[5];

// Latched destination for B and R channel routing
logic write_sel_q;
logic read_sel_q;


logic [ADDR_WIDTH-1:0] reg_awaddr;
logic reg_awvalid;
logic reg_awready;

 logic [DATA_WIDTH-1:0] reg_wdata;
 logic reg_wvalid;
 logic reg_wready;

 logic [1:0] reg_bresp;
 logic reg_bvalid;
 logic reg_bready;

 logic [ADDR_WIDTH-1:0] reg_araddr;
 logic reg_arvalid;
 logic reg_arready;

 logic [DATA_WIDTH-1:0] reg_rdata;
 logic [1:0] reg_rresp;
 logic reg_rvalid;
 logic reg_rready;


 logic [ADDR_WIDTH-1:0] csr_awaddr;
 logic csr_awvalid;
 logic csr_awready;

 logic [DATA_WIDTH-1:0] csr_wdata;
 logic csr_wvalid;
 logic csr_wready;

 logic [1:0] csr_bresp;
 logic csr_bvalid;
 logic csr_bready;

 logic [ADDR_WIDTH-1:0] csr_araddr;
 logic csr_arvalid;
 logic csr_arready;

 logic [DATA_WIDTH-1:0] csr_rdata;
 logic [1:0] csr_rresp;
 logic csr_rvalid;
 logic csr_rready;

// DMA CSR <-> DMA Engine Interface

 logic [DATA_WIDTH-1:0] dma_src_addr;
 logic [DATA_WIDTH-1:0] dma_dst_addr;
 logic [DATA_WIDTH-1:0] dma_length;

 logic dma_start;
 logic dma_start_ack;
 logic dma_busy;
 logic dma_done;
 logic dma_error;

 // Internal Router Control

 logic aw_handshake;
 logic ar_handshake;

 assign aw_handshake = AWVALID & AWREADY;
 assign ar_handshake = ARVALID & ARREADY;

// Destination Tracking
 always_ff @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            write_sel_q <= 1'b0;
        else if (aw_handshake)
            write_sel_q <= write_sel;
    end

    always_ff @(posedge ACLK or negedge ARESETN) begin
        if (!ARESETN)
            read_sel_q <= 1'b0;
        else if (ar_handshake)
            read_sel_q <= read_sel;
    end

   // Register File Instance

    nexuslite_regfile #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_regfile (

        .ACLK (ACLK),
        .ARESETN (ARESETN),

        // AXI-Lite Slave Interface
        .AWADDR (reg_awaddr),
        .AWVALID (reg_awvalid),
        .AWREADY (reg_awready),

        .WDATA (reg_wdata),
        .WVALID (reg_wvalid),
        .WREADY (reg_wready),

        .BRESP (reg_bresp),
        .BVALID (reg_bvalid),
        .BREADY (reg_bready),

        .ARADDR (reg_araddr),
        .ARVALID (reg_arvalid),
        .ARREADY (reg_arready),

        .RDATA (reg_rdata),
        .RRESP (reg_rresp),
        .RVALID (reg_rvalid),
        .RREADY (reg_rready)
    );


     // DMA CSR Instance

    nexuslite_dma_csr #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_dma_csr (

        .ACLK (ACLK),
        .ARESETN (ARESETN),
        .AWADDR (csr_awaddr),
        .AWVALID (csr_awvalid),
        .AWREADY (csr_awready),

        .WDATA (csr_wdata),
        .WVALID (csr_wvalid),
        .WREADY (csr_wready),

        .BRESP (csr_bresp),
        .BVALID (csr_bvalid),
        .BREADY (csr_bready),

        .ARADDR (csr_araddr),
        .ARVALID (csr_arvalid),
        .ARREADY (csr_arready),

        .RDATA (csr_rdata),
        .RRESP (csr_rresp),
        .RVALID (csr_rvalid),
        .RREADY (csr_rready),

        .dma_src_addr  (dma_src_addr),
        .dma_dst_addr  (dma_dst_addr),
        .dma_length    (dma_length),

        .dma_start     (dma_start),
        .dma_start_ack (dma_start_ack),
        .dma_busy      (dma_busy),
        .dma_done      (dma_done),
        .dma_error     (dma_error)
    );

    nexuslite_dma_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_dma_engine (

        .ACLK (ACLK),
        .ARESETN (ARESETN),

        .dma_src_addr  (dma_src_addr),
        .dma_dst_addr  (dma_dst_addr),
        .dma_length    (dma_length),

        .dma_start     (dma_start),
        .dma_start_ack (dma_start_ack),
        .dma_busy      (dma_busy),
        .dma_done      (dma_done),
        .dma_error     (dma_error),

        .m_AWADDR (m_AWADDR),
        .m_AWVALID (m_AWVALID),
        .m_AWREADY (m_AWREADY),

        .m_WDATA (m_WDATA),
        .m_WVALID (m_WVALID),
        .m_WREADY (m_WREADY),

        .m_BRESP (m_BRESP),
        .m_BVALID (m_BVALID),
        .m_BREADY (m_BREADY),

        .m_ARADDR (m_ARADDR),
        .m_ARVALID (m_ARVALID),
        .m_ARREADY (m_ARREADY),

        .m_RDATA (m_RDATA),
        .m_RRESP (m_RRESP),
        .m_RVALID (m_RVALID),
        .m_RREADY (m_RREADY)
    );
    // Write Address Routing (AW Channel)

   // Route AWADDR

 assign reg_awaddr = AWADDR;
 assign csr_awaddr = AWADDR;

 // Route AWVALID

 assign reg_awvalid = AWVALID & (~write_sel);
 assign csr_awvalid = AWVALID & ( write_sel);

 // Return AWREADY

 assign AWREADY = (write_sel) ? csr_awready
                                 : reg_awready;

// Write Data Routing (W Channel)

 assign reg_wdata = WDATA;
 assign csr_wdata = WDATA;

 assign reg_wvalid = WVALID & (~write_sel);
 assign csr_wvalid = WVALID & ( write_sel);

 assign WREADY = (write_sel) ? csr_wready
                                : reg_wready;


    // Write Response Routing (B Channel)
    // Response channel must use the LATCHED destination,
    // not the live address decode.

 assign reg_bready = (~write_sel_q) ? BREADY : 1'b0;
 assign csr_bready = ( write_sel_q) ? BREADY : 1'b0;

 always_comb begin

        BVALID = 1'b0;
        BRESP  = 2'b00;

        if (write_sel_q) begin

            BVALID = csr_bvalid;
            BRESP  = csr_bresp;

        end
        else begin

            BVALID = reg_bvalid;
            BRESP  = reg_bresp;

        end

    end



 // Read Address Routing (AR Channel)

 // Route ARADDR

 assign reg_araddr = ARADDR;
 assign csr_araddr = ARADDR;

 // Route ARVALID

 assign reg_arvalid = ARVALID & (~read_sel);
 assign csr_arvalid = ARVALID & ( read_sel);


 // Return ARREADY

 assign ARREADY = (read_sel) ? csr_arready
                                : reg_arready;


 // Read Data Routing (R Channel)
 // RREADY must only be asserted to the selected slave

 assign reg_rready = (~read_sel_q) ? RREADY : 1'b0;
 assign csr_rready = ( read_sel_q) ? RREADY : 1'b0;


 // Route response back to external master
 always_comb begin

        RVALID = 1'b0;
        RDATA  = '0;
        RRESP  = 2'b00;

        if (read_sel_q) begin

            RVALID = csr_rvalid;
            RDATA  = csr_rdata;
            RRESP  = csr_rresp;

        end
        else begin

            RVALID = reg_rvalid;
            RDATA  = reg_rdata;
            RRESP  = reg_rresp;

        end

    end
endmodule