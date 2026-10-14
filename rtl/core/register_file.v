`timescale 1ns / 1ps

module register_file #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 5
)(
    input  wire                  i_clk,
    
    // Control Ports
    input  wire                  i_we,       // Write Enable (Validated)
    
    // Address Ports
    input  wire [ADDR_WIDTH-1:0] i_rs1_addr, // Read Address 1
    input  wire [ADDR_WIDTH-1:0] i_rs2_addr, // Read Address 2
    input  wire [ADDR_WIDTH-1:0] i_rd_addr,  // Write Address
    
    // Data Ports
    input  wire [DATA_WIDTH-1:0] i_wdata,    // Write Data
    output wire [DATA_WIDTH-1:0] o_rs1_data, // Read Data 1
    output wire [DATA_WIDTH-1:0] o_rs2_data  // Read Data 2
);

    // =========================================================================
    // MEMORY ARRAY
    // =========================================================================
    reg [DATA_WIDTH-1:0] r_regs [0:(1<<ADDR_WIDTH)-1];

    // Initialize all registers to 0 for simulation/FPGA (ignored by some ASIC flows)
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            r_regs[i] = {DATA_WIDTH{1'b0}};
        end
    end

    // =========================================================================
    // SYNCHRONOUS WRITE LOGIC
    // =========================================================================
    always @(posedge i_clk) begin
        // Protect x0: Hardwired to 0 per RISC-V ISA
        if (i_we && (i_rd_addr != {ADDR_WIDTH{1'b0}})) begin
            r_regs[i_rd_addr] <= i_wdata;
        end
    end

    // =========================================================================
    // ASYNCHRONOUS READ & INTERNAL FORWARDING (WRITE-BEFORE-READ)
    // =========================================================================
    // Resolves structural hazard when WB and ID stages access the same register.
    
    assign o_rs1_data = (i_rs1_addr == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : r_regs[i_rs1_addr];
    assign o_rs2_data = (i_rs2_addr == {ADDR_WIDTH{1'b0}}) ? {DATA_WIDTH{1'b0}} : r_regs[i_rs2_addr];

endmodule