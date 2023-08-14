`timescale 1ns / 1ps

module fmac #(
    parameter GRPSIZE = 16,
    parameter FPEXPSIZE = 8,
    parameter FPMANSIZE = 23+1,
    parameter BFPEXPSIZE = 8,
    parameter BFPMANSIZE = 3+1
) (
    input  i_clk, 
    input  i_reset_n,
    input  [BFPEXPSIZE-1:0] i_Act_E,
    input  [BFPMANSIZE-1:0] i_Act_M [0:GRPSIZE-1],
    input  [BFPEXPSIZE-1:0] i_Weight_E,
    input  [BFPMANSIZE-1:0] i_Weight_M [0:GRPSIZE-1],
    input  [BFPEXPSIZE-1:0] i_prev_result_E,
    input  [BFPMANSIZE-1:0] i_prev_result_M [0:GRPSIZE-1],
    output logic [FPEXPSIZE-1:0]  o_result_E,
    output logic [FPMANSIZE-1:0]  o_result_M,
    output logic [BFPEXPSIZE-1:0] o_Act_E,
    output logic [BFPEXPSIZE-1:0] o_Act_M [0:GRPSIZE-1]
    );

    parameter levels = $clog2(GRPSIZE);
    parameter MULBFPMANSIZE = ((BFPMANSIZE-1)*2)+1;     //7-bit

    logic [(BFPEXPSIZE+1)-1:0] exp_rslt;                // additional 1-bit for carry in (9-bit)
    logic [BFPEXPSIZE-1:0] fp_exp;

    logic [MULBFPMANSIZE-1:0] mul_rslt [0:GRPSIZE-1];
    logic [(MULBFPMANSIZE+levels)-1:0] tmp_rslt [1:GRPSIZE-1];  //11-bit
    logic [FPMANSIZE-1:0] tmp_fp_man;
    logic [FPMANSIZE-1:0] fp_man;


    /* add exponent of two groups */
    always @ (*) begin
        exp_rslt = i_Act_E + i_Weight_E;
    end

    /* multiply mantissa mul_rslt[index] = activation[index] * weight[index] */
    genvar mul;
    generate
        for(mul=0; mul<2**levels; mul=mul+1) begin
            always @ (*) begin
                /* 0.aaa * 0.bbb = 0.cccccc */
                mul_rslt[mul][MULBFPMANSIZE-1] = i_Act_M[mul][BFPMANSIZE-1] ^ i_Weight_M[mul][BFPMANSIZE-1];            //multiply sign bit
                mul_rslt[mul][MULBFPMANSIZE-2:0] = i_Act_M[mul][BFPMANSIZE-2:0] * i_Weight_M[mul][BFPMANSIZE-2:0];      //multiply 3-bit mantissa
            end
        end
    endgenerate


    /* adder tree */
    genvar lv, add;
    generate
        for(lv=levels-1; lv>=0; lv=lv-1) begin : level
            for(add=0; add<2**lv; add=add+1) begin : add_man
                always @ (*) begin
                    /* For the first level of the adder tree, fetch operands from mul_rslt. */
                    if(lv == levels-1) begin
                        /* a + (-b) */
                        if(mul_rslt[add*2][MULBFPMANSIZE-1] == 0 && mul_rslt[add*2+1][MULBFPMANSIZE-1] == 1) begin  
                            /* |a| >= |b| */
                            if(mul_rslt[add*2][MULBFPMANSIZE-2:0] >= mul_rslt[add*2+1][MULBFPMANSIZE-2:0]) begin
                                /* tmp_rslt = a - b */                                                              
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 0;                                                                                            
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = mul_rslt[add*2][MULBFPMANSIZE-2:0] - mul_rslt[add*2+1][MULBFPMANSIZE-2:0];
                            end
                            /* |a| < |b| */
                            else begin
                                /* tmp_rslt = -(b - a) */                                                                                                  
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 1;                                                                                           
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = mul_rslt[add*2+1][MULBFPMANSIZE-2:0] - mul_rslt[add*2][MULBFPMANSIZE-2:0];
                            end
                        end
                        /* (-a) + b */
                        else if(mul_rslt[add*2][MULBFPMANSIZE-1] == 1 && mul_rslt[add*2+1][MULBFPMANSIZE-1] == 0) begin  
                            /* |a| >= |b| */                                                     
                            if(mul_rslt[add*2][MULBFPMANSIZE-2:0] >= mul_rslt[add*2+1][MULBFPMANSIZE-2:0]) begin      
                                /* tmp_rslt = -(b - a) */                                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 1;                                                                                            
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = mul_rslt[add*2][MULBFPMANSIZE-2:0] - mul_rslt[add*2+1][MULBFPMANSIZE-2:0];
                            end
                            /* |a| < |b| */
                            else begin   
                                /* tmp_rslt = b - a */                                                                                                                                    
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 0;                                                                                           
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = mul_rslt[add*2+1][MULBFPMANSIZE-2:0] - mul_rslt[add*2][MULBFPMANSIZE-2:0];
                            end
                        end
                        /* a + b or (-a) + (-b) */
                        else begin
                            /* tmp_rslt = +-(a + b) */
                            tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = mul_rslt[add*2][MULBFPMANSIZE-1];                                                             
                            tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = mul_rslt[add*2][MULBFPMANSIZE-2:0] + mul_rslt[add*2+1][MULBFPMANSIZE-2:0];
                        end
                    end
                    /* For the rest of the level, fetch operands from the previous level of the tree. tmp_rslt[level] = tmp_rslt[prev_level] + tmp_rslt[prev_level+1]*/
                    else begin
                        /* a + (-b) */
                        if(tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-1] == 0 && tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-1] == 1) begin    
                            /* |a| >= |b| */                                     
                            if(tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0] >= tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0]) begin    
                                /* tmp_rslt = a - b */                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 0;                                                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0] - tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0];
                            end
                            /* |a| < |b| */
                            else begin      
                                /* tmp_rslt = -(b - a) */                                                                                                             
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 1;                                                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0] - tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0];
                            end
                        end
                        /* (-a) + b */
                        else if(tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-1] == 1 && tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-1] == 0) begin 
                            /* |a| >= |b| */                                   
                            if(tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0] >= tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0]) begin
                                /* tmp_rslt = -(b - a) */                                           
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 1;                                                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0] - tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0];
                            end
                            /* |a| < |b| */
                            else begin     
                                /* tmp_rslt = b - a */                                                                                                              
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = 0;                                                                        
                                tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0] - tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0];
                            end
                        end
                        /* a + b or (-a) + (-b) */
                        else begin
                            /* tmp_rslt = +-(a + b) */
                            tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-1] = tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-1];                                          
                            tmp_rslt[2**lv+add][(MULBFPMANSIZE+levels)-2:0] = tmp_rslt[2**(lv+1)+add*2][(MULBFPMANSIZE+levels)-2:0] + tmp_rslt[2**(lv+1)+add*2+1][(MULBFPMANSIZE+levels)-2:0];
                        end
                    end
                end
            end
        end
    endgenerate

    /* making implicit leading 1 and check for exponent overflow and underflow */
    always @ (*) begin
        if(tmp_rslt[1][(MULBFPMANSIZE+levels)-2] == 1'b1) begin
            if((exp_rslt + 3) > 9'b0_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                fp_exp = exp_rslt + 3;
                fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 1;
                fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-3] == 1'b1) begin
            if((exp_rslt + 2) > 9'b0_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                fp_exp = exp_rslt + 2;
                fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 2;
                fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-4] == 1'b1) begin
            if((exp_rslt + 1) > 9'b0_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                fp_exp = exp_rslt + 1;
                fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 3;
                fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-5] == 1'b1) begin
            if(exp_rslt > 9'b0_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                fp_exp = exp_rslt;
                fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 4;
                fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-6] == 1'b1) begin
            if(({1'b1, exp_rslt} - 1) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 1) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 1;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 5;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-7] == 1'b1) begin
            if(({1'b1, exp_rslt} - 2) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 2) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 2;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 6;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-8] == 1'b1) begin
            if(({1'b1, exp_rslt} - 3) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 3) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 3;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 7;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-9] == 1'b1) begin
            if(({1'b1, exp_rslt} - 4) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 4) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 4;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 8;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-10] == 1'b1) begin
            if(({1'b1, exp_rslt} - 5) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 5) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 5;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 9;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;     
                end
            end
        end
        else if(tmp_rslt[1][(MULBFPMANSIZE+levels)-11] == 1'b1) begin
            if(({1'b1, exp_rslt} - 6) > 10'b10_1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                if(({1'b1, exp_rslt} - 6) < 10'b10_0000_0000) begin
                    fp_exp = 8'b0000_0000;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << exp_rslt;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
                end
                else begin
                    fp_exp = exp_rslt - 6;
                    fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
                    fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0] << 10;
                    fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;     
                end
            end
        end
        else begin
            fp_exp = exp_rslt;
            fp_man[23] = tmp_rslt[1][(MULBFPMANSIZE+levels)-1];
            fp_man[22:22-(MULBFPMANSIZE+levels-1)+1] = tmp_rslt[1][(MULBFPMANSIZE+levels)-2:0];
            fp_man[22-(MULBFPMANSIZE+levels-1):0] = 0;
        end
    end

    /* Output logic */
    always_ff @ (posedge i_clk or negedge i_reset_n) begin
        if(~i_reset_n) begin
            o_Act_E <= 0;
            o_result_E <= 0;
            o_result_M <= 0;
        end
        else begin
            o_Act_E <= i_Act_E;
            o_result_E <= fp_exp;
            o_result_M <= fp_man;
        end
    end

    genvar out;
    generate
        for(out=0; out<GRPSIZE; out=out+1) begin
            always_ff @ (posedge i_clk or negedge i_reset_n) begin
                if(~i_reset_n) begin
                    o_Act_M[out] <= 0;
                end
                else begin
                    o_Act_M[out] <= i_Act_M[out];
                end
                
            end
        end
    endgenerate


`ifdef DEBUG
    logic                              tmp_rslt_0_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_0;
    logic                              tmp_rslt_1_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_1;
    logic                              tmp_rslt_2_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_2;
    logic                              tmp_rslt_3_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_3;
    logic                              tmp_rslt_4_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_4;
    logic                              tmp_rslt_5_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_5;
    logic                              tmp_rslt_6_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_6;
    logic                              tmp_rslt_7_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_7;
    logic                              tmp_rslt_8_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_8;
    logic                              tmp_rslt_9_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_9;
    logic                              tmp_rslt_10_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_10;
    logic                              tmp_rslt_11_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_11;
    logic                              tmp_rslt_12_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_12;
    logic                              tmp_rslt_13_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_13;
    logic                              tmp_rslt_14_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_14;
    logic                              tmp_rslt_15_sign;
    logic [(MULBFPMANSIZE+levels)-2:0] tmp_rslt_15;



    logic                     mul_rslt_0_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_0;
    logic                     mul_rslt_1_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_1;
    logic                     mul_rslt_2_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_2;
    logic                     mul_rslt_3_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_3;
    logic                     mul_rslt_4_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_4;
    logic                     mul_rslt_5_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_5;
    logic                     mul_rslt_6_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_6;
    logic                     mul_rslt_7_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_7;
    logic                     mul_rslt_8_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_8;
    logic                     mul_rslt_9_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_9;
    logic                     mul_rslt_10_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_10;
    logic                     mul_rslt_11_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_11;
    logic                     mul_rslt_12_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_12;
    logic                     mul_rslt_13_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_13;
    logic                     mul_rslt_14_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_14;
    logic                     mul_rslt_15_sign;
    logic [MULBFPMANSIZE-2:0] mul_rslt_15;

    always @ (*) begin        
        //tmp_rslt_0 =  tmp_rslt[ 0][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_1_sign =  tmp_rslt[ 1][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_2_sign =  tmp_rslt[ 2][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_3_sign =  tmp_rslt[ 3][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_4_sign =  tmp_rslt[ 4][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_5_sign =  tmp_rslt[ 5][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_6_sign =  tmp_rslt[ 6][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_7_sign =  tmp_rslt[ 7][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_8_sign =  tmp_rslt[ 8][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_9_sign =  tmp_rslt[ 9][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_10_sign = tmp_rslt[10][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_11_sign = tmp_rslt[11][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_12_sign = tmp_rslt[12][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_13_sign = tmp_rslt[13][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_14_sign = tmp_rslt[14][(MULBFPMANSIZE+levels)-1];
        tmp_rslt_15_sign = tmp_rslt[15][(MULBFPMANSIZE+levels)-1];

        tmp_rslt_1 =  tmp_rslt[ 1][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_2 =  tmp_rslt[ 2][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_3 =  tmp_rslt[ 3][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_4 =  tmp_rslt[ 4][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_5 =  tmp_rslt[ 5][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_6 =  tmp_rslt[ 6][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_7 =  tmp_rslt[ 7][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_8 =  tmp_rslt[ 8][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_9 =  tmp_rslt[ 9][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_10 = tmp_rslt[10][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_11 = tmp_rslt[11][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_12 = tmp_rslt[12][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_13 = tmp_rslt[13][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_14 = tmp_rslt[14][(MULBFPMANSIZE+levels)-2:0];
        tmp_rslt_15 = tmp_rslt[15][(MULBFPMANSIZE+levels)-2:0];

        mul_rslt_0_sign =  mul_rslt[ 0][6];
        mul_rslt_1_sign =  mul_rslt[ 1][6];
        mul_rslt_2_sign =  mul_rslt[ 2][6];
        mul_rslt_3_sign =  mul_rslt[ 3][6];
        mul_rslt_4_sign =  mul_rslt[ 4][6];
        mul_rslt_5_sign =  mul_rslt[ 5][6];
        mul_rslt_6_sign =  mul_rslt[ 6][6];
        mul_rslt_7_sign =  mul_rslt[ 7][6];
        mul_rslt_8_sign =  mul_rslt[ 8][6];
        mul_rslt_9_sign =  mul_rslt[ 9][6];
        mul_rslt_10_sign = mul_rslt[10][6];
        mul_rslt_11_sign = mul_rslt[11][6];
        mul_rslt_12_sign = mul_rslt[12][6];
        mul_rslt_13_sign = mul_rslt[13][6];
        mul_rslt_14_sign = mul_rslt[14][6];
        mul_rslt_15_sign = mul_rslt[15][6];

        mul_rslt_0 =  mul_rslt[ 0][5:0];
        mul_rslt_1 =  mul_rslt[ 1][5:0];
        mul_rslt_2 =  mul_rslt[ 2][5:0];
        mul_rslt_3 =  mul_rslt[ 3][5:0];
        mul_rslt_4 =  mul_rslt[ 4][5:0];
        mul_rslt_5 =  mul_rslt[ 5][5:0];
        mul_rslt_6 =  mul_rslt[ 6][5:0];
        mul_rslt_7 =  mul_rslt[ 7][5:0];
        mul_rslt_8 =  mul_rslt[ 8][5:0];
        mul_rslt_9 =  mul_rslt[ 9][5:0];
        mul_rslt_10 = mul_rslt[10][5:0];
        mul_rslt_11 = mul_rslt[11][5:0];
        mul_rslt_12 = mul_rslt[12][5:0];
        mul_rslt_13 = mul_rslt[13][5:0];
        mul_rslt_14 = mul_rslt[14][5:0];
        mul_rslt_15 = mul_rslt[15][5:0];
    end


`endif

endmodule