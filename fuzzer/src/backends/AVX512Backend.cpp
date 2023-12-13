#include <iostream>

#include "backends/AVX512Backend.hpp"
#include "spdlog/spdlog.h"
#include "strategies/SimpleFuzzingStrategies.hpp"

void runInstruction(State& state, std::uint32_t instruction, uint8_t* memory) {
    // Step 1: Figure out instruction length
    // Instructions come in 16 bit increments
    // 16 bit: lowest two bits != 11
    // 32 bit: lowest two bits == 11, next three bits != 111
    // 48 bit: ends in 011111
    // 64 bit: ends in 0111111
    // Larger size instructions don't need to be supported, but they
    // all end in some amount of 1s and have other features
    // Note that this means instruction of all 0s is ILLEGAL
    // All 1s is also ILLEGAL

    // Since we're gonna be doing RV32 only, we're only gonna support
    // the 32 and 16 bit instructions
    // Because of this, I'm electing to always just load 32 bits
    // when reading for the next instruction. Note also that these 16 bit
    // instructions will break alignment. But yeah, we do have to be careful
    // that we don't read out of bounds when reading literally the last instruction
    // if it happens to be 16 bits. Therefore, so that we can always read 32 bits,
    // it makes sense to pad the program if the last instruction is 16 bits.

    // Since we're emulating, we can't use the same hardware optimizations that the ISA
    // was designed to make easy (I think) because we get all the bits from the memory
    // load at the same time.

    // Normally this is the destination register, but in S and B type instructions
    // where there is not destination register these same bits communicate parts of an immediate
    // value. We always need to look at these bits as a unit no matter what
    const auto rd = (instruction >> 7) & 0x1f; // Bits 11 to 7

    const auto opcode = instruction & 0x7f;

    switch (opcode) {
        case 0x37: // lui
        {
            // We don't need to load it into low bits, then reshift it into high bits... can just read the bits in
            // place! Lower bits are filled with zeros according to standard
            state.x[rd] = instruction & 0xfffff000;
            state.pc += 4;
            break;
        }
        case 0x17: // auipc
        {
            // Mirrors the above, but result is imm + offset from pc
            state.x[rd] = state.pc + (instruction & 0xfffff000);
            state.pc += 4;
            break;
        }
        case 0x6f: // jal
        {
            // This part seems like it would be much nicer in hardware...
            // The bit order is very strange, [20|10:1|11|19:12]
            // so 31 -> 20 == 11, 30 -> 10 == 20, 20 -> 11 == 9, 19 -> 19 == 0
            // Since right shift doing sign extension is implementation dependent, and
            // this wants sign extension, we do it manually...
            // also, yes, this is correct -- it doesn't set lsb
            std::uint32_t imm = ((instruction & (1u << 31)) >> 11) | ((instruction & 0x7fe00000) >> 20) |
                                ((instruction & 0x00100000) >> 9) | (instruction & 0x000ff000);
            state.x[rd] = state.pc + 4;
            // Two cases: either our machine does sign extension and this is redundant, or it defaults to 0 extension
            // and we need this No machine will default to 1 extension so we're all good
            if (instruction & (1u << 31)) {
                imm |= 0xffe00000;
            }
            state.pc += imm;
            break;
        }
        case 0x67: // jalr
        {
            // This wants us to use a temporary in case the destination register and source register are the same
            std::uint32_t rs1  = (instruction >> 15) & 0x1f;
            std::uint32_t temp = state.pc + 4;
            // Oh yeah we have to sign this one again, but bits are nicer, [11:0], so 31 -> 11 == 20
            std::uint32_t imm = (instruction >> 20);
            if (instruction & (1u << 31)) {
                imm |= 0xfffff000;
            }
            state.pc    = (state.x[rs1] + imm) & ~1;
            state.x[rd] = temp;
            break;
        }
        case 0x63: // beq, bne, blt, bge, bltu, bgeu
        {
            std::uint32_t rs1 = (instruction >> 15) & 0x1f;
            std::uint32_t rs2 = (instruction >> 20) & 0x1f;
            // The immediate for jump offset is cursed again, high bits are [12|10:5] and then rd has [4:1|11]
            // 31 -> 12 == 19, 30 -> 10 == 20, 4 -> 4 == 0, 0 -> 11 == -11
            // we have to sign extend again as well
            std::uint32_t imm = ((instruction & (1u << 31)) >> 19) | ((instruction & 0x7e000000) >> 20) | (rd & 0x1e) |
                                ((rd & 0x1) << 11);
            if (instruction & (1u << 31)) {
                imm |= 0xffffe000;
            }
            // funct3 (bits 14:12) determines which of the comparisons to do
            switch ((instruction >> 12) & 0x7) {
                case 0x0: // beq
                {
                    if (state.x[rs1] == state.x[rs2]) {
                        state.pc += imm;
                    }
                    break;
                }
                case 0x1: // bne
                {
                    if (state.x[rs1] != state.x[rs2]) {
                        state.pc += imm;
                    }
                    break;
                }
                case 0x4: // blt (this is signed)
                {
                    if (static_cast<int32_t>(state.x[rs1]) < static_cast<int32_t>(state.x[rs2])) {
                        state.pc += imm;
                    }
                    break;
                }
                case 0x5: // bge (this is signed)
                {
                    if (static_cast<int32_t>(state.x[rs1]) >= static_cast<int32_t>(state.x[rs2])) {
                        state.pc += imm;
                    }
                    break;
                }
                case 0x6: // bltu (this is unsigned)
                {
                    if (static_cast<std::uint32_t>(state.x[rs1]) < static_cast<std::uint32_t>(state.x[rs2])) {
                        state.pc += imm;
                    }
                    break;
                }
                case 0x7: // bgeu (this is unsigned)
                {
                    if (static_cast<std::uint32_t>(state.x[rs1]) >= static_cast<std::uint32_t>(state.x[rs2])) {
                        state.pc += imm;
                    }
                    break;
                }
                    // TODO: handle if it isn't one of these? Set trap maybe?
            }
            state.pc += 4;
            break;
        }
        case 0x03: // lb, lh, lw, lbu, lhu
        {
            std::uint32_t rs1 = (instruction >> 15) & 0x1f;
            // Same format as jalr
            std::uint32_t imm = (instruction >> 20);
            if (instruction & (1u << 31)) {
                imm |= 0xfffff000;
            }
            // funct3 again
            switch ((instruction >> 12) & 0x7) {
                case 0x0: // lb
                {
                    uint8_t loaded = *(memory + (state.x[rs1] + imm));
                    state.x[rd]    = (loaded & (1u << 7)) ? loaded | 0xffffff00 : loaded;
                    break;
                }
                case 0x1: // lh
                {
                    uint16_t loaded = *reinterpret_cast<uint16_t*>(memory + (state.x[rs1] + imm));
                    state.x[rd]     = (loaded & (1u << 15)) ? loaded | 0xffff0000 : loaded;
                    break;
                }
                case 0x2: // lw
                {
                    state.x[rd] = *reinterpret_cast<std::uint32_t*>(memory + (state.x[rs1] + imm));
                    break;
                }
                case 0x4: // lbu
                {
                    uint8_t loaded = *(memory + (state.x[rs1] + imm));
                    state.x[rd]    = loaded & 0x000000ff;
                    break;
                }
                case 0x5: // lhu
                {
                    uint16_t loaded = *reinterpret_cast<uint16_t*>(memory + (state.x[rs1] + imm));
                    state.x[rd]     = loaded & 0x0000ffff;
                    break;
                }
                    // TODO: handle if it isn't one of these? Set trap maybe?
            }
            state.pc += 4;
            break;
        }
        case 0x23: // sb, sh, sw
        {
            // In this one, we reuse rs1 as the memory location (well plus the immediate offset) and we use rs2 as the
            // source This means the immediate is split up again
            std::uint32_t rs1 = (instruction >> 15) & 0x1f;
            std::uint32_t rs2 = (instruction >> 20) & 0x1f;
            std::uint32_t imm = ((instruction & 0xfe000000) >> 20) | rd;
            if (instruction & (1u << 31)) {
                imm |= 0xfffff000;
            }
            switch ((instruction >> 12) & 0x7) {
                case 0x0: // sb
                {
                    *(memory + (state.x[rs1] + imm)) = state.x[rs2];
                    break;
                }
                case 0x1: // sh
                {
                    *reinterpret_cast<uint16_t*>(memory + (state.x[rs1] + imm)) = state.x[rs2];
                    break;
                }
                case 0x2: // sw
                {
                    *reinterpret_cast<std::uint32_t*>(memory + (state.x[rs1] + imm)) = state.x[rs2];
                    break;
                }
                    // TODO: handle default?
            }
            state.pc += 4;
            break;
        }
        case 0x13: // addi, slti, sltiu, xori, ori, andi, slli, srli, srai
        {
            std::uint32_t rs1 = (instruction >> 15) & 0x1f;
            std::uint32_t imm = (instruction >> 20);
            if (instruction & (1u << 31)) {
                imm |= 0xfffff000;
            }
            // funct3 again
            switch ((instruction >> 12) & 0x7) {
                case 0x0: // addi
                {
                    state.x[rd] = state.x[rs1] + imm;
                    break;
                }
                case 0x2: // slti
                {
                    // I'm pretty sure c standard says true statements always get set to 1 but just to make
                    // it clear
                    state.x[rd] = (static_cast<int32_t>(state.x[rs1]) < static_cast<int32_t>(imm)) ? 1 : 0;
                    break;
                }
                case 0x3: // sltiu
                {
                    state.x[rd] = (static_cast<std::uint32_t>(state.x[rs1]) < static_cast<std::uint32_t>(imm)) ? 1 : 0;
                    break;
                }
                case 0x4: // xori
                {
                    state.x[rd] = state.x[rs1] ^ imm;
                    break;
                }
                case 0x6: // ori
                {
                    state.x[rd] = state.x[rs1] | imm;
                    break;
                }
                case 0x7: // andi
                {
                    state.x[rd] = state.x[rs1] & imm;
                    break;
                }
                case 0x1: // slli
                {
                    // TODO: these instructions only use the lowest 5 bits of imm, and
                    // the standard says the high bits are all 0 (or 1 of them is 1 for srai)
                    // I assume it should be illegal operation if that's not the case?
                    state.x[rd] = state.x[rs1] << (imm & 0x1f);
                    break;
                }
                case 0x5: // srli, srai are differentiated by a 1 in the 30th bit
                {
                    std::uint32_t shamt = imm & 0x1f;
                    if (instruction & (1u << 30)) {
                        state.x[rd] = static_cast<int32_t>(state.x[rs1]) >> shamt;
                        if ((state.x[rs1] & (1u << 31)) && shamt) {
                            // Bit shifts by 32 are undefined by c standard so we actually can't use this which is
                            // extremely cringe because it won't work on 0 shift... so we just special case it.
                            state.x[rd] |= ~0 << (32 - shamt);
                        }
                    } else {
                        // Don't do sign extension (don't need to do anything special here)
                        state.x[rd] = static_cast<std::uint32_t>(state.x[rs1]) >> shamt;
                    }
                    break;
                }
            }
            state.pc += 4;
            break;
        }
        case 0x33: // add, sub, sll, slt, sltu, xor, srl, sra, or, and
        {
            const auto rs1 = (instruction >> 15) & 0x1f;
            const auto rs2 = (instruction >> 20) & 0x1f;
            switch ((instruction >> 12) & 0x7) {
                case 0x0: // add, sub are differentiated again by funct7 (only 1 bit of it tho), inst bit 30
                {
                    // Oh and arithmetic overflow is ignored (aka we don't care, and you know what, just use what our
                    // implementation does) This isn't 122
                    if (instruction & (1u << 30)) // add
                    {
                        state.x[rd] = state.x[rs1] + state.x[rs2];
                    } else // sub
                    {
                        state.x[rd] = state.x[rs1] - state.x[rs2];
                    }
                    break;
                }
                case 0x1: // sll
                {
                    // This only cares about the lower 5 bits
                    state.x[rd] = state.x[rs1] << (state.x[rs2] & 0x1f);
                    break;
                }
                case 0x2: // slt
                {
                    state.x[rd] = (static_cast<int32_t>(state.x[rs1]) < static_cast<int32_t>(state.x[rs2])) ? 1 : 0;
                    break;
                }
                case 0x3: // sltu
                {
                    state.x[rd] = (static_cast<std::uint32_t>(state.x[rs1]) < static_cast<std::uint32_t>(state.x[rs2]))
                                          ? 1
                                          : 0;
                    break;
                }
                case 0x4: // xor
                {
                    state.x[rd] = state.x[rs1] ^ state.x[rs2];
                    break;
                }
                case 0x5: // srl, sra
                {
                    std::uint32_t shamt = state.x[rs2] & 0x1f;
                    if (instruction & (1u << 30)) {
                        state.x[rd] = static_cast<int32_t>(state.x[rs1]) >> shamt;
                        if (state.x[rs1] & (1u << 31) && shamt) {
                            state.x[rd] |= ~0 << (32 - shamt);
                        }
                    } else {
                        state.x[rd] = static_cast<std::uint32_t>(state.x[rs1]) >> shamt;
                    }
                    break;
                }
                case 0x6: // or
                {
                    state.x[rd] = state.x[rs1] | state.x[rs2];
                    break;
                }
                case 0x7: // and
                {
                    state.x[rd] = state.x[rs1] & state.x[rs2];
                    break;
                }
            }
            state.pc += 4;
            break;
        }
        case 0x0f: // fence, fence.i
        {
            // TODO: do something other than nop?
            state.pc += 4;
            break;
        }
        case 0x73: // ecall, ebreak, csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
        {
            // TODO: do something other than nop?
            state.pc += 4;
            break;
        }
        default: {
            std::cerr << "Encountered unknown opcode!" << std::endl;
        }
    }

    // We could have written to 0, so just put it back to 0
    if (rd == 0) {
        state.x[rd] = 0;
    }
}

