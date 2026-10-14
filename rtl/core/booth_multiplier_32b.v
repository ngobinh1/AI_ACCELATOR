`timescale 1ns / 1ps
// ==============================================================================
// MODULE: booth_multiplier_32b (8-Cycle Sequential Multiplier)
// DESCRIPTION: 32x32 -> 64-bit Signed/Unsigned Iterative Multiplier (4-bit/cycle)
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3 Option B Refactor)
// ==============================================================================

module booth_multiplier_32b (
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // =========================================================================
    // PIPELINE CONTROL & HANDSHAKE INTERFACE
    // =========================================================================
    input  wire        i_mul_valid,     // Request from Stage 2 (ID/EX)
    input  wire        i_flush,         // Flush on branch mispredict or trap
    output wire        o_ready,         // Calculation complete (1 at cycle 8)
    output wire        o_busy,          // Busy computing (cycles 1..7)
    
    // =========================================================================
    // DATA INPUTS
    // =========================================================================
    input  wire [31:0] i_multiplicand,  // RS1
    input  wire [31:0] i_multiplier,    // RS2
    input  wire        i_is_signed_a,   // Signed flag for RS1
    input  wire        i_is_signed_b,   // Signed flag for RS2
    
    // =========================================================================
    // DATA OUTPUT
    // =========================================================================
    output wire [63:0] o_product        // 64-bit result {MULH*, MUL}
);

    // =========================================================================
    // FSM STATES
    // =========================================================================
    localparam S_IDLE = 2'b00;
    localparam S_CALC = 2'b01;
    localparam S_DONE = 2'b10;

    reg [1:0]  r_state;
    reg [2:0]  r_cnt;       // 0 to 7 (8 cycles)
    reg [31:0] r_a;         // Multiplicand magnitude
    reg [31:0] r_b;         // Multiplier magnitude (shifted right 4 bits/cycle)
    reg [63:0] r_acc;       // 64-bit accumulator
    reg        r_sign;      // Final sign flag

    // =========================================================================
    // OPERAND SIGN & MAGNITUDE EXTRACTION
    // =========================================================================
    wire sign_a = i_is_signed_a & i_multiplicand[31];
    wire sign_b = i_is_signed_b & i_multiplier[31];
    wire [31:0] abs_a = sign_a ? (-i_multiplicand) : i_multiplicand;
    wire [31:0] abs_b = sign_b ? (-i_multiplier) : i_multiplier;
    wire prod_sign = (abs_a != 32'd0 && abs_b != 32'd0) ? (sign_a ^ sign_b) : 1'b0;

    // =========================================================================
    // 4-BIT CHUNK PARTIAL PRODUCT & ACCUMULATION
    // =========================================================================
    // 32-bit x 4-bit unsigned product produces up to 36-bit result
    wire [35:0] w_chunk_prod = r_a * r_b[3:0];
    
    // Upper addition: add chunk product to upper 36 bits of accumulator
    // r_acc is shifted right by 4 bits each cycle
    wire [36:0] w_sum = {4'b0, r_acc[63:32]} + {1'b0, w_chunk_prod};

    // =========================================================================
    // FSM SEQUENTIAL LOGIC
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_state <= S_IDLE;
            r_cnt   <= 3'd0;
            r_a     <= 32'd0;
            r_b     <= 32'd0;
            r_acc   <= 64'd0;
            r_sign  <= 1'b0;
        end else if (i_flush) begin
            r_state <= S_IDLE;
            r_cnt   <= 3'd0;
            r_a     <= 32'd0;
            r_b     <= 32'd0;
            r_acc   <= 64'd0;
            r_sign  <= 1'b0;
        end else begin
            case (r_state)
                S_IDLE: begin
                    if (i_mul_valid) begin
                        r_state <= S_CALC;
                        r_cnt   <= 3'd0;
                        r_a     <= abs_a;
                        r_b     <= abs_b;
                        r_acc   <= 64'd0;
                        r_sign  <= prod_sign;
                    end
                end

                S_CALC: begin
                    // Shift-and-accumulate 4 bits per cycle
                    r_acc <= {w_sum[35:0], r_acc[31:4]};
                    r_b   <= {4'b0, r_b[31:4]};
                    
                    if (r_cnt == 3'd7) begin
                        r_state <= S_DONE;
                    end else begin
                        r_cnt <= r_cnt + 3'd1;
                    end
                end

                S_DONE: begin
                    // Hold result until pipeline consumes it or new mul starts
                    if (i_mul_valid) begin
                        r_state <= S_CALC;
                        r_cnt   <= 3'd0;
                        r_a     <= abs_a;
                        r_b     <= abs_b;
                        r_acc   <= 64'd0;
                        r_sign  <= prod_sign;
                    end else begin
                        r_state <= S_IDLE;
                    end
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // OUTPUT ASSIGNMENTS
    // =========================================================================
    assign o_ready   = (r_state == S_DONE);
    assign o_busy    = (r_state == S_CALC) || (r_state == S_IDLE && i_mul_valid);
    assign o_product = r_sign ? (-r_acc) : r_acc;

endmodule
