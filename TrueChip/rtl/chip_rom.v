module chip_rom (
    output wire [127:0] chip_uid,
    output wire [127:0] secret_key
);
    assign chip_uid   = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_ABCD_EF01;
    
    assign secret_key = 128'h2B7E_1516_28AE_D2A6_ABF7_1588_09CF_4F3C;
endmodule