void simdRunInstruction(AVX512State& state, MachineWord instruction, uint8_t* memory) {}

void AVX512Backend::run() {
    while (true) {
        auto instruction = *reinterpret_cast<std::uint32_t*>(program + state.pc);
        printf("executing instruction: %x\n", instruction);
        runInstruction(state, instruction, memory);
        printf("pc = %x\n", state.pc);
        if (state.pc == DONE_ADDRESS) {
            break;
        }
    }

    std::uint32_t const BYTES_PER_LINE = 4 * 4;
    for (std::uint32_t i = 0; i < MEMORY_SIZE; i += 4) {
        if (i % BYTES_PER_LINE == 0) {
            printf("\n");
        }
        printf("%08x ", *reinterpret_cast<std::uint32_t*>(memory + i));
    }
    printf("\n");
}

void AVX512Backend::emitInstruction(const Instruction& instruction) {
    thread_local uint8_t scratch512b1[LANE_COUNT]{};
    thread_local uint8_t scratch512b2[LANE_COUNT]{};
    thread_local uint8_t scratch512b3[LANE_COUNT]{};
    thread_local std::int64_t instructionNumber{-1};
    const auto opcode = static_cast<Opcode>(instruction.opcode());

    instructionNumber++;

    // TODO: Think harder about memory layout + masking :(
    // TODO: think also about PC

    switch (opcode) {
        case Opcode::LUI: { // OK
            assembler.mov(EAX, instruction.raw & 0xfffff000);
            assembler.vpbroadcastd(asmjit::x86::zmm(instruction.rd()), EAX);
            break;
        }
        case Opcode::AUIPC: { // OK
            const auto dst = asmjit::x86::zmm(instruction.rd());

            // tmp = &pc
            assembler.mov(TMP_SCALAR_REGISTER, &state.pc);

            // dst = *tmp = pc
            assembler.vmovdqa(dst, asmjit::x86::ptr(TMP_SCALAR_REGISTER)); // rd = pc

            // eax = imm
            assembler.mov(EAX, instruction.raw & 0xfffff000);

            // tmp = eax = imm
            assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);

            // dst = dst + tmp = pc + imm
            assembler.vpaddd(dst, dst, TMP_DATA_REGISTER);
            break;
        }
        case Opcode::JAL: { // TODO: Instrument instrument instrument (OK...ish)
            const auto imm = (((instruction.raw & (1u << 31)) >> 11) | ((instruction.raw & 0x7fe00000) >> 20) |
                              ((instruction.raw & 0x00100000) >> 9) | (instruction.raw & 0x000ff000)) |
                             (instruction.isHighestBitSet() ? 0xffe00000 : 0);

            const auto dst = asmjit::x86::zmm(instruction.rd());

            assembler.mov(TMP_SCALAR_REGISTER, &state.pc);
            assembler.vmovdqa(asmjit::x86::zmm(instruction.rd()), asmjit::x86::ptr(TMP_SCALAR_REGISTER)); // rd = pc
            assembler.mov(EAX, imm);
            assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
            assembler.vpaddd(dst, dst, TMP_DATA_REGISTER); // + imm
            assembler.vmovdqa(asmjit::x86::ptr(TMP_SCALAR_REGISTER), dst);
            assembler.vpsubb(dst, dst, TMP_DATA_REGISTER); // - imm = pd
            assembler.mov(EAX, 4);
            assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
            assembler.vpaddd(dst, dst, TMP_DATA_REGISTER); // + 4

            // TODO: the actual jump part
            // Make sure not to do things incorrectly when it comes to updating pc after twice

            goto resetZeroRegister;
            break;
        }
        case Opcode::JALR: { // TODO: Instrument instrument instrument (OK...ish)
                             // TODO: rd = PC+4; PC = rs1 + imm
            const auto imm = instruction.imm() | (instruction.isHighestBitSet() ? 0xfffff000 : 0);
            const auto dst = asmjit::x86::zmm(instruction.rd());
            const auto src = asmjit::x86::zmm(instruction.rs1());

            assembler.mov(TMP_SCALAR_REGISTER, &state.pc);

            assembler.vmovdqa(asmjit::x86::zmm(instruction.rd()), asmjit::x86::ptr(TMP_SCALAR_REGISTER)); // rd = pc
            assembler.mov(EAX, 4);
            assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
            assembler.vpaddd(dst, dst, TMP_DATA_REGISTER); // rd = pc + 4

            assembler.mov(EAX, imm);
            assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);                              // tmp = imm
            assembler.vpaddd(TMP_DATA_REGISTER, TMP_DATA_REGISTER, src);                 // tmp = rs1 + imm
            assembler.vmovdqa(asmjit::x86::ptr(TMP_SCALAR_REGISTER), TMP_DATA_REGISTER); // pc = tmp = rs1 + imm

            // TODO: Not sure how important the &1 ends up being...
            // TODO: the actual jump part
            goto resetZeroRegister;
            break;
        }
        case Opcode::BRANCH: { // TODO: Instrument instrument instrument
            const auto fn3 = instruction.funct3();
            const auto rs1 = asmjit::x86::zmm(instruction.rs1());
            const auto rs2 = asmjit::x86::zmm(instruction.rs2());
            const auto rd  = instruction.rd();

            // AJAX:
            // The immediate for jump offset is cursed again, high bits are [12|10:5] and then rd has [4:1|11]
            // 31 -> 12 == 19, 30 -> 10 == 20, 4 -> 4 == 0, 0 -> 11 == -11
            // we have to sign extend again as well

            const auto imm = (((instruction.raw & (1u << 31)) >> 19) | ((instruction.raw & 0x7e000000) >> 20) |
                              (rd & 0x1e) | ((rd & 0x1) << 11)) |
                             (instruction.isHighestBitSet() ? 0xffffe000 : 0);

            // funct3 (bits 14:12) determines which of the comparisons to do
            switch (fn3) {
                case 0x0: { // BEQ
                    assembler.vpcmpd(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kEQ_OQ);
                    break;
                }
                case 0x1: { // BNE
                    assembler.vpcmpd(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kNEQ_OQ);
                    break;
                }
                case 0x4: { // BLT (this is signed)
                    assembler.vpcmpd(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kLT_OQ);
                    break;
                }
                case 0x5: { // BGE (this is signed)
                    assembler.vpcmpd(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kGE_OQ);
                    break;
                }
                case 0x6: { // BLTU (this is unsigned)
                    assembler.vpcmpud(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kLT_OQ);
                    break;
                }
                case 0x7: { // bgeu (this is unsigned)
                    assembler.vpcmpud(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kGE_OQ);
                    break;
                }
                default: {
                    spdlog::error("In an invalid branch operation case: {}", fn3);
                    break;
                }
            }

            // backup zmm1 (spill)
            assembler.mov(RAX, &scratch512b1);
            assembler.vmovdqu64(asmjit::x86::ptr(RAX), asmjit::x86::zmm1);

            // overwrite zmm1 w/pc
            assembler.mov(TMP_SCALAR_REGISTER, &state.pc);
            assembler.vmovdqa32(asmjit::x86::zmm1, asmjit::x86::ptr(TMP_SCALAR_REGISTER));

            // load imm, broadcast
            assembler.mov(TMP_SCALAR_REGISTER, imm);
            assembler.vpbroadcastd(TMP_DATA_REGISTER, TMP_SCALAR_REGISTER);

            // compute new pcs
            assembler.vpaddd(asmjit::x86::zmm1, asmjit::x86::zmm1, TMP_DATA_REGISTER);

            // update pc
            assembler.mov(RAX, &state.pc);
            assembler.k(TMP_MASK_REGISTER).vmovdqa32(asmjit::x86::ptr(RAX), asmjit::x86::zmm1);

            // restore from spill
            assembler.vmovdqu64(asmjit::x86::zmm1, asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b1)));
            break;
        }
        case Opcode::LOAD: { // TODO: Instrument instrument instrument (and masks)

            const auto imm = instruction.imm() | (instruction.isHighestBitSet() ? 0xfffff000 : 0);
            const auto fn3 = instruction.funct3();
            const auto rs1 = asmjit::x86::zmm(instruction.rs1());
            const auto dst = asmjit::x86::zmm(instruction.rd());

            // we have to spill
            // TODO: Should probably be EAX, not RAX. (TODO: fixed but check for bugs)
            // assembler.sub(RSP, 64);
            // assembler.vmovdqu64(asmjit::x86::ptr(asmjit::x86::rsp), TMP_DATA_REGISTER);
            //
            // assembler.vmovdqu32(TMP_DATA_REGISTER, asmjit::x86::ptr(EAX));
            // assembler.mov(EAX, reinterpret_cast<uint64_t>(laneBaseAddressOffsets.data()));

            // assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
            // TMP_DATA_REGISTER = rs1 + imm
            // assembler.vpaddd(TMP_DATA_REGISTER, TMP_DATA_REGISTER, rs1);

            // TMP_DATA_REGISTER = rs1 + offsets
            assembler.mov(RAX, laneBaseAddressOffsets.data());
            assembler.vmovdqu64(TMP_DATA_REGISTER, asmjit::x86::ptr(RAX));
            assembler.vpaddd(TMP_DATA_REGISTER, TMP_DATA_REGISTER, rs1);
            // Read base
            assembler.mov(TMP_SCALAR_REGISTER, laneLocalMemory.get());

            if (imm >= INT_MAX) {
                spdlog::error("SIMD fastpath bug: IMM >= INT_MAX in load.");
            }

            assembler.vpgatherdd(
                    dst, asmjit::x86::zmmword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0, static_cast<int>(imm)));

            switch (fn3) {
                case 0x0: { // LB
                    assembler.vpmovdb(dst, dst);
                    assembler.vpmovsxbq(dst, dst);
                    break;
                }
                case 0x1: { // LH
                    assembler.vpmovdw(dst, dst);
                    assembler.vpmovsxwd(dst, dst);
                    break;
                }
                case 0x2: { // LW
                    // rd = M[rs1+imm][0:31]
                    // TODO: please god let this be right
                    /* Code here was hoisted up */
                    break;
                }
                case 0x3: { // NA
                    spdlog::error("In an unsupported load operation: {}", fn3);
                    break;
                }
                case 0x4: { // LBU
                    assembler.mov(RAX, 0xFF);
                    assembler.vpbroadcastb(TMP_DATA_REGISTER, RAX);
                    assembler.vpandd(dst, dst, TMP_DATA_REGISTER);
                    break;
                }
                case 0x5: { // LHU
                    assembler.mov(RAX, 0xFFFF);
                    assembler.vpbroadcastb(TMP_DATA_REGISTER, RAX);
                    assembler.vpandd(dst, dst, TMP_DATA_REGISTER);
                    break;
                }
                default: {
                    spdlog::error("In an invalid load operation case: {}", fn3);
                    break;
                }
            }
        }
        case Opcode::STORE: { // TODO: Instrument instrument instrument
            // TODO: ok basically all of this lol yikes
            const auto fn3 = instruction.funct3(); // i've caved. AlignConsecutiveAssignments is now on
            const auto rs1 = asmjit::x86::zmm(instruction.rs1());
            const auto rs2 = asmjit::x86::zmm(instruction.rs2());
            const auto imm = instruction.imm() | (instruction.isHighestBitSet() ? 0xfffff000 : 0);

            // assembler.mov(EAX, imm);
            // assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
            // assembler.vpaddd(TMP_DATA_REGISTER, TMP_DATA_REGISTER, rs1);
            // TMP_DATA_REGISTER = rs1 + imm

            // TMP_DATA_REGISTER = rs1 + offsets
            assembler.mov(RAX, laneBaseAddressOffsets.data());
            assembler.vmovdqu64(TMP_DATA_REGISTER, asmjit::x86::ptr(RAX));
            assembler.vpaddd(TMP_DATA_REGISTER, TMP_DATA_REGISTER, rs1);
            // Read base
            assembler.mov(TMP_SCALAR_REGISTER, laneLocalMemory.get());

            if (imm >= INT_MAX) {
                spdlog::error("SIMD fastpath bug: IMM >= INT_MAX in store.");
            }

            switch (fn3) {
                case 0x0: { // SB
                    // i wonder if this actually works
                    assembler.vmovdqu64(asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b1)), asmjit::x86::zmm1);
                    assembler.vmovdqu64(asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b2)), asmjit::x86::zmm2);

                    assembler.vgatherdps(asmjit::x86::zmm1,
                                         asmjit::x86::dword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0));

                    assembler.vpmovdb(asmjit::x86::xmm2, rs2); // Move the lowest bytes of each dword in rs2 to xmm2

                    // Prepare a mask for blending
                    std::size_t mask{};
                    for (int i = 0; i < LANE_COUNT; i++) {
                        mask <<= 8;
                        mask += 0b1;
                    }

                    assembler.mov(RAX, mask);
                    assembler.kmovq(TMP_MASK_REGISTER, RAX);

                    assembler.k(TMP_MASK_REGISTER).vpblendmb(asmjit::x86::zmm1, asmjit::x86::zmm1, asmjit::x86::zmm2);

                    assembler.vscatterdps(asmjit::x86::dword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0),
                                          asmjit::x86::zmm1);

                    assembler.vmovdqu64(asmjit::x86::zmm1, asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b1)));
                    assembler.vmovdqu64(asmjit::x86::zmm2, asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b2)));

                    break;
                }
                case 0x1: { // SH
                    // i wonder if this actually works
                    assembler.vmovdqu64(asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b1)), asmjit::x86::zmm1);
                    assembler.vmovdqu64(asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b2)), asmjit::x86::zmm2);

                    assembler.vgatherdps(asmjit::x86::zmm1,
                                         asmjit::x86::dword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0));

                    assembler.vpmovdb(asmjit::x86::xmm2, rs2); // Move the lowest bytes of each dword in rs2 to xmm2

                    std::size_t mask{};
                    for (int i = 0; i < LANE_COUNT; i++) {
                        mask <<= 8;
                        mask += 0b11;
                    }

                    assembler.mov(RAX, mask);
                    assembler.kmovq(TMP_MASK_REGISTER, RAX);

                    assembler.k(TMP_MASK_REGISTER).vpblendmb(asmjit::x86::zmm1, asmjit::x86::zmm1, asmjit::x86::zmm2);

                    assembler.vscatterdps(asmjit::x86::dword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0),
                                          asmjit::x86::zmm1);

                    assembler.vmovdqu64(asmjit::x86::zmm1, asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b1)));
                    assembler.vmovdqu64(asmjit::x86::zmm2, asmjit::x86::ptr(reinterpret_cast<uint64_t>(&scratch512b2)));

                    break;
                }
                case 0x2: { // SW
                    // M[rs1+imm][0:31] = rs2[0:31]
                    assembler.vpscatterdd(
                            asmjit::x86::zmmword_ptr(TMP_SCALAR_REGISTER, TMP_DATA_REGISTER, 0, static_cast<int>(imm)),
                            rs2);
                    break;
                }
                default: {
                    spdlog::error("In an invalid STORE operation case: {}", fn3);
                }
            }

            break;
        }
        case Opcode::IMM: { // OK
            static constexpr auto IMM_REGISTER = EAX;

            if (instruction.rd() == 0) {
                spdlog::debug("Skipping over IMM write to zero register.");
                return;
            }

            const auto is0 = instruction.rs1() == 0;
            const auto imm = instruction.imm();
            const auto fn3 = instruction.funct3(); // sorry about the name I just wanted it to be aligned
            const auto src = asmjit::x86::zmm(instruction.rs1());
            const auto dst = asmjit::x86::zmm(instruction.rd());

            assembler.mov(EAX, instruction.imm()); // TODO: Redundant
            assembler.vpbroadcastd(TMP_DATA_REGISTER, IMM_REGISTER);

            switch (fn3) {
                case 0x0: { // ADDI (ok?)
                    if (is0) {
                        assembler.vmovdqa32(dst, TMP_DATA_REGISTER); // TODO?
                    } else {
                        assembler.vpaddq(dst, src, TMP_DATA_REGISTER);
                    }
                    break;
                }
                case 0x2: { // SLTI (ok)
                    assembler.mov(EAX, imm);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vpcmpd(TMP_MASK_REGISTER, src, TMP_DATA_REGISTER, asmjit::x86::VCmpImm::kLT_OQ);
                    assembler.vpmovm2d(dst, TMP_MASK_REGISTER);
                    break;
                }
                case 0x1: {                        // SLLI (OK)
                    const auto shamt = imm & 0x1F; // Shift amount (5 bits) (TODO...sus)
                    assembler.mov(EAX, shamt);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vpsllvd(dst, src, TMP_DATA_REGISTER);
                    break;
                }
                case 0x3: { // SLTIU (OK)
                    assembler.mov(EAX, imm);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vpcmpud(TMP_MASK_REGISTER, src, TMP_DATA_REGISTER, asmjit::x86::VCmpImm::kLT_OQ);
                    assembler.vpmovm2d(dst, TMP_MASK_REGISTER);
                    break;
                }
                case 0x4: { // XORI (OK)
                    assembler.mov(EAX, imm);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vpxorq(dst, src, TMP_DATA_REGISTER);
                    break;
                }
                case 0x5: { // SRLI, SRAI (OK)
                    const auto shamt = imm & 0x1F;
                    assembler.mov(EAX, shamt);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);

                    if (instruction.isSecondHighestBitSet()) { // SRAI
                        assembler.vpsravd(dst, src, TMP_DATA_REGISTER);
                    } else { // SRLI
                        assembler.vpsrlvd(dst, src, TMP_DATA_REGISTER);
                    }
                    break;
                }
                case 0x6: { // ORI (ok)
                    assembler.mov(EAX, imm);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vporq(dst, src, TMP_DATA_REGISTER);
                    break;
                }
                case 0x7: { // ANDI (ok)
                    assembler.mov(EAX, imm);
                    assembler.vpbroadcastd(TMP_DATA_REGISTER, EAX);
                    assembler.vpandq(dst, src, TMP_DATA_REGISTER);
                    break;
                }
                default: {
                    spdlog::error("In an invalid IMM operation case: {}", fn3);
                    break;
                }
            }

            break;
        }
        case Opcode::ARITH: {                      // OK
            const auto fn7 = instruction.funct7(); // sorry about the name I just wanted it to be aligned
            const auto rs1 = asmjit::x86::zmm(instruction.rs1());
            const auto rs2 = asmjit::x86::zmm(instruction.rs2());
            const auto dst = asmjit::x86::zmm(instruction.rd());

            switch (instruction.funct3()) {
                case 0x00: {                                   // ADD, SUB (ok)
                    if (instruction.isSecondHighestBitSet()) { // ADD
                        assembler.vpaddq(dst, rs1, rs2);
                    } else { // SUB
                        assembler.vpsubq(dst, rs1, rs2);
                    }
                    break;
                }
                case 0x01: { // SLL
                    // TODO: SLL only cares about lower 5 bits. Should sanity-check this.
                    // As far as I can understand, vpsllq behaves correctly in this case.
                    assembler.vpsllq(dst, rs1, rs2);
                    break;
                }
                case 0x02: { // SLT (OK)
                    assembler.vpcmpq(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kLT_OQ);
                    assembler.vpmovm2q(dst, TMP_MASK_REGISTER);
                    break;
                }
                case 0x03: { // SLTU (OK)
                    assembler.vpcmpuq(TMP_MASK_REGISTER, rs1, rs2, asmjit::x86::VCmpImm::kLT_OQ);
                    assembler.vpmovm2q(dst, TMP_MASK_REGISTER);
                    break;
                }
                case 0x04: { // XOR
                    assembler.vpxorq(dst, rs1, rs2);
                    break;
                }
                case 0x05: { // SRL, SRA
                    if (instruction.isSecondHighestBitSet()) {
                        assembler.vpsrlq(dst, rs1, rs2);
                    } else {
                        assembler.vpsraq(dst, rs1, rs2);
                    }
                    break;
                }
                case 0x06: { // OR (OK)
                    assembler.vporq(dst, rs1, rs2);
                    break;
                }
                case 0x07: { // AND (OK)
                    assembler.vpandq(dst, rs1, rs2);
                    break;
                }
                default: { // OK
                    spdlog::error("In an invalid arithmetic operation case: {}", fn7);
                    break;
                }
            }
            break;
        }
        case Opcode::MEMORY: {  // OK
            assembler.mfence(); // god bless ;-;
            break;
        }
        case Opcode::SYSCALL: { // OK
            spdlog::error("Syscalls are currently unsupported!");
            break;
        }
        default: { // OK
            spdlog::error("Invalid instruction: 0x{:08x}", instruction.raw);
            break;
        }
    }

