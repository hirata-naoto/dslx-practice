import rv32i;

fn r(funct7: u7, funct3: u3) -> u32 { funct7 ++ u5:2 ++ u5:1 ++ funct3 ++ u5:3 ++ u7:0x33 }

fn i(opcode: u7, funct3: u3, rd: u5, rs1: u5, immediate: u12) -> u32 {
    immediate ++ rs1 ++ funct3 ++ rd ++ opcode
}

fn s(funct3: u3, immediate: u12) -> u32 {
    immediate[5+:u7] ++ u5:2 ++ u5:1 ++ funct3 ++ immediate[0+:u5] ++ u7:0x23
}

fn b(funct3: u3, offset: u13) -> u32 {
    offset[12+:u1] ++ offset[5+:u6] ++ u5:2 ++ u5:1 ++ funct3 ++ offset[1+:u4] ++ offset[11+:u1] ++
    u7:0x63
}

fn j(rd: u5, offset: u21) -> u32 {
    offset[20+:u1] ++ offset[1+:u10] ++ offset[11+:u1] ++ offset[12+:u8] ++ rd ++ u7:0x6f
}

fn operands(a: u32, b: u32) -> rv32i::State {
    let state = rv32i::reset(u32:0x1000);
    rv32i::State { regs: update(update(state.regs, u32:1, a), u32:2, b), ..state }
}

fn check_alu(state: rv32i::State, instruction: u32, expected: u32) {
    let result = rv32i::step(state, instruction, u32:0);
    assert_eq(result.state.regs[u32:3], expected);
    assert_eq(result.state.pc, state.pc + u32:4);
    assert_eq(result.state.regs[u32:0], u32:0);
    assert_eq(result.state.regs[u32:1], state.regs[u32:1]);
    assert_eq(result.state.regs[u32:2], state.regs[u32:2]);
    assert_eq(result.state.trapped, false);
    assert_eq(result.memory.valid, false);
}

fn check_trap(state: rv32i::State, instruction: u32, cause: u32, value: u32) {
    let result = rv32i::step(state, instruction, u32:0xaabbccdd);
    assert_eq(result.state.trapped, true);
    assert_eq(result.state.trap_cause, cause);
    assert_eq(result.state.trap_value, value);
    assert_eq(result.state.pc, state.pc);
    assert_eq(result.state.regs, state.regs);
    assert_eq(result.memory.valid, false);
    assert_eq(result.memory.write, false);
    assert_eq(rv32i::memory_request(state, instruction).valid, false);
    assert_eq(rv32i::step(result.state, u32:0x00108093, u32:0).state, result.state);
    assert_eq(rv32i::step(result.state, s(u3:2, u12:0), u32:0).memory.valid, false);
}

#[test]
fn reset_and_zero_register_test() {
    let state = rv32i::reset(u32:0);
    assert_eq(state.regs, u32[32]:[u32:0, ...]);
    assert_eq(state.trapped, false);
    let result = rv32i::step(state, u32:0xfff00013, u32:0);  // addi x0, x0, -1
    assert_eq(result.state.regs, state.regs);
    assert_eq(result.state.pc, u32:4);
    let result = rv32i::step(result.state, u32:0x00700f93, u32:0);  // addi x31, x0, 7
    assert_eq(result.state.regs[u32:31], u32:7);
}

#[test]
fn register_alu_test() {
    let state = operands(u32:0x80000005, u32:3);
    let cases = [
        (u7:0, u3:0, u32:0x80000008), // ADD
        (u7:0x20, u3:0, u32:0x80000002), // SUB
        (u7:0, u3:1, u32:0x28), // SLL
        (u7:0, u3:2, u32:1), // SLT
        (u7:0, u3:3, u32:0), // SLTU
        (u7:0, u3:4, u32:0x80000006), // XOR
        (u7:0, u3:5, u32:0x10000000), // SRL
        (u7:0x20, u3:5, u32:0xf0000000), // SRA
        (u7:0, u3:6, u32:0x80000007), // OR
        (u7:0, u3:7, u32:1), // AND
    ];
    for (index, ()): (u32, ()) in u32:0..u32:10 {
        let (funct7, funct3, expected) = cases[index];
        check_alu(state, r(funct7, funct3), expected);
    }(())
}

