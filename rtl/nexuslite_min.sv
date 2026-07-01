import nexuslite_pkg::*;
module nexuslite_min#(
    parameter int ADDR_WIDTH = 4,
    parameter int DATA_WIDTH = 32
)(
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
input  logic RREADY
);

logic [DATA_WIDTH-1:0] reg_data;

//write fsm
typedef enum logic [0:0] { WR_IDLE, WR_RESP } wr_state_t;
wr_state_t wr_state;

//reaf fsm
typedef enum logic [0:0] { R_IDLE, R_RESP } rd_state_t;
rd_state_t rd_state;

logic [ADDR_WIDTH-1:0] aw_addr_captured; //save address
logic [DATA_WIDTH-1:0] w_data_captured; //saves data to be written
logic aw_captured, w_captured; //1bit flags

logic [ADDR_WIDTH-1:0] ar_addr_captured;
logic [DATA_WIDTH-1:0] r_data_captured;
logic ar_captured, r_captured;

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
            reg_data <= '0;
        end

        else
        begin
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
                    reg_data    <= (WVALID && !w_captured) ? WDATA : w_data_captured; 
                    wr_state    <= WR_RESP;
                    BVALID      <= 1'b1;
                    BRESP       <= AXI_RESP_OKAY;
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
                    ar_addr_captured<=ARADDR;
                    ARREADY<=1'b1;
                    RDATA<=reg_data;
                    RVALID<=1'b1;
                    RRESP<=AXI_RESP_OKAY;
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