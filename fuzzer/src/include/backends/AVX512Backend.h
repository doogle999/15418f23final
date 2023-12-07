#pragma once

#include "backends/MachineBackend.h"

class AVX512Backend : MachineBackend {
public:
    using MachineBackend::MachineBackend;
    void run() override;
};