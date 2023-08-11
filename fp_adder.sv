
module fp_adder (
    input [32-1:0] i_fp1,
    input [32-1:0] i_fp2,
    output [32-1:0] o_fp
);
    logic fp1_sign;
    logic [7:0] fp1_exp;
    logic [22:0] fp1_man;
    logic [22:0] fp1_man_align;

    logic fp2_sign;
    logic [7:0] fp2_exp;
    logic [22:0] fp2_man;
    logic [22:0] fp2_man_align;

    logic fp_sign;
    logic [7:0] fp_exp;
    logic [8:0] fp_exp_carry;
    logic [22:0] fp_man;
    logic [24:0] fp_man_carry;

    logic is_fp1_infinity;
    logic is_fp2_infinity;
    logic is_fp1_denorm;
    logic is_fp2_denorm;
    logic larger_fp1_exp;

    // component slicing
    always @ (*) begin
        //fp1
        fp1_sign = i_fp1[31];
        fp1_exp = i_fp1[30:23];
        fp1_man = i_fp1[22:0];
        //fp2
        fp2_sign = i_fp2[31];
        fp2_exp = i_fp2[30:23];
        fp2_man = i_fp2[22:0];
    end

    /* check special cases */
    assign is_fp1_infinity = (fp1_exp == 8'b1111_1111) ? 1 : 0;
    assign is_fp2_infinity = (fp2_exp == 8'b1111_1111) ? 1 : 0;
    assign is_fp1_NaN = (is_fp1_infinity && (fp1_man != 0)) ? 1 : 0;
    assign is_fp2_NaN = (is_fp2_infinity && (fp2_man != 0)) ? 1 : 0;
    assign is_fp1_denorm = (fp1_exp == 8'b0000_0000) ? 1 : 0;
    assign is_fp2_denorm = (fp2_exp == 8'b0000_0000) ? 1 : 0;
    assign is_fp1_zero = (is_fp1_denorm && (fp1_man == 0)) ? 1 : 0;
    assign is_fp2_zero = (is_fp2_denorm && (fp2_man == 0)) ? 1 : 0;
    assign larger_fp1_exp = (fp1_exp > fp2_exp) ? 1 : 0;


    /* Add operation */
    always @ (*) begin
        if(is_fp1_infinity || is_fp2_infinity) begin
            if(is_fp1_infinity) begin
                fp_sign = fp1_sign;
            end
            else begin
                fp_sign = fp2_sign;
            end
            fp_exp = 8'b1111_1111;
            fp_man = 0;
        end
        else if(is_fp1_zero || is_fp2_zero) begin
            if(is_fp1_zero) begin
                fp_sign = fp2_sign;
                fp_exp = fp2_exp;
                fp_man = fp2_man;
            end
            else begin
                fp_sign = fp1_sign;
                fp_exp = fp1_exp;
                fp_man = fp1_man;
            end
        end
        else begin
            /* mantissa alignment */ 
            if(is_fp1_denorm || is_fp2_denorm) begin
                if(is_fp1_denorm) begin
                    fp1_man_align = {1'b0, fp1_man} >> (fp2_exp - 1);               //mantissa align
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin                    // fp1 + (-fp2)
                        fp_sign = 1;
                        fp_man_carry = {1'b1, fp2_man} - {1'b0, fp1_man_align};
                    end
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin               // (-fp1) + fp2
                        fp_sign = 0;
                        fp_man_carry = {1'b1, fp2_man} - {1'b0, fp1_man_align};
                    end
                    else begin
                        fp_sign = fp1_sign;
                        fp_man_carry = {1'b1, fp2_man} + {1'b0, fp1_man_align};
                    end
                end
                else begin                                                          
                    fp2_man_align = {1'b0, fp2_man} >> (fp1_exp - 1);               // mantissa align
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin                    // fp1 + (-fp2)
                        fp_sign = 0;
                        fp_man_carry = {1'b1, fp1_man} - {1'b0, fp2_man_align};
                    end
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin               // (-fp1) + fp2
                        fp_sign = 1;
                        fp_man_carry = {1'b1, fp1_man} - {1'b0, fp2_man_align};
                    end
                    else begin
                        fp_sign = fp2_sign;
                        fp_man_carry = {1'b1, fp1_man} + {1'b0, fp2_man_align};
                    end
                end
            end
            else begin
                if(fp2_exp >= fp1_exp) begin
                    fp1_man_align = {1'b1, fp1_man} >> (fp2_exp - fp1_exp - 1);     //mantissa align
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin                    // fp1 + (-fp2)
                        fp_sign = 1;
                        fp_man_carry = {1'b1, fp2_man} - {1'b0, fp1_man_align};
                    end
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin               // (-fp1) + fp2
                        fp_sign = 0;
                        fp_man_carry = {1'b1, fp2_man} - {1'b0, fp1_man_align};
                    end
                    else begin
                        fp_sign = fp1_sign;
                        fp_man_carry = {1'b1, fp2_man} + {1'b0, fp1_man_align};
                    end
                end
                else begin
                    fp2_man_align = {1'b1, fp2_man} >> (fp1_exp - fp2_exp - 1);
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin                    // fp1 + (-fp2)
                        fp_sign = 0;
                        fp_man_carry = {1'b1, fp1_man} - {1'b0, fp2_man_align};
                    end
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin               // (-fp) + fp2
                        fp_sign = 1;
                        fp_man_carry = {1'b1, fp1_man} - {1'b0, fp2_man_align};
                    end
                    else begin
                        fp_sign = fp2_sign;
                        fp_man_carry = {1'b1, fp1_man} + {1'b0, fp2_man_align};
                    end
                end
            end


        end
    end
    
    



endmodule