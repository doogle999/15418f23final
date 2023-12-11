#pragma once

#include "MachineBackend.hpp"

class AVX512Backend : MachineBackend {
public:
    using MachineBackend::MachineBackend;
    void run() override;
};
