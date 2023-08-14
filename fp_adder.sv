
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
    logic [7:0] tmp_fp_exp;
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
    //assign is_fp1_NaN = (is_fp1_infinity && (fp1_man != 0)) ? 1 : 0;
    //assign is_fp2_NaN = (is_fp2_infinity && (fp2_man != 0)) ? 1 : 0;
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
            tmp_fp_exp = 8'b1111_1111;
            fp_man_carry = 0;
        end
        else if(is_fp1_zero || is_fp2_zero) begin
            if(is_fp1_zero) begin
                fp_sign = fp2_sign;
                tmp_fp_exp = fp2_exp;
                fp_man_carry = {2'b00, fp2_man};
            end
            else begin
                fp_sign = fp1_sign;
                tmp_fp_exp = fp1_exp;
                fp_man_carry = {2'b00, fp1_man};
            end
        end
        else begin
            if(is_fp1_denorm || is_fp2_denorm) begin
                /* |fp2| > |fp1|, since fp1 is 0.xxx... */
                if(is_fp1_denorm) begin
                    tmp_fp_exp = fp2_exp;                                       // set exponent
                    fp1_man_align = {1'b0, fp1_man} >> (fp2_exp - 1);           // mantissa alignment
                    /* fp1 + (-fp2) */
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin
                        fp_sign = 1;
                        fp_man_carry = {2'b01, fp2_man} - {2'b00, fp1_man_align};   // fp = -(fp2 - fp1)
                    end
                    /* (-fp1) + fp2 */
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin
                        fp_sign = 0;
                        fp_man_carry = {2'b01, fp2_man} - {2'b00, fp1_man_align};   // fp = (fp2 - fp1)
                    end
                    /* (-fp1) + (-fp2) or fp1 + fp2 */
                    else begin
                        fp_sign = fp1_sign;
                        fp_man_carry = {2'b01, fp2_man} + {2'b00, fp1_man_align};   // fp = +-(fp2 + fp1)
                    end
                end
                /* |fp1| > |fp2|, since fp2 is 0.xxx... */
                else begin               
                    tmp_fp_exp = fp1_exp;                                       // set exponent
                    fp2_man_align = {1'b0, fp2_man} >> (fp1_exp - 1);           // mantissa alignment 
                    /* fp1 + (-fp2) */
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin
                        fp_sign = 0;
                        fp_man_carry = {2'b01, fp1_man} - {2'b00, fp2_man_align};   // fp = fp1 - fp2
                    end
                    /* (-fp1) + fp2 */
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin               
                        fp_sign = 1;
                        fp_man_carry = {2'b01, fp1_man} - {2'b00, fp2_man_align};   // fp = -(fp1 - fp2) 
                    end
                    /* (-fp1) + (-fp2) or fp1 + fp2 */
                    else begin
                        fp_sign = fp2_sign;
                        fp_man_carry = {2'b01, fp1_man} + {2'b00, fp2_man_align};   // fp = +-(fp1 + fp2)
                    end
                end
            end
            /* two normalized number */
            else begin
                /* |fp2| >= |fp1| */
                if(fp2_exp >= fp1_exp) begin
                    tmp_fp_exp = fp2_exp;                                           // set exponent 
                    fp1_man_align = {1'b1, fp1_man} >> (fp2_exp - fp1_exp - 1);     // mantissa align
                    /* fp1 + (-fp2) */
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin
                        fp_sign = 1;
                        fp_man_carry = {2'b01, fp2_man} - {2'b00, fp1_man_align};   // fp = -(fp2 - fp1)
                    end
                    /* (-fp1) + fp2 */
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin            
                        fp_sign = 0;    
                        fp_man_carry = {2'b01, fp2_man} - {2'b00, fp1_man_align};   // fp = (fp2 - fp1)
                    end
                    /* (-fp1) + (-fp2) or fp1 + fp2 */
                    else begin
                        fp_sign = fp1_sign;
                        fp_man_carry = {2'b01, fp2_man} + {2'b00, fp1_man_align};   // fp = +-(fp2 + fp1)
                    end
                end
                /* |fp2| < |fp1| */
                else begin
                    tmp_fp_exp = fp1_exp;                                           // set exponent 
                    fp2_man_align = {1'b1, fp2_man} >> (fp1_exp - fp2_exp - 1);     // mantissa alignment 
                    /* fp1 + (-fp2) */
                    if((fp1_sign == 0) && (fp2_sign == 1)) begin
                        fp_sign = 0;
                        fp_man_carry = {2'b01, fp1_man} - {2'b00, fp2_man_align};   // fp = (fp1 - fp2)
                    end
                    /* (-fp1) + fp2 */
                    else if((fp1_sign == 1) && (fp2_sign == 0)) begin
                        fp_sign = 1;
                        fp_man_carry = {2'b01, fp1_man} - {2'b00, fp2_man_align};   // fp = -(fp1 - fp2)
                    end
                    /* (-fp1) + (-fp2) or fp1 + fp2 */
                    else begin
                        fp_sign = fp2_sign;
                        fp_man_carry = {2'b01, fp1_man} + {2'b00, fp2_man_align};   // fp = +-(fp1 + fp2)
                    end
                end
            end
        end
    end


    /* making implicit leading 1 and check for exponent overflow and underflow */
    always @ (*) begin
        if(fp_man_carry[24] == 1'b1) begin
            if((tmp_fp_exp + 1) > 8'b1111_1110) begin
                fp_exp = 8'b1111_1111;
                fp_man = 0;
            end
            else begin
                fp_exp = tmp_fp_exp + 1;
                fp_man = fp_man_carry[23:1];
            end
        end
        else if(fp_man_carry[23] == 1'b1) begin
            fp_exp = tmp_fp_exp;
            fp_man = fp_man_carry[22:0];
        end
        else if(fp_man_carry[22] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 1) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 1;
                fp_man = fp_man_carry[22:0] << 1;
            end 
        end
        else if(fp_man_carry[21] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 2) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 2;
                fp_man = fp_man_carry[22:0] << 2;
            end 
        end
        else if(fp_man_carry[20] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 3) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 3;
                fp_man = fp_man_carry[22:0] << 3;
            end 
        end
        else if(fp_man_carry[19] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 4) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 4;
                fp_man = fp_man_carry[22:0] << 4;
            end 
        end
        else if(fp_man_carry[18] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 5) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 5;
                fp_man = fp_man_carry[22:0] << 5;
            end 
        end
        else if(fp_man_carry[17] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 6) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 6;
                fp_man = fp_man_carry[22:0] << 6;
            end 
        end
        else if(fp_man_carry[16] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 7) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 7;
                fp_man = fp_man_carry[22:0] << 7;
            end 
        end
        else if(fp_man_carry[15] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 8) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 8;
                fp_man = fp_man_carry[22:0] << 8;
            end 
        end
        else if(fp_man_carry[14] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 9) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 9;
                fp_man = fp_man_carry[22:0] << 9;
            end 
        end
        else if(fp_man_carry[13] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 10) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 10;
                fp_man = fp_man_carry[22:0] << 10;
            end 
        end
        else if(fp_man_carry[12] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 11) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 11;
                fp_man = fp_man_carry[22:0] << 11;
            end 
        end
        else if(fp_man_carry[11] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 12) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 12;
                fp_man = fp_man_carry[22:0] << 12;
            end 
        end
        else if(fp_man_carry[10] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 13) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 13;
                fp_man = fp_man_carry[22:0] << 13;
            end 
        end
        else if(fp_man_carry[9] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 14) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 14;
                fp_man = fp_man_carry[22:0] << 14;
            end 
        end
        else if(fp_man_carry[8] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 15) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 15;
                fp_man = fp_man_carry[22:0] << 15;
            end 
        end
        else if(fp_man_carry[7] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 16) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 16;
                fp_man = fp_man_carry[22:0] << 16;
            end 
        end
        else if(fp_man_carry[6] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 17) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 17;
                fp_man = fp_man_carry[22:0] << 17;
            end 
        end
        else if(fp_man_carry[5] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 18) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 18;
                fp_man = fp_man_carry[22:0] << 18;
            end 
        end
        else if(fp_man_carry[4] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 19) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 19;
                fp_man = fp_man_carry[22:0] << 19;
            end 
        end
        else if(fp_man_carry[3] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 20) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 20;
                fp_man = fp_man_carry[22:0] << 20;
            end 
        end
        else if(fp_man_carry[2] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 21) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 21;
                fp_man = fp_man_carry[22:0] << 21;
            end 
        end
        else if(fp_man_carry[1] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 22) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 22;
                fp_man = fp_man_carry[22:0] << 22;
            end 
        end
        else if(fp_man_carry[0] == 1'b1) begin
            if(({1'b1, tmp_fp_exp} - 23) < 9'b1_0000_0000) begin
                fp_exp = 8'b0000_0000;
                fp_man = fp_man_carry[22:0] << tmp_fp_exp;
            end
            else begin
                fp_exp = tmp_fp_exp - 23;
                fp_man = fp_man_carry[22:0] << 23;
            end 
        end
    end

endmodule