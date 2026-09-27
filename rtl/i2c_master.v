// Simple I2C master (baseline write-only, single target).
// we treat SCL/SDA as simple push-pull signals, not full
// open-drain with multi-master arbitration. Focus is on bit timing and
// start/address/data/stop sequencing.
//
// One transaction:
//   - START
//   - 7-bit address + write bit (0)
//   - 8-bit data byte
//   - STOP

`timescale 1ns/1ps

module i2c_master (
    input  wire       clk,
    input  wire       rst_n,        // Active-low async reset
    input  wire       clk_div_tick, // Divider pulse controlling SCL timing
    input  wire       start,        // Pulse high for one cycle to start transfer
    input  wire [6:0] addr,         // 7-bit I2C address
    input  wire [7:0] data_in,      // Byte to send
    output reg        scl,          // I2C clock (simplified)
    output reg        sda,          // I2C data (simplified)
    output reg        busy,         // High while transfer in progress
    output reg        done          // One-cycle pulse at end of transfer
);
    // State encoding (pure Verilog - no typedef enum).
    localparam [2:0] IDLE       = 3'd0,
                      START_COND = 3'd1,
                      ADDR_BITS  = 3'd2,
                      DATA_BITS  = 3'd3,
                      STOP_COND  = 3'd4;

    reg [2:0] state;
    reg [7:0] shift_reg;
    reg [3:0] bit_idx;   // up to 8 bits

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            shift_reg <= 8'h00;
            bit_idx   <= 4'd0;
            scl       <= 1'b1;  // idle high
            sda       <= 1'b1;  // idle high
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    scl  <= 1'b1;
                    sda  <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        // Prepare address + write bit (LSB = 0).
                        shift_reg <= {addr, 1'b0};
                        bit_idx   <= 4'd7;
                        state     <= START_COND;
                        busy      <= 1'b1;
                    end
                end

                START_COND: begin
                    // Generate START: SDA goes low while SCL is high.
                    sda <= 1'b0;
                    if (clk_div_tick) begin
                        state <= ADDR_BITS;
                        // First bit will be driven while SCL is low.
                        scl <= 1'b0;
                    end
                end

                ADDR_BITS: begin
                    if (clk_div_tick) begin
                        // Drive data while SCL low, then raise SCL to "clock" it.
                        if (scl == 1'b0) begin
                            sda <= shift_reg[bit_idx];
                            scl <= 1'b1;
                        end else begin
                            scl <= 1'b0;
                            if (bit_idx == 0) begin
                                // Address+W complete; move to data phase.
                                shift_reg <= data_in;
                                bit_idx   <= 4'd7;
                                state     <= DATA_BITS;
                            end else begin
                                bit_idx <= bit_idx - 4'd1;
                            end
                        end
                    end
                end

                DATA_BITS: begin
                    if (clk_div_tick) begin
                        if (scl == 1'b0) begin
                            sda <= shift_reg[bit_idx];
                            scl <= 1'b1;
                        end else begin
                            scl <= 1'b0;
                            if (bit_idx == 0) begin
                                state <= STOP_COND;
                            end else begin
                                bit_idx <= bit_idx - 4'd1;
                            end
                        end
                    end
                end

                STOP_COND: begin
                    // Generate STOP: SDA goes high while SCL is high.
                    scl <= 1'b1;
                    if (clk_div_tick) begin
                        sda  <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state<= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule