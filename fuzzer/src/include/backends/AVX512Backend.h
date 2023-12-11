#pragma once

#include <asmjit/asmjit.h>
#include <immintrin.h>

#include "backends/MachineBackend.h"

constexpr auto TMP_MASK = asmjit::x86::k1;

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
};
