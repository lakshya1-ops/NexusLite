module nexuslite_dma_csr #(
     parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
)
(
input logic ACLK,
input logic ARESETN,

//write addr channel
input  logic [ADDR_WIDTH-1:0] AWADDR,
input  logic AWVALID,
output logic AWREADY,

// Write data channel
input  logic [DATA_WIDTH-1:0] WDATA, 
input  logic WVALID,
output logic WREADY,

// Write response channel
output logic [1:0] BRESP ,
output logic BVALID,
input  logic BREADY,

// Read address channel
input  logic [ADDR_WIDTH-1:0] ARADDR,
input  logic ARVALID,
output logic ARREADY,

// Read data channel
output logic [DATA_WIDTH-1:0]  RDATA,
output logic [1:0] RRESP,
output logic RVALID,
input  logic RREADY,


// To the DMA engine
output logic [DATA_WIDTH-1:0] dma_src_addr,
output logic [DATA_WIDTH-1:0] dma_dst_addr,
output logic [DATA_WIDTH-1:0] dma_length,
output logic dma_start,      // pulses high for one cycle when START is written
input  logic dma_start_ack,  // DMA engine pulses this back once it has captured the start command - this is what clears DMA_CTRL bit0

// From the DMA engine
input  logic dma_busy,
input  logic dma_done,
input  logic dma_error
);

import nexuslite_pkg::*;

localparam logic [ADDR_WIDTH-1:0] SRC_ADDR_OFFSET    = 8'h00;
localparam logic [ADDR_WIDTH-1:0] DST_ADDR_OFFSET   = 8'h04;
localparam logic [ADDR_WIDTH-1:0] LENGTH_OFFSET   = 8'h08;
localparam logic [ADDR_WIDTH-1:0] DMA_CTRL_OFFSET = 8'h0C;
localparam logic [ADDR_WIDTH-1:0] DMA_STATUS_OFFSET  = 8'h10;

//storage
logic [DATA_WIDTH-1:0] src_addr_reg;
logic [DATA_WIDTH-1:0] dst_addr_reg;
logic [DATA_WIDTH-1:0] length_reg;

logic [DATA_WIDTH-1:0] write_data_current;

// tracks whether a start command has been written but not yet acked by the DMA engine
// (readable back via DMA_CTRL bit0)
logic dma_start_pending;

assign dma_src_addr = src_addr_reg;
assign dma_dst_addr = dst_addr_reg;
assign dma_length   = length_reg;

//write fsm
typedef enum logic [0:0] { WR_IDLE, WR_RESP } wr_state_t;
wr_state_t wr_state;

logic [ADDR_WIDTH-1:0] aw_addr_captured; //save address
logic [DATA_WIDTH-1:0] w_data_captured; //saves data to be written
logic aw_captured, w_captured; //1bit flags