incrementPC:
// Zero the zero register lol
resetZeroRegister:
    assembler.vpxorq(TMP_DATA_REGISTER, TMP_DATA_REGISTER, TMP_DATA_REGISTER);
}

AVX512Backend::AVX512Backend(std::uint8_t* memory, State state) : AbstractMachineBackend(memory, state) {
    this->memory          = memory;
    this->program         = memory + MEMORY_SIZE; // Write-only!
    this->laneLocalMemory = std::make_unique<std::uint8_t[]>(MEMORY_SIZE * LANE_COUNT);

    // Each lane gets its own non-instruction memory
    for (auto i = 0; i < LANE_COUNT; i++) {
        static constexpr auto MAX_DISTANCE =
                std::numeric_limits<typename decltype(laneBaseAddressOffsets)::value_type>::max();

        const auto distance = std::distance(&laneLocalMemory[0], &laneLocalMemory[i]); // TODO: check order

        if (distance >= MAX_DISTANCE) {
            spdlog::error("Can't run with inputs of size {} bytes. Max is 2 GB. Behavior undefined from hereon.",
                          laneBaseAddressOffsets[i]);
        }

        laneBaseAddressOffsets[i] = distance;
        laneBaseAddresses         = &laneLocalMemory[i];
        std::memcpy(&laneLocalMemory[i * MEMORY_SIZE], memory, MEMORY_SIZE);

        FuzzingStrategies::MaxEverythingStrategy(&laneLocalMemory[i], MEMORY_SIZE);
    }
}

void AVX512Backend::createBranchLabels(const std::vector<Instruction>& instructions) {
    for (auto i = 0ull; i < instructions.size(); ++i) {
        labels.push_back(assembler.newLabel());
        const auto& instruction = instructions.at(i);

        if (0x70D0) {                           // TODO
            std::size_t targetIndex   = 0x70D0; // TODO
            std::size_t notTakenIndex = i + 1;  // TODO: use +4 if going to memory-based & still needed

            // Create labels
            auto targetLabel   = assembler.newLabel();
            auto notTakenLabel = assembler.newLabel();

            instructionIdToLabelsMap[instruction.uniqueId] = {targetLabel, notTakenLabel};

            instructionIdToLabelsMap[targetIndex].push_back(targetLabel);
            instructionIdToLabelsMap[notTakenIndex].push_back(notTakenLabel);
        }
    }
}
