#pragma once

#include <limits>
#include <random>
#include <type_traits>

#include "strategies/AbstractFuzzingStrategy.hpp"

namespace FuzzingStrategies {
    AbstractFuzzingStrategy MinEverythingStrategy = [](std::uint8_t* memory, std::size_t memorySize) {
        constexpr auto MIN_VALUE = std::numeric_limits<std::remove_pointer_t<decltype(memory)>>::min();
        static_assert(MIN_VALUE == 0x00);

        for (auto i = 0; i < memorySize; i++) {
            memory[i] = MIN_VALUE;
        }
    };
    AbstractFuzzingStrategy MaxEverythingStrategy = [](std::uint8_t* memory, std::size_t memorySize) {
        constexpr auto MAX_VALUE = std::numeric_limits<std::remove_pointer_t<decltype(memory)>>::max();
        static_assert(MAX_VALUE == 0xFF);

        for (auto i = 0; i < memorySize; i++) {
            memory[i] = MAX_VALUE;
        }
    };
    AbstractFuzzingStrategy RandomizedStrategy = [](std::uint8_t* memory, std::size_t memorySize) {
        static constexpr auto RANDOM_NUMBER_GENERATOR_SEED = 1337;
        static std::mt19937 callableRandomNumberGenerator{RANDOM_NUMBER_GENERATOR_SEED};

        for (auto i = 0; i < memorySize; i++) {
            memory[i] = callableRandomNumberGenerator();
        }
    };
} // namespace FuzzingStrategies
