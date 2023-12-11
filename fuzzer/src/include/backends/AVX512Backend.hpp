#pragma once

#include <array>
#include <asmjit/asmjit.h>
#include <immintrin.h>
#include <memory>

#include "backends/MachineBackend.hpp"

/*
 * Ideas:
 * Inserting comparisons against pc for mask registers based on a CFG.
 *
 * TODO: if mask registers all zero, or all one, special-case. If half-zero, try optimizing.
 */


constexpr auto LANE_COUNT = 32;
constexpr auto RAX = asmjit::x86::rax;
constexpr auto RSP = asmjit::x86::rax;
constexpr auto TMP_MASK_REGISTER = asmjit::x86::k1;
constexpr auto TMP_DATA_REGISTER = asmjit::x86::zmm31;

struct AVX512State {
    // Program counter,
    __m512i pc{0};

    // Registers, they are called "x" in the technical document
    // x[0] is just constant 0, and so we have 31 general purpose registers
    __m512i x[32]{0};
};

class AVX512Backend : MachineBackend {
public:
    AVX512Backend(uint8_t* memory, State state);
    void run() override;

private:
    asmjit::x86::Assembler assembler{};
    AVX512State state{}; // TODO: init properly :(
    asmjit::CodeHolder code{};
    asmjit::JitRuntime runtime{};
    void emitInstruction(const Instruction& instruction);
    std::unique_ptr<std::uint8_t[]> laneLocalMemory;
    std::array<std::uint32_t, LANE_COUNT> laneBaseAddressOffsets{};
};
