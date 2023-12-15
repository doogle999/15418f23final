# Backends

- `AVX512Backend.cpp` contains the AVX-512 JIT backend
- `ClassicalBackend.cpp` contains the interpreter backend.
- Definitions are in `include/backends/{AbstractMachineBackend,AVX512Backend,ClassicalBackend}.hpp`

The CUDA backend, which is not contained in this folder, is in `main.cu` in the `ajaxemu` folder of the project.