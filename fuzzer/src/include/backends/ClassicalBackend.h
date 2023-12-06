#include "backends/MachineBackend.h"

#pragma once

class ClassicalBackend : MachineBackend {
public:
    using MachineBackend::MachineBackend;
    void run() override;
};