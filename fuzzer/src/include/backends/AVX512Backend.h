#pragma once

#include "backends/MachineBackend.h"

class AVX512Backend : MachineBackend {
public:
    void run() override;
};