#include "backends/AbstractMachineBackend.hpp"

#pragma once

class ClassicalBackend : AbstractMachineBackend {
public:
    using AbstractMachineBackend::AbstractMachineBackend;
    void run() override;
};
