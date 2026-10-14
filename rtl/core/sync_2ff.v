`timescale 1ns / 1ps
// ==============================================================================
// MODULE: sync_2ff
// DESCRIPTION: 2-Flip-Flop Synchronizer for asynchronous external inputs
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core
// ==============================================================================

module sync_2ff #(
    parameter WIDTH = 1,
    parameter RST_VAL = 0
)(
    input  wire             i_clk,
    input  wire             i_rst_n,
    input  wire [WIDTH-1:0] i_async,
    output wire [WIDTH-1:0] o_sync
);

    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] r_meta;
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] r_sync;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_meta <= {WIDTH{RST_VAL[0]}};
            r_sync <= {WIDTH{RST_VAL[0]}};
        end else begin
            r_meta <= i_async;
            r_sync <= r_meta;
        end
    end

    assign o_sync = r_sync;

endmodule
