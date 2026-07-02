module nexuslite_dma_engine #(
    parameter int ADDR_WIDTH = 8,
    parameter int DATA_WIDTH = 32
)(
    input logic ACLK,
    input logic ARESETN,

    // From the CSR block
    input  logic [DATA_WIDTH-1:0] dma_src_addr,
    input  logic [DATA_WIDTH-1:0] dma_dst_addr,
    input  logic [DATA_WIDTH-1:0] dma_length,
    input  logic dma_start,
    output logic dma_start_ack,
    output logic dma_busy,
    output logic dma_done,
    output logic dma_error,

    // AXI-Lite MASTER interface (this module drives the outputs
    // that were inputs in your slave modules, and reads what were
    // outputs there - the direction of every signal flips)
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

import nexuslite_pkg::*;

typedef enum logic [2:0] { DMA_IDLE, DMA_READ_ADDR, DMA_READ_DATA, DMA_WRITE_ADDR_DATA ,DMA_WRITE_RESP} dma_state;
dma_state state;

logic [DATA_WIDTH-1:0] words_remaining;
logic [DATA_WIDTH-1:0] current_src_addr;
logic [DATA_WIDTH-1:0] current_dst_addr;
logic [DATA_WIDTH-1:0] read_data_captured;

always_ff @(posedge ACLK or negedge ARESETN)
begin
    if(!ARESETN)
    begin
        dma_start_ack<='0;
        dma_busy<='0;
        dma_done<='0;
        dma_error<='0;
        m_AWADDR<='0;
        m_AWVALID<='0;
        m_WDATA<='0;
        m_WVALID<='0;
        m_BREADY<='0;
        m_ARADDR<='0;
        m_ARVALID<='0;
        m_RREADY<='0;
        words_remaining<='0;
        current_src_addr<='0;
        current_dst_addr<='0;
        read_data_captured<='0;
        state<=DMA_IDLE;
    end
    else
    begin
        dma_done <= 1'b0;
        case(state)

        DMA_IDLE:
        begin
            dma_start_ack<='0;
            dma_busy<='0;

            if(dma_start)
            begin
                current_src_addr <= dma_src_addr;
                current_dst_addr <= dma_dst_addr;
                words_remaining <= dma_length;
                dma_start_ack <= 1'b1;
                dma_error <= 1'b0;
                state<=DMA_READ_ADDR;
                dma_busy <= 1'b1;
            end
        end
        DMA_READ_ADDR:
        begin
            m_ARADDR <= current_src_addr;
            m_ARVALID <= 1'b1;

            if(m_ARREADY) 
            begin
                m_ARVALID<='0;
                state<=DMA_READ_DATA;
            end
        end

        DMA_READ_DATA:
        begin
            m_RREADY <= 1'b1;
            if(m_RVALID)
            begin
                read_data_captured <= m_RDATA;
                m_RREADY <= 1'b0;
                if(m_RRESP!=AXI_RESP_OKAY)
                begin
                    dma_error <= 1'b1;
                    dma_busy<='0;
                    state<=DMA_IDLE;
                end
                else
                begin
                    state<=DMA_WRITE_ADDR_DATA;
                end
            end
        end

        DMA_WRITE_ADDR_DATA:
        begin
            m_AWADDR <= current_dst_addr;
            m_AWVALID <= 1'b1;
            m_WDATA <= read_data_captured;
            m_WVALID <= 1'b1;

            if(m_AWREADY && m_WREADY)
            begin
                 m_AWVALID <= 1'b0;
                 m_WVALID<=1'b0;
                 state<=DMA_WRITE_RESP;
            end
        end

        DMA_WRITE_RESP:
        begin
            m_BREADY <= 1'b1;
            if(m_BVALID)
             begin
                m_BREADY <= 1'b0;
                if(m_BRESP != AXI_RESP_OKAY)
                begin
                    dma_error <= 1'b1;
                    dma_busy  <= 1'b0;
                    state <= DMA_IDLE;
                end
                else if(words_remaining == 32'd1)
                begin
                    dma_done  <= 1'b1;
                    dma_busy  <= 1'b0;
                    state <= DMA_IDLE;
                end
                else
                begin
                    words_remaining  <= words_remaining - 1'b1;
                    current_src_addr <= current_src_addr + 1'b1;
                    current_dst_addr <= current_dst_addr + 1'b1;
                    state <= DMA_READ_ADDR;
                end
             end
         end

        endcase
    end
end

endmodule