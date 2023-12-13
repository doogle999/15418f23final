#pragma once

#include <array>
#include <asmjit/asmjit.h>
#include <asmjit/core.h>
#include <asmjit/x86.h>
#include <immintrin.h>
#include <memory>
#include <unordered_map>
#include <vector>

#include "backends/AbstractMachineBackend.hpp"

/*
 * Ideas:
 * Inserting comparisons against pc for mask registers based on a CFG.
 *
 * TODO: if mask registers all zero, or all one, special-case. If half-zero, try optimizing.
 */

constexpr auto LANE_COUNT                 = 512 / 32;
constexpr auto EAX                        = asmjit::x86::eax;
constexpr auto TMP_SCALAR_REGISTER        = asmjit::x86::r15;
constexpr auto RAX                        = asmjit::x86::rax;
constexpr auto RSP                        = asmjit::x86::rax;
constexpr auto EXECUTION_CONTROL_REGISTER = asmjit::x86::k2;
constexpr auto TMP_MASK_REGISTER          = asmjit::x86::k1;
constexpr auto TMP_DATA_REGISTER          = asmjit::x86::zmm0;

static_assert(LANE_COUNT == 16);

struct AVX512State {
    // Program counter,
    std::uint32_t pc[32] {0};

    // Registers, they are called "x" in the technical document
    // x[0] is just constant 0, and so we have 31 general purpose registers
    __m512i x[32]{0};
    std::size_t totalNumJumps{};
    std::size_t totalJumpfsSeen{};
    std::size_t totalJumpsTaken{};
};

class AVX512Backend : AbstractMachineBackend {
public:
    AVX512Backend(uint8_t* memory, State state);
    void run() override;

private:
    void createBranchLabels(const std::vector<Instruction>& instructions);

    std::unordered_map<std::size_t, std::vector<asmjit::Label>> instructionIdToLabelsMap;
    std::vector<asmjit::Label> labels;
    asmjit::x86::Assembler assembler{};
    AVX512State state{}; // TODO: init properly :(
    asmjit::CodeHolder code{};
    asmjit::JitRuntime runtime{};
    void emitInstruction(const Instruction& instruction);
    std::unique_ptr<std::uint8_t[]> laneLocalMemory;
    std::array<std::uint32_t, LANE_COUNT> laneBaseAddressOffsets{};
    std::array<std::uint32_t, LANE_COUNT> laneBaseAddresses{};
};