#[test]
fn immediate_alu_test() {
    let state = operands(u32:0x80000005, u32:0);
    let cases = [
        (u3:0, u12:0xfff, u32:0x80000004), // ADDI -1
        (u3:2, u12:0xfff, u32:1), // SLTI -1
        (u3:3, u12:0xfff, u32:1), // SLTIU sign-extends the immediate
        (u3:4, u12:0xfff, u32:0x7ffffffa), // XORI
        (u3:6, u12:0xff0, u32:0xfffffff5), // ORI
        (u3:7, u12:0xff0, u32:0x80000000), // ANDI
        (u3:1, u12:3, u32:0x28), // SLLI
        (u3:5, u12:3, u32:0x10000000), // SRLI
        (u3:5, u12:0x403, u32:0xf0000000), // SRAI
    ];
    for (index, ()): (u32, ()) in u32:0..u32:9 {
        let (funct3, immediate, expected) = cases[index];
        check_alu(state, i(u7:0x13, funct3, u5:3, u5:1, immediate), expected);
    }(())
}

#[test]
fn arithmetic_boundaries_test() {
    check_alu(operands(u32:0xffffffff, u32:1), r(u7:0, u3:0), u32:0);
    check_alu(operands(u32:0, u32:1), r(u7:0x20, u3:0), u32:0xffffffff);
    check_alu(operands(u32:0x7fffffff, u32:1), r(u7:0, u3:0), u32:0x80000000);
    check_alu(operands(u32:0x80000000, u32:0xffffffff), r(u7:0, u3:2), u32:1);
    check_alu(operands(u32:0xffffffff, u32:0), r(u7:0, u3:3), u32:0);
    check_alu(operands(u32:0, u32:0), i(u7:0x13, u3:0, u5:3, u5:1, u12:0x800), u32:0xfffff800);
    check_alu(operands(u32:0, u32:0), i(u7:0x13, u3:0, u5:3, u5:1, u12:0x7ff), u32:0x7ff);
}

#[test]
fn shift_amount_masking_test() {
    for (amount, ()): (u32, ()) in u32:0..u32:64 {
        let state = operands(u32:0x80000001, amount);
        let shamt = amount & u32:31;
        check_alu(state, r(u7:0, u3:1), u32:0x80000001 << shamt);
        check_alu(state, r(u7:0, u3:5), u32:0x80000001 >> shamt);
        check_alu(state, r(u7:0x20, u3:5), ((u32:0x80000001 as s32) >> shamt) as u32);
        check_alu(state, i(u7:0x13, u3:1, u5:3, u5:1, shamt as u12), u32:0x80000001 << shamt);
        check_alu(state, i(u7:0x13, u3:5, u5:3, u5:1, shamt as u12), u32:0x80000001 >> shamt);
        check_alu(
            state, i(u7:0x13, u3:5, u5:3, u5:1, u12:0x400 | shamt as u12),
            ((u32:0x80000001 as s32) >> shamt) as u32);
    }(())
}

#[test]
fn upper_immediates_and_pc_wrap_test() {
    check_alu(operands(u32:0, u32:0), u32:0xabcde1b7, u32:0xabcde000);  // LUI x3
    check_alu(operands(u32:0, u32:0), u32:0xfffff197, u32:0);  // AUIPC x3, -1
    let result = rv32i::step(rv32i::reset(u32:0xfffffffc), u32:0x00000197, u32:0);
    assert_eq(result.state.regs[u32:3], u32:0xfffffffc);
    assert_eq(result.state.pc, u32:0);
}

#[test]
fn branches_test() {
    let cases = [
        (u3:0, u32:7, u32:7, true), (u3:0, u32:7, u32:8, false), (u3:1, u32:7, u32:8, true),
        (u3:1, u32:7, u32:7, false), (u3:4, u32:0xffffffff, u32:1, true),
        (u3:4, u32:1, u32:0xffffffff, false), (u3:5, u32:1, u32:0xffffffff, true),
        (u3:5, u32:0xffffffff, u32:1, false), (u3:6, u32:1, u32:0xffffffff, true),
        (u3:6, u32:0xffffffff, u32:1, false), (u3:7, u32:0xffffffff, u32:1, true),
        (u3:7, u32:1, u32:0xffffffff, false), (u3:4, u32:7, u32:7, false),
        (u3:5, u32:7, u32:7, true), (u3:6, u32:7, u32:7, false), (u3:7, u32:7, u32:7, true),
    ];
    for (index, ()): (u32, ()) in u32:0..u32:16 {
        let (funct3, a, c, taken) = cases[index];
        let state = operands(a, c);
        let result = rv32i::step(state, b(funct3, u13:0x1ff8), u32:0);
        assert_eq(result.state.pc, if taken { u32:0xff8 } else { u32:0x1004 });
        assert_eq(result.state.regs, state.regs);
        assert_eq(result.state.trapped, false);
        assert_eq(result.memory.valid, false);
    }(())
}

#[test]
fn control_flow_offsets_test() {
    let offsets = u13[4]:[u13:0, u13:0x7fc, u13:0xffc, u13:0x1000];
    for (index, ()): (u32, ()) in u32:0..u32:4 {
        let offset = offsets[index];
        let result = rv32i::step(operands(u32:0, u32:0), b(u3:0, offset), u32:0);
        assert_eq(result.state.pc, u32:0x1000 + ((offset as s13) as u32));
        assert_eq(result.state.trapped, false);
    }(());
    let offsets = u21[6]:[u21:0, u21:0x7fc, u21:0x800, u21:0xffffc, u21:0x100000, u21:0x1ffffc];
    for (index, ()): (u32, ()) in u32:0..u32:6 {
        let offset = offsets[index];
        let result = rv32i::step(rv32i::reset(u32:0x1000), j(u5:3, offset), u32:0);
        assert_eq(result.state.pc, u32:0x1000 + ((offset as s21) as u32));
        assert_eq(result.state.regs[u32:3], u32:0x1004);
        assert_eq(result.state.trapped, false);
    }(())
}

#[test]
fn jalr_and_link_test() {
    let state = operands(u32:0x2005, u32:0);
    let result = rv32i::step(state, i(u7:0x67, u3:0, u5:1, u5:1, u12:0xffc), u32:0);
    assert_eq(result.state.pc, u32:0x2000);  // Clear bit 0 after adding -4.
    assert_eq(result.state.regs[u32:1], u32:0x1004);  // rd == rs1 reads old rs1.
    assert_eq(result.state.trapped, false);
    let result = rv32i::step(state, j(u5:0, u21:8), u32:0);
    assert_eq(result.state.pc, u32:0x1008);
    assert_eq(result.state.regs, state.regs);
}

#[test]
fn load_lanes_test() {
    let state = operands(u32:0x2000, u32:0);
    let word = u32:0x80ff7f01;
    let cases = [
        (u3:0, u12:0, u4:1, u32:1), (u3:0, u12:1, u4:2, u32:0x7f),
        (u3:0, u12:2, u4:4, u32:0xffffffff), (u3:0, u12:3, u4:8, u32:0xffffff80),
        (u3:4, u12:0, u4:1, u32:1), (u3:4, u12:1, u4:2, u32:0x7f), (u3:4, u12:2, u4:4, u32:0xff),
        (u3:4, u12:3, u4:8, u32:0x80), (u3:1, u12:0, u4:3, u32:0x7f01),
        (u3:1, u12:2, u4:12, u32:0xffff80ff), (u3:5, u12:0, u4:3, u32:0x7f01),
        (u3:5, u12:2, u4:12, u32:0x80ff), (u3:2, u12:0, u4:15, word),
    ];
    for (index, ()): (u32, ()) in u32:0..u32:13 {
        let (funct3, offset, mask, expected) = cases[index];
        let instruction = i(u7:0x03, funct3, u5:3, u5:1, offset);
        let request = rv32i::memory_request(state, instruction);
        let result = rv32i::step(state, instruction, word);
        assert_eq(request, result.memory);
        assert_eq(request.valid, true);
        assert_eq(request.write, false);
        assert_eq(request.address, u32:0x2000);
        assert_eq(request.byte_enable, mask);
        assert_eq(result.state.regs[u32:3], expected);
        assert_eq(result.state.pc, u32:0x1004);
        assert_eq(result.state.trapped, false);
    }(())
}

