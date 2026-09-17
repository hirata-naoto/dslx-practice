// RV32I, little-endian, single-instruction state transition.
pub const INSTRUCTION_ADDRESS_MISALIGNED = u32:0;
pub const ILLEGAL_INSTRUCTION = u32:2;
pub const BREAKPOINT = u32:3;
pub const LOAD_ADDRESS_MISALIGNED = u32:4;
pub const STORE_ADDRESS_MISALIGNED = u32:6;
pub const ECALL = u32:11;  // Machine-mode environment call; no privileged ISA.

pub struct State { pc: u32, regs: u32[32], trapped: bool, trap_cause: u32, trap_value: u32 }

pub struct MemoryRequest {
    valid: bool,
    write: bool,
    address: u32,  // Word-aligned byte address.
    write_data: u32,
    byte_enable: u4,  // Bit 0 selects the least-significant byte.
}

pub struct StepResult { state: State, memory: MemoryRequest }

const NO_MEMORY = MemoryRequest {
    valid: false,
    write: false,
    address: u32:0,
    write_data: u32:0,
    byte_enable: u4:0,
};

struct Effects {
    next_pc: u32,
    write_rd: bool,
    value: u32,
    memory: MemoryRequest,
    trap: bool,
    cause: u32,
    trap_value: u32,
}

pub fn reset(entry_pc: u32) -> State {
    State {
        pc: entry_pc,
        regs: u32[32]:[u32:0, ...],
        trapped: false,
        trap_cause: u32:0,
        trap_value: u32:0,
    }
}

fn read_reg(state: State, index: u5) -> u32 {
    if index == u5:0 { u32:0 } else { state.regs[index] }
}

fn imm_i(instruction: u32) -> u32 { (instruction[20+:u12] as s12) as u32 }

fn imm_s(instruction: u32) -> u32 { ((instruction[25+:u7] ++ instruction[7+:u5]) as s12) as u32 }

fn imm_b(instruction: u32) -> u32 {
    ((instruction[31+:u1] ++ instruction[7+:u1] ++ instruction[25+:u6] ++ instruction[8+:u4] ++ u1:0) as
    s13) as
    u32
}

fn imm_j(instruction: u32) -> u32 {
    ((instruction[31+:u1] ++ instruction[12+:u8] ++ instruction[20+:u1] ++ instruction[21+:u10] ++
    u1:0) as
    s21) as
    u32
}

fn fault(effects: Effects, cause: u32, value: u32) -> Effects {
    Effects { trap: true, cause, trap_value: value, ..effects }
}

fn jump(effects: Effects, target: u32) -> Effects {
    if target & u32:3 != u32:0 {
        fault(effects, INSTRUCTION_ADDRESS_MISALIGNED, target)
    } else {
        Effects { next_pc: target, ..effects }
    }
}

