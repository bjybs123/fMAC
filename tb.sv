module testbench;

logic clk, reset;

logic [7:0]    Act_E [0:15];
logic [3:0]    Act_M [0:15];
logic [7:0]    Weight_E [0:15];
logic [3:0]    Weight_M [0:15];

logic [7:0]    result_E;
logic [23:0]   result_M;

logic [32-1:0] vectornum, errors;
logic [(12*16)-1:0] testvectors_Act [0:10000];
logic [(12*16)-1:0] testvectors_Weight [0:10000];

fmac dut(
    .i_clk(clk), 
    .i_reset_n(~reset),
    .i_Act_E(Act_E[0]),
    .i_Act_M(Act_M),
    .i_Weight_E(Weight_E[0]),
    .i_Weight_M(Weight_M),
    .i_prev_result_E(),
    .i_prev_result_M(),
    .o_result_E(result_E),
    .o_result_M(result_M),
    .o_Act_E(),
    .o_Act_M()
    );

always #5 clk = ~clk;

initial begin
    $readmemb("./weight.tv", testvectors_Weight);
    $readmemb("./bfps.tv", testvectors_Act);
    vectornum = 0; errors = 0;


    $dumpfile("testbench.vcd");
	$dumpvars(0, testbench);


    clk = 0; reset = 1; vectornum = 0;
    #27; reset = 0; 
    #10; 
    #128; $finish;
end

genvar i;
generate
    for(i=0; i<16; i=i+1) begin
        assign {Act_M[i][3], Act_E[i], Act_M[i][2:0]} = testvectors_Act[0][(i*12)+:12];
        assign {Weight_M[i][3], Weight_E[i], Weight_M[i][2:0]} = testvectors_Weight[0][(i*12)+:12];
    end
endgenerate



endmodule
