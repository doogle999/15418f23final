#pragma once

#include "strategies/AbstractFuzzingStrategy.hpp"
#include <limits>
#include <type_traits>

namespace Strategies {
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
} // namespace Strategies