#[test]
fn store_lanes_test() {
    let state = operands(u32:0x2000, u32:0x89abcdef);
    let cases = [
        (u3:0, u12:0, u4:1, u32:0x89abcdef), (u3:0, u12:1, u4:2, u32:0xabcdef00),
        (u3:0, u12:2, u4:4, u32:0xcdef0000), (u3:0, u12:3, u4:8, u32:0xef000000),
        (u3:1, u12:0, u4:3, u32:0x89abcdef), (u3:1, u12:2, u4:12, u32:0xcdef0000),
        (u3:2, u12:0, u4:15, u32:0x89abcdef),
    ];
    for (index, ()): (u32, ()) in u32:0..u32:7 {
        let (funct3, offset, mask, data) = cases[index];
        let result = rv32i::step(state, s(funct3, offset), u32:0);
        assert_eq(result.memory.valid, true);
        assert_eq(result.memory.write, true);
        assert_eq(result.memory.address, u32:0x2000);
        assert_eq(result.memory.byte_enable, mask);
        assert_eq(result.memory.write_data, data);
        assert_eq(result.state.regs, state.regs);
        assert_eq(result.state.pc, u32:0x1004);
        assert_eq(result.state.trapped, false);
    }(())
}

#[test]
fn memory_address_boundaries_test() {
    let state = operands(u32:0, u32:0x12345678);
    let result = rv32i::step(state, s(u3:2, u12:0xffc), u32:0);
    assert_eq(result.memory.address, u32:0xfffffffc);
    assert_eq(result.memory.valid, true);
    let instruction = i(u7:0x03, u3:2, u5:0, u5:1, u12:0xffc);
    let result = rv32i::step(state, instruction, u32:0xffffffff);
    assert_eq(result.memory.address, u32:0xfffffffc);
    assert_eq(result.memory.valid, true);  // A load to x0 still accesses memory.
    assert_eq(result.state.regs, state.regs);
    let state = operands(u32:0xfffffffc, u32:0);
    let result = rv32i::step(state, i(u7:0x03, u3:2, u5:3, u5:1, u12:4), u32:7);
    assert_eq(result.memory.address, u32:0);
    assert_eq(result.state.regs[u32:3], u32:7);
    let result = rv32i::step(operands(u32:0x2000, u32:0), s(u3:2, u12:0x800), u32:0);
    assert_eq(result.memory.address, u32:0x1800);
}

#[test]
fn misaligned_data_test() {
    for (offset, ()): (u32, ()) in u32:1..u32:4 {
        let state = operands(u32:0x2000 + offset, u32:123);
        check_trap(
            state, i(u7:0x03, u3:2, u5:0, u5:1, u12:0), rv32i::LOAD_ADDRESS_MISALIGNED,
            u32:0x2000 + offset);
        check_trap(state, s(u3:2, u12:0), rv32i::STORE_ADDRESS_MISALIGNED, u32:0x2000 + offset);
        if offset != u32:2 {
            check_trap(
                state, i(u7:0x03, u3:1, u5:3, u5:1, u12:0), rv32i::LOAD_ADDRESS_MISALIGNED,
                u32:0x2000 + offset);
            check_trap(
                state, i(u7:0x03, u3:5, u5:3, u5:1, u12:0), rv32i::LOAD_ADDRESS_MISALIGNED,
                u32:0x2000 + offset);
            check_trap(state, s(u3:1, u12:0), rv32i::STORE_ADDRESS_MISALIGNED, u32:0x2000 + offset);
        } else {
            ()
        };
    }(())
}

#[test]
fn misaligned_control_flow_test() {
    let state = operands(u32:0x2002, u32:0x2002);
    check_trap(state, j(u5:1, u21:2), rv32i::INSTRUCTION_ADDRESS_MISALIGNED, u32:0x1002);
    check_trap(
        state, i(u7:0x67, u3:0, u5:1, u5:1, u12:1), rv32i::INSTRUCTION_ADDRESS_MISALIGNED,
        u32:0x2002);
    check_trap(state, b(u3:0, u13:2), rv32i::INSTRUCTION_ADDRESS_MISALIGNED, u32:0x1002);
    let result = rv32i::step(state, b(u3:1, u13:2), u32:0);
    assert_eq(result.state.trapped, false);  // Untaken branch must not trap.
    assert_eq(result.state.pc, u32:0x1004);
    check_trap(rv32i::reset(u32:2), s(u3:2, u12:0), rv32i::INSTRUCTION_ADDRESS_MISALIGNED, u32:2);
}

