#pragma once

#include <cstdint>

// Some references and tools
// https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf
// https://msyksphinz-self.github.io/riscv-isadoc/html/rvi.html#lui
// https://godbolt.org/
// https://luplab.gitlab.io/rvcodecjs/#q=02010113&abi=false&isa=AUTO

// Width of integer registers in bits
using MachineWord = std::uint32_t;
constexpr auto MEMORY_SIZE = 0xff;
constexpr auto XLEN = sizeof(std::uint32_t);
constexpr auto DONE_ADDRESS = 0xfffffff0u;

struct State {
    // Program counter,
    MachineWord pc{0};

    // Registers, they are called "x" in the technical document
    // x[0] is just constant 0, and so we have 31 general purpose registers
    MachineWord x[32]{0};
};

class MachineBackend {
public:
    explicit MachineBackend(uint8_t* memory, State state)
        : memory(memory), program(memory + MEMORY_SIZE), state(state){};
    virtual void run() = 0;

protected:
    uint8_t* memory;
    uint8_t* program;
    State state;
};
