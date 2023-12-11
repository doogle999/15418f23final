#pragma once

#include <cstdint>

using AbstractFuzzingStrategy = void(*)(std::uint8_t* memory, std::size_t memorySize);
