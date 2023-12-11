#include "MachineBackend.hpp"

#pragma once

class ClassicalBackend : MachineBackend {
public:
    using MachineBackend::MachineBackend;
    void run() override;
};