#[test]
fn illegal_encodings_test() {
    let state = operands(u32:0, u32:0);
    let instructions = [
        u32:0, u32:0xffffffff, u32:0x00000001, // Unknown / compressed.
        i(u7:0x03, u3:3, u5:3, u5:1, u12:0), i(u7:0x03, u3:6, u5:3, u5:1, u12:0),
        i(u7:0x03, u3:7, u5:3, u5:1, u12:0), s(u3:3, u12:0), s(u3:4, u12:0), s(u3:5, u12:0),
        s(u3:6, u12:0), s(u3:7, u12:0), b(u3:2, u13:0), b(u3:3, u13:0),
        i(u7:0x67, u3:1, u5:3, u5:1, u12:0), u32:0x0000100f, // FENCE.I (Zifencei)
        u32:0x300091f3, // CSRRW (Zicsr)
        u32:0x30200073, // MRET
        u32:0x00200073, u32:0x000000f3, u32:0x00008073,
    ];
    for (index, ()): (u32, ()) in u32:0..u32:20 {
        let instruction = instructions[index];
        check_trap(state, instruction, rv32i::ILLEGAL_INSTRUCTION, instruction);
    }(());
    for (funct3, ()): (u32, ()) in u32:0..u32:8 {
        let instruction = r(u7:1, funct3 as u3);  // All RV32M operations.
        check_trap(state, instruction, rv32i::ILLEGAL_INSTRUCTION, instruction);
        if funct3 != u32:0 && funct3 != u32:5 {
            let instruction = r(u7:0x20, funct3 as u3);
            check_trap(state, instruction, rv32i::ILLEGAL_INSTRUCTION, instruction);
        } else {
            ()
        };
    }(());
    let instructions = [
        i(u7:0x13, u3:1, u5:3, u5:1, u12:0x400), i(u7:0x13, u3:1, u5:3, u5:1, u12:0x020),
        i(u7:0x13, u3:5, u5:3, u5:1, u12:0x020), i(u7:0x13, u3:5, u5:3, u5:1, u12:0x420),
    ];
    for (index, ()): (u32, ()) in u32:0..u32:4 {
        let instruction = instructions[index];
        check_trap(state, instruction, rv32i::ILLEGAL_INSTRUCTION, instruction);
    }(())
}

#[test]
fn fence_and_environment_test() {
    let state = operands(u32:1, u32:2);
    let instructions = [u32:0x0ff0000f, u32:0x8330000f, u32:0xfff0808f];
    for (index, ()): (u32, ()) in u32:0..u32:3 {
        let result = rv32i::step(state, instructions[index], u32:0);
        assert_eq(result.state.trapped, false);
        assert_eq(result.state.pc, u32:0x1004);
        assert_eq(result.state.regs, state.regs);
        assert_eq(result.memory.valid, false);
    }(());
    check_trap(state, u32:0x00000073, rv32i::ECALL, u32:0);
    check_trap(state, u32:0x00100073, rv32i::BREAKPOINT, u32:0x1000);
}

#[test]
fn sum_program_test() {
    // Sum 1..5, store the result, reload it, then halt with EBREAK.
    let rom = u32[9]:[
        u32:0x00500093, // addi x1, x0, 5
        u32:0x00000113, // addi x2, x0, 0
        u32:0x00110133, // add x2, x2, x1
        u32:0xfff08093, // addi x1, x1, -1
        u32:0xfe009ce3, // bne x1, x0, -8
        u32:0x10000193, // addi x3, x0, 256
        u32:0x0021a023, // sw x2, 0(x3)
        u32:0x0001a203, // lw x4, 0(x3)
        u32:0x00100073, // ebreak
    ];
    let (state, memory, stores) =
        for (_, (state, memory, stores)): (u32, (rv32i::State, u32, u32)) in u32:0..u32:24 {
            assert!(state.pc >> u32:2 < u32:9, "pc_outside_rom");
            let instruction = rom[state.pc >> u32:2];
            let request = rv32i::memory_request(state, instruction);
            if request.valid {
                assert_eq(request.address, u32:0x100);
                assert_eq(request.byte_enable, u4:15);
            } else {
                ()
            };
            let result = rv32i::step(state, instruction, memory);
            assert_eq(result.memory, request);
            let store = request.valid && request.write;
            (result.state, if store { request.write_data } else { memory }, stores + store as u32)
        }((rv32i::reset(u32:0), u32:0, u32:0));
    assert_eq(memory, u32:15);
    assert_eq(stores, u32:1);
    assert_eq(state.regs[u32:1], u32:0);
    assert_eq(state.regs[u32:2], u32:15);
    assert_eq(state.regs[u32:4], u32:15);
    assert_eq(state.regs[u32:0], u32:0);
    assert_eq(state.pc, u32:32);
    assert_eq(state.trapped, true);
    assert_eq(state.trap_cause, rv32i::BREAKPOINT);
}
