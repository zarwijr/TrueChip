module chip_rom (
    output wire [127:0] chip_uid,
    output wire [127:0] secret_key
);
    // Mã UID của chip TrueChipDe10_2583 bạn vừa đăng ký
    assign chip_uid   = 128'h2583_2583_2583_2583_2583_2583_2583_2583;
    
    // Khóa bí mật (Secret Key) tương ứng
    assign secret_key = 128'h1234_1234_1234_1234_1234_1234_1234_1234;
endmodule