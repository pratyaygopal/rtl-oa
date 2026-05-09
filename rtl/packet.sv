module packet (
    input  logic       clk,
    input  logic       rst,

    input  logic       bit_valid,
    output logic       bit_ready,
    input  logic       bit_in,

    input  logic       out_ready,
    output logic       out_valid,
    output logic [7:0] out_data,
    output logic       packet_match
);

    localparam logic [7:0] MATCH_PATTERN = 8'b1011_0010;



endmodule