#pragma once

#include <cstdint>

// Some references and tools
// https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf
// https://msyksphinz-self.github.io/riscv-isadoc/html/rvi.html#lui
// https://godbolt.org/
// https://luplab.gitlab.io/rvcodecjs/#q=02010113&abi=false&isa=AUTO

// Width of integer registers in bits
using MachineWord           = std::uint32_t;
constexpr auto MEMORY_SIZE  = 0xff;
constexpr auto XLEN         = sizeof(std::uint32_t);
constexpr auto DONE_ADDRESS = 0xfffffff0u;

enum class Opcode {
    ARITH   = 0x33,
    AUIPC   = 0x17,
    BRANCH  = 0x63,
    IMM     = 0x13,
    JAL     = 0x6F,
    JALR    = 0x67,
    LOAD    = 0x03,
    LUI     = 0x37,
    MEMORY  = 0x0F,
    STORE   = 0x23,
    SYSCALL = 0x73,
};

struct Instruction {
    std::size_t uniqueId{}; // Address is probably better. But meh.
    MachineWord raw;

    // Generic helpers. See https://riscv.org/wp-content/uploads/2017/05/riscv-spec-v2.2.pdf
    inline MachineWord opcode() const { return raw & 0x7F; }
    inline MachineWord rd() const { return (raw >> 7) & 0x1F; }
    inline MachineWord funct3() const { return (raw >> 12) & 0x7; }
    inline MachineWord funct7() const { return raw >> 25; }
    inline MachineWord rs1() const { return (raw >> 15) & 0x1F; }
    inline MachineWord rs2() const { return (raw >> 15) & 0x1F; }
    inline MachineWord imm() const { return static_cast<std::int32_t>(raw) >> 20; } // TODO: int or uint...
    inline MachineWord isSecondHighestBitSet() const { return static_cast<std::uint32_t>(raw) & (1u << 30); }
    inline MachineWord isHighestBitSet() const { return static_cast<std::uint32_t>(raw) & (1u << 31); }
};

struct State {
    // Program counter,
    MachineWord pc{0};

    // Registers, they are called "x" in the technical document
    // x[0] is just constant 0, and so we have 31 general purpose registers
    MachineWord x[32]{0};
};

class AbstractMachineBackend {
public:
    explicit AbstractMachineBackend(std::uint8_t* memory, State state)
        : memory(memory), program(memory + MEMORY_SIZE), state(state){};
    virtual void run() = 0;

protected:
    std::uint8_t* memory;
    std::uint8_t* program;
    State state;
};