always_ff @(posedge ACLK or negedge ARESETN)
begin
        if (!ARESETN)
         begin
            wr_state <= WR_IDLE;
            AWREADY <= 1'b0;
            WREADY <= 1'b0;
            BVALID <= 1'b0;
            BRESP <= AXI_RESP_OKAY;
            aw_captured <= 1'b0;
            w_captured <= 1'b0;
            aw_addr_captured <= '0;
            w_data_captured <= '0;
            src_addr_reg <= '0;
            dst_addr_reg <= '0;
            length_reg   <= '0;
            dma_start <= 1'b0;
            dma_start_pending <= 1'b0;
        end

        else
        begin
        // dma_start is a one-cycle pulse: default low every cycle unless
        // explicitly asserted below in the DMA_CTRL write branch
        dma_start <= 1'b0;

        // clear the pending flag once the DMA engine acks the start command
        if (dma_start_ack)
            dma_start_pending <= 1'b0;

        case (wr_state)

            WR_IDLE:
            begin
                // Default: not asserting anything unless conditions below say so
                AWREADY <= 1'b0;
                WREADY  <= 1'b0;
                BVALID  <= 1'b0;

                // Latch address the cycle AWVALID is seen (if not already captured)
                if (AWVALID && !aw_captured) 
                begin
                    aw_addr_captured <= AWADDR;
                    aw_captured      <= 1'b1;
                    AWREADY          <= 1'b1;   // acknowledge we took the address
                end

                // Latch data the cycle WVALID is seen (if not already captured)
                if (WVALID && !w_captured) 
                begin
                    w_data_captured <= WDATA;
                    w_captured <= 1'b1;
                    WREADY <= 1'b1;    // acknowledge we took the data
                end

                // Once we have BOTH (either just captured this cycle, or already captured earlier)
                if ((AWVALID || aw_captured) && (WVALID || w_captured)) 
               begin
               write_data_current = (WVALID && !w_captured) ? WDATA : w_data_captured;
                   case((AWVALID && !aw_captured) ? AWADDR : aw_addr_captured)
                   
                    SRC_ADDR_OFFSET:
                        begin
                        src_addr_reg <= write_data_current;
                        BRESP<= AXI_RESP_OKAY;
                         end
                    DST_ADDR_OFFSET:
                        begin
                        dst_addr_reg <= write_data_current;
                        BRESP <= AXI_RESP_OKAY;
                        end
                    LENGTH_OFFSET:
                        begin
                        length_reg <= write_data_current; 
                        BRESP<= AXI_RESP_OKAY;
                        end
                    DMA_CTRL_OFFSET:
                        begin
                            if (write_data_current[0])
                            
                            begin
                                dma_start         <= 1'b1;
                                dma_start_pending <= 1'b1;
                            end
                            BRESP <= AXI_RESP_OKAY;
                        end

                    DMA_STATUS_OFFSET: BRESP <= AXI_RESP_OKAY;
        
                    default: BRESP <= AXI_RESP_SLVERR;

                    endcase
                    wr_state    <= WR_RESP;
                    BVALID      <= 1'b1;
                    aw_captured <= 1'b0;   // clear for next transaction
                    w_captured  <= 1'b0;
                end
            end
                
            WR_RESP:
            begin
                if(BREADY)
                begin
                    BVALID<=1'b0;
                    wr_state<=WR_IDLE;
                end
            end
        endcase
        end
end


//reaf fsm
typedef enum logic [0:0] { R_IDLE, R_RESP } rd_state_t;
rd_state_t rd_state;

logic [ADDR_WIDTH-1:0] ar_addr_captured;
logic [DATA_WIDTH-1:0] r_data_captured;
logic ar_captured, r_captured;

always_ff @(posedge ACLK or negedge ARESETN)
begin
         //read fsm
        if (!ARESETN)
         begin
            rd_state <= R_IDLE;
            ARREADY <= 1'b0; 
            RVALID <= 1'b0;
            RRESP <= AXI_RESP_OKAY;
            ar_captured <= 1'b0;
            r_captured <= 1'b0;
            ar_addr_captured <= '0;
            r_data_captured <= '0;
        end
        else
        begin
        case(rd_state)

            R_IDLE:
            begin
                //default
                ARREADY<=1'b0;
                RVALID<=1'b0;

                if(ARVALID)
                begin
                    case(ARADDR)
                    SRC_ADDR_OFFSET:
                        begin
                        RDATA<=src_addr_reg;
                        RRESP<= AXI_RESP_OKAY;
                         end
                    DST_ADDR_OFFSET:
                        begin
                        RDATA<=dst_addr_reg;
                        RRESP <= AXI_RESP_OKAY;
                        end
                    LENGTH_OFFSET:
                        begin
                        RDATA<=length_reg;
                        RRESP<= AXI_RESP_OKAY;
                        end
                    DMA_CTRL_OFFSET:
                        begin
                            RDATA<={31'b0, dma_start_pending};
                            RRESP <= AXI_RESP_OKAY;

                        end

                    DMA_STATUS_OFFSET:
                    begin
                     RDATA<={29'b0, dma_error, dma_done, dma_busy};
                     RRESP <= AXI_RESP_OKAY;
                    end
                    default:
                    begin
                        RDATA <= '0;
                        RRESP <= AXI_RESP_SLVERR;
                    end

                    endcase
                    ar_addr_captured<=ARADDR;
                    ARREADY<=1'b1;
                    RVALID<=1'b1;
                    rd_state <= R_RESP;

                end
            end

            R_RESP:
            begin
                if(RREADY)
                begin
                    RVALID<=1'b0;
                    rd_state<=R_IDLE;
                end
            end
        endcase
        end
end

endmodule