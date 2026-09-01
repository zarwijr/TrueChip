module chip_rom (
    output wire [127:0] chip_uid,
    output wire [127:0] master_key
);
    // ============================================================
    // Ma UID cong khai cua chip (khong bi mat, dung de nhan dang)
    // ============================================================
    assign chip_uid   = 128'h2583_2583_2583_2583_2583_2583_2583_2583;

    // ============================================================
    // MASTER KEY - PROTOTYPE ONLY.
    //
    // In this design it is used at boot for:
    //     diversified_key = AES_encrypt(master_key, puf_id)
    // and the diversified key is then used for CHALLENGE responses.
    //
    // Do not over-claim this construction: a hard-coded common master key is
    // acceptable only for the FPGA/competition prototype. A production chip
    // should use a secure provisioning/root-of-trust scheme (e.g. per-device
    // OTP/eFuse/NVM or a properly characterized PUF key-reconstruction flow),
    // with explicit resistance goals for invasive probing, fault injection and
    // side-channel attacks. PUF outputs also require measured stability; they
    // are not automatically secret or perfectly unclonable merely because they
    // originate from manufacturing variation.
    // ============================================================
    assign master_key = 128'h1234_1234_1234_1234_1234_1234_1234_1234;
endmodule
