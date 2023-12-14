#include <iostream>

#include "backends/AVX512Backend.hpp"
#include "spdlog/spdlog.h"
#include "strategies/SimpleFuzzingStrategies.hpp"


#include <fstream>

void AVX512Backend::run() {
    spdlog::info("The AVX512 backend is a JIT. It doesn't run anything! Look out for an output.");

    for (auto i = 0ull; i < numberOfInstructions; i++) {
        emitInstruction(Instruction{reinterpret_cast<Instruction*>(program)[i]});
    }

    auto output = std::ofstream("jitoutput.dmp", std::ios::out | std::ios::binary | std::ios::trunc);

    if (!output) {
        spdlog::error("Could not open jitoutput.dmp for writing!");
        exit(EXIT_FAILURE);
    }


    const auto text     = code.textSection();
    const auto textCode = text->data();
    const auto textSize = text->bufferSize();

    for (auto i = 0ull; i < textSize; i++) {
        output << std::format("{:02x}", textCode[i]);
    }

    output << '\n';

    output.close();
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
                    // seemingly not RIP-relative so this addressof works? cool
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

AVX512Backend::AVX512Backend(std::uint8_t* memory, State state, std::size_t programSize)
    : AbstractMachineBackend(memory, state, programSize) {
    this->programSize          = programSize;
    this->numberOfInstructions = programSize / 4;
    this->memory               = memory;
    this->program              = memory + MEMORY_SIZE; // Write-only!
    this->laneLocalMemory      = std::make_unique<std::uint8_t[]>(MEMORY_SIZE * LANE_COUNT);

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