fn decode(state: State, instruction: u32, load_data: u32) -> Effects {
    let opcode = instruction[0+:u7];
    let funct3 = instruction[12+:u3];
    let funct7 = instruction[25+:u7];
    let a = read_reg(state, instruction[15+:u5]);
    let b = read_reg(state, instruction[20+:u5]);
    let immediate = imm_i(instruction);
    let sequential = state.pc + u32:4;
    let base = Effects {
        next_pc: sequential,
        write_rd: false,
        value: u32:0,
        memory: NO_MEMORY,
        trap: false,
        cause: u32:0,
        trap_value: u32:0,
    };
    let illegal = fault(base, ILLEGAL_INSTRUCTION, instruction);
    match opcode {
        u7:0x37 => Effects { write_rd: true, value: instruction & u32:0xfffff000, ..base },
        u7:0x17 => Effects {
            // AUIPC
            write_rd: true,
            value: state.pc + (instruction & u32:0xfffff000),
            ..base
        },
        u7:0x6f => jump(
            Effects { write_rd: true, value: sequential, ..base }, state.pc + imm_j(instruction)),
        u7:0x67 => {
            // JALR
            if funct3 != u3:0 {
                illegal
            } else {
                jump(
                    Effects { write_rd: true, value: sequential, ..base },
                    (a + immediate) & u32:0xfffffffe)
            }
        },
        u7:0x63 => {
            // Conditional branches.
            let (valid, taken) = match funct3 {
                u3:0 => (true, a == b),
                u3:1 => (true, a != b),
                u3:4 => (true, (a as s32) < (b as s32)),
                u3:5 => (true, (a as s32) >= (b as s32)),
                u3:6 => (true, a < b),
                u3:7 => (true, a >= b),
                _ => (false, false),
            };
            if !valid {
                illegal
            } else if taken {
                jump(base, state.pc + imm_b(instruction))
            } else {
                base
            }
        },
        u7:0x13 => {
            // Register-immediate ALU.
            let shamt = instruction[20+:u5];
            let (valid, value) = match funct3 {
                u3:0 => (true, a + immediate),
                u3:2 => (true, ((a as s32) < (immediate as s32)) as u32),
                u3:3 => (true, (a < immediate) as u32),
                u3:4 => (true, a ^ immediate),
                u3:6 => (true, a | immediate),
                u3:7 => (true, a & immediate),
                u3:1 => (funct7 == u7:0, a << shamt),
                u3:5 => {
                    (
                        funct7 == u7:0 || funct7 == u7:0x20,
                        if funct7 == u7:0x20 { ((a as s32) >> shamt) as u32 } else { a >> shamt },
                    )
                    },
                _ => (false, u32:0),
            };
            if valid { Effects { write_rd: true, value, ..base } } else { illegal }
        },
        u7:0x33 => {
            // Register-register ALU; M-extension encodings are rejected.
            let shamt = b as u5;
            let (valid, value) = match funct3 {
                u3:0 => {
                    (
                        funct7 == u7:0 || funct7 == u7:0x20,
                        if funct7 == u7:0x20 { a - b } else { a + b },
                    )
                    },
                u3:1 => (funct7 == u7:0, a << shamt),
                u3:2 => (funct7 == u7:0, ((a as s32) < (b as s32)) as u32),
                u3:3 => (funct7 == u7:0, (a < b) as u32),
                u3:4 => (funct7 == u7:0, a ^ b),
                u3:5 => {
                    (
                        funct7 == u7:0 || funct7 == u7:0x20,
                        if funct7 == u7:0x20 { ((a as s32) >> shamt) as u32 } else { a >> shamt },
                    )
                    },
                u3:6 => (funct7 == u7:0, a | b),
                u3:7 => (funct7 == u7:0, a & b),
                _ => (false, u32:0),
            };
            if valid { Effects { write_rd: true, value, ..base } } else { illegal }
        },
        u7:0x03 => {
            // Loads from an aligned little-endian memory word.
            let address = a + immediate;
            let offset = address as u2;
            let shifted = load_data >> ((offset as u5) << u5:3);
            let (valid, misaligned, mask, value) = match funct3 {
                u3:0 => (true, false, u4:1, (shifted as s8) as u32),
                u3:1 => (true, address[0+:u1] != u1:0, u4:3, (shifted as s16) as u32),
                u3:2 => (true, offset != u2:0, u4:15, load_data),
                u3:4 => (true, false, u4:1, (shifted as u8) as u32),
                u3:5 => (true, address[0+:u1] != u1:0, u4:3, (shifted as u16) as u32),
                _ => (false, false, u4:0, u32:0),
            };
            if !valid {
                illegal
            } else if misaligned {
                fault(base, LOAD_ADDRESS_MISALIGNED, address)
            } else {
                Effects {
                    write_rd: true,
                    value,
                    memory: MemoryRequest {
                        valid: true,
                        address: address & u32:0xfffffffc,
                        byte_enable: mask << offset,
                        ..NO_MEMORY
                    },
                    ..base
                }
            }
        },
        u7:0x23 => {
            // Stores use byte enables; no read-modify-write is required.
            let address = a + imm_s(instruction);
            let offset = address as u2;
            let (valid, misaligned, mask) = match funct3 {
                u3:0 => (true, false, u4:1),
                u3:1 => (true, address[0+:u1] != u1:0, u4:3),
                u3:2 => (true, offset != u2:0, u4:15),
                _ => (false, false, u4:0),
            };
            if !valid {
                illegal
            } else if misaligned {
                fault(base, STORE_ADDRESS_MISALIGNED, address)
            } else {
                Effects {
                    memory: MemoryRequest {
                        valid: true,
                        write: true,
                        address: address & u32:0xfffffffc,
                        write_data: b << ((offset as u5) << u5:3),
                        byte_enable: mask << offset,
                    },
                    ..base
                }
            }
        },
        u7:0x0f => {
            // FENCE is a no-op on this blocking, in-order interface.
            if funct3 == u3:0 { base } else { illegal }
        },
        u7:0x73 => {
            match instruction {
                u32:0x00000073 => fault(base, ECALL, u32:0),
                u32:0x00100073 => fault(base, BREAKPOINT, state.pc),
                _ => illegal,
            }
            },
        _ => illegal,
    }
}

// The caller commits the returned state and store together, once per instruction.
pub fn step(state: State, instruction: u32, load_data: u32) -> StepResult {
    let effects = decode(state, instruction, load_data);
    let effects = if state.pc & u32:3 != u32:0 {
        fault(effects, INSTRUCTION_ADDRESS_MISALIGNED, state.pc)
    } else {
        effects
    };
    if state.trapped {
        StepResult { state, memory: NO_MEMORY }
    } else if effects.trap {
        StepResult {
            state: State {
                trapped: true,
                trap_cause: effects.cause,
                trap_value: effects.trap_value,
                ..state
            },
            memory: NO_MEMORY,
        }
    } else {
        let rd = instruction[7+:u5];
        let regs = if effects.write_rd && rd != u5:0 {
            update(state.regs, rd, effects.value)
        } else {
            state.regs
        };
        StepResult {
            state: State { pc: effects.next_pc, regs: update(regs, u5:0, u32:0), ..state },
            memory: effects.memory,
        }
    }
}

// Query before reading memory; this request never depends on the load response.
pub fn memory_request(state: State, instruction: u32) -> MemoryRequest {
    step(state, instruction, u32:0).memory
}
