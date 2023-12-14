#include <iostream>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "backends/AVX512Backend.hpp"
#include "backends/AbstractMachineBackend.hpp"
#include "backends/ClassicalBackend.hpp"

int main(int argc, char** argv) {
    if (argc != 2) {
        printf("Pass one argument, the filename.\n");
        return 1;
    }

    FILE* programFile = fopen(argv[1], "rb");
    if (!programFile) {
        printf("Couldn't open program file \"%s\".\n", argv[1]);
        return 1;
    }
    fseek(programFile, 0L, SEEK_END); // Technically it wants a long... but
    // The program file cannot possibly be more than can fit in a 32 because it's 32 bit lol
    const auto programSize = ftell(programFile);
    rewind(programFile);

    uint8_t* memory  = nullptr;
    uint8_t* program = nullptr;

    memory = static_cast<uint8_t*>(malloc(MEMORY_SIZE + programSize));
    if (!memory) {
        printf("Failed to allocate memory for the emulator.\n");
        return 1;
    }
    program = memory + MEMORY_SIZE;
    fread(program, sizeof(uint8_t), programSize, programFile);

    auto state = State();
    // We initalize a fake return address so that we can tell when we're done lol
    state.x[1] = DONE_ADDRESS;
    // We set the stack pointer to 0 cuz, uh, sure
    state.x[2] = MEMORY_SIZE - 4;

    auto backend = ClassicalBackend(memory, state, programSize);
    backend.run();

    free(memory);

    return 0;
}
