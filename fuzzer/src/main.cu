#include <iostream>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "backends/MachineBackend.hpp"
#include "backends/ClassicalBackend.hpp"
#include "backends/AVX512Backend.hpp"

#include <cuda.h>
#include <cuda_runtime.h>

typedef struct RAMImage
{
	uint8_t* data;
	uint32_t size;
} RAMImage;

typedef struct State
{
	uint32_t pc;
	uint32_t x;
} State;

void setup()
{
    int deviceCount = 0;
    std::string name;
    cudaError_t err = cudaGetDeviceCount(&deviceCount);

    printf("---------------------------------------------------------\n");
    printf("Initializing CUDA for Cuda Fuzzer\n");
    printf("Found %d CUDA devices\n", deviceCount);

    for(int i = 0; i < deviceCount; i++)
	{
        cudaDeviceProp deviceProps;
        cudaGetDeviceProperties(&deviceProps, i);
        name = deviceProps.name;

        printf("Device %d: %s\n", i, deviceProps.name);
        printf("   SMs:        %d\n", deviceProps.multiProcessorCount);
        printf("   Global mem: %.0f MB\n", static_cast<float>(deviceProps.totalGlobalMem) / (1024 * 1024));
        printf("   CUDA Cap:   %d.%d\n", deviceProps.major, deviceProps.minor);
    }
    printf("---------------------------------------------------------\n");

	// First we copy an image of the program and memory to execute
	// Then we initialize the program state
	// Then we launch the kernel

	// It's a bit strange here just because we want to load the program into a buffer on the host side
	// (Along with say, the initial memory) and then we want to copy all that for each instance on
	// the device side

	// Then we want our kernel call to give the relevant information for setting up the initial state of the program

	// Once we have the processor state, and a copy of the memory on the device, we can start executing everything
	
    // cudaMalloc(&cudaDevicePosition, sizeof(float) * 3 * numberOfCircles);
    // cudaMalloc(&cudaDeviceVelocity, sizeof(float) * 3 * numberOfCircles);
    // cudaMalloc(&cudaDeviceColor, sizeof(float) * 3 * numberOfCircles);
    // cudaMalloc(&cudaDeviceRadius, sizeof(float) * numberOfCircles);
    // cudaMalloc(&cudaDeviceImageData, sizeof(float) * 4 * image->width * image->height);

	// if(numberOfCircles < 1000)
	// {
	// 	maxAcreSubdiv = 2;
	// }
	
	// int globalHitsSize = ((2 << (maxAcreSubdiv + acreStartdiv)) * (2 << (maxAcreSubdiv + acreStartdiv))) * numberOfCircles;
	// int globalHitCountsSize = (2 << (maxAcreSubdiv + acreStartdiv)) * (2 << (maxAcreSubdiv + acreStartdiv));
        
	// cudaError_t mallocErrorCode = cudaMalloc(&globalHits, 3 * (sizeof(int) * globalHitsSize) + 2 * (sizeof(int) * globalHitCountsSize));

	// if(mallocErrorCode != cudaSuccess)
	// {
	// 	printf("FAILED TO CUDA MALLOC: %s\n", cudaGetErrorString(mallocErrorCode));
	// }
    
    // //cudaMalloc(&cudaDeviceParts, sizeof(unsigned char) * numberOfCircles);

    // cudaMemcpy(cudaDevicePosition, position, sizeof(float) * 3 * numberOfCircles, cudaMemcpyHostToDevice);
    // cudaMemcpy(cudaDeviceVelocity, velocity, sizeof(float) * 3 * numberOfCircles, cudaMemcpyHostToDevice);
    // cudaMemcpy(cudaDeviceColor, color, sizeof(float) * 3 * numberOfCircles, cudaMemcpyHostToDevice);
    // cudaMemcpy(cudaDeviceRadius, radius, sizeof(float) * numberOfCircles, cudaMemcpyHostToDevice);

    // // Initialize parameters in constant memory.  We didn't talk about
    // // constant memory in class, but the use of read-only constant
    // // memory here is an optimization over just sticking these values
    // // in device global memory.  NVIDIA GPUs have a few special tricks
    // // for optimizing access to constant memory.  Using global memory
    // // here would have worked just as well.  See the Programmer's
    // // Guide for more information about constant memory.

    // GlobalConstants params;
    // params.sceneName = sceneName;
    // params.numberOfCircles = numberOfCircles;
    // params.imageWidth = image->width;
    // params.imageHeight = image->height;
    // params.position = cudaDevicePosition;
    // params.velocity = cudaDeviceVelocity;
    // params.color = cudaDeviceColor;
    // params.radius = cudaDeviceRadius;
    // params.imageData = cudaDeviceImageData;
    
    // //params.parts = cudaDeviceParts;

    // cudaMemcpyToSymbol(cuConstRendererParams, &params, sizeof(GlobalConstants));

    // // Also need to copy over the noise lookup tables, so we can
    // // implement noise on the GPU
    // int* permX;
    // int* permY;
    // float* value1D;
    // getNoiseTables(&permX, &permY, &value1D);
    // cudaMemcpyToSymbol(cuConstNoiseXPermutationTable, permX, sizeof(int) * 256);
    // cudaMemcpyToSymbol(cuConstNoiseYPermutationTable, permY, sizeof(int) * 256);
    // cudaMemcpyToSymbol(cuConstNoise1DValueTable, value1D, sizeof(float) * 256);

    // // Copy over the color table that's used by the shading
    // // function for circles in the snowflake demo

    // float lookupTable[COLOR_MAP_SIZE][3] = {
    //     {1.f, 1.f, 1.f},
    //     {1.f, 1.f, 1.f},
    //     {.8f, .9f, 1.f},
    //     {.8f, .9f, 1.f},
    //     {.8f, 0.8f, 1.f},
    // };

    // cudaMemcpyToSymbol(cuConstColorRamp, lookupTable, sizeof(float) * 3 * COLOR_MAP_SIZE);
}

__device__ void  runInstruction(State* state, uint32_t inst, uint8_t* memory, uint32_t memorySize)
{	
	uint32_t rd = (inst >> 7) & 0x1f; // Bits 11 to 7

	uint32_t opcode = inst & 0x7f;
	
	// I literally just put these in the order they are in as I read them from page 106 of the
	// RISCV user guide version 2.2 lol
	// There are certainly better ways to do this!
	switch(opcode)
	{
		case 0x37: // lui
		{
			// We don't need to load it into low bits, then reshift it into high bits... can just read the bits in place!
			// Lower bits are filled with zeros according to standard
			state->x[rd] = inst & 0xfffff000;
			state->pc += 4;
			break;
		}
		case 0x17: // auipc
		{
			// Mirrors the above, but result is imm + offset from pc
			state->x[rd] = state->pc + (inst & 0xfffff000);
			state->pc += 4;
			break;
		}
		case 0x6f: // jal
		{
			// This part seems like it would be much nicer in hardware...
			// The bit order is very strange, [20|10:1|11|19:12]
			// so 31 -> 20 == 11, 30 -> 10 == 20, 20 -> 11 == 9, 19 -> 19 == 0
			// Since right shift doing sign extension is implementation dependent, and
			// this wants sign extension, we do it manually...
			// also, yes, this is correct -- it doesn't set lsb
			uint32_t imm = ((inst & (1 << 31)) >> 11) | ((inst & 0x7fe00000) >> 20) | ((inst & 0x00100000) >> 9) | (inst & 0x000ff000);
			state->x[rd] = state->pc + 4;
			// Two cases: either our machine does sign extension and this is redundant, or it defaults to 0 extension and we need this
			// No machine will default to 1 extension so we're all good
			if(inst & (1 << 31))
			{
				imm |= 0xffe00000;
			}
			state->pc += imm;
			break;
		}
		case 0x67: // jalr
		{
			// This wants us to use a temporary in case the destination register and source register are the same
			uint32_t rs1 = (inst >> 15) & 0x1f;
			uint32_t temp = state->pc + 4;
			// Oh yeah we have to sign this one again, but bits are nicer, [11:0], so 31 -> 11 == 20
			uint32_t imm = (inst >> 20);
			if(inst & (1 << 31))
			{
				imm |= 0xfffff000;
			}
			state->pc = (state->x[rs1] + imm) & ~1;
			state->x[rd] = temp;
			break;
		}
		case 0x63: // beq, bne, blt, bge, bltu, bgeu
		{
			uint32_t rs1 = (inst >> 15) & 0x1f;
			uint32_t rs2 = (inst >> 20) & 0x1f;
			// The immediate for jump offset is cursed again, high bits are [12|10:5] and then rd has [4:1|11]
			// 31 -> 12 == 19, 30 -> 10 == 20, 4 -> 4 == 0, 0 -> 11 == -11
			// we have to sign extend again as well
			uint32_t imm = ((inst & (1 << 31)) >> 19) | ((inst & 0x7e000000) >> 20) | (rd & 0x1e) | ((rd & 0x1) << 11);
			if(inst & (1 << 31))
			{
				imm |= 0xffffe000;
			}
			// funct3 (bits 14:12) determines which of the comparisons to do
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // beq
				{
					if(state->x[rs1] == state->x[rs2]) { state->pc += imm; }
					break;
				}
				case 0x1: // bne
				{
					if(state->x[rs1] != state->x[rs2]) { state->pc += imm; }
					break;
				}
				case 0x4: // blt (this is signed)
				{
					if((int32_t)state->x[rs1] < (int32_t)state->x[rs2]) { state->pc += imm; }
					break;
				}
				case 0x5: // bge (this is signed)
				{
					if((int32_t)state->x[rs1] >= (int32_t)state->x[rs2]) { state->pc += imm; }
					break;
				}
				case 0x6: // bltu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] < (uint32_t)state->x[rs2]) { state->pc += imm; }
					break;
				}
				case 0x7: // bgeu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] >= (uint32_t)state->x[rs2]) { state->pc += imm; }
					break;
				}
				// TODO: handle if it isn't one of these? Set trap maybe?
			}
			state->pc += 4;
			break;
		}
		case 0x03: // lb, lh, lw, lbu, lhu
		{
			uint32_t rs1 = (inst >> 15) & 0x1f;
			// Same format as jalr
			uint32_t imm = (inst >> 20);
			if(inst & (1 << 31))
			{
				imm |= 0xfffff000;
			}
			// funct3 again
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // lb
				{
					uint8_t loaded = *(uint8_t*)(memory + (state->x[rs1] + imm));
					state->x[rd] = (loaded & (1 << 7)) ? loaded | 0xffffff00 : loaded;
					break;
				}
				case 0x1: // lh
				{
					uint16_t loaded = *(uint16_t*)(memory + (state->x[rs1] + imm));
					state->x[rd] = (loaded & (1 << 15)) ? loaded | 0xffff0000 : loaded;
					break;
				}
				case 0x2: // lw
				{
					state->x[rd] = *(uint32_t*)(memory + (state->x[rs1] + imm));
					break;
				}
				case 0x4: // lbu
				{
					uint8_t loaded = *(uint8_t*)(memory + (state->x[rs1] + imm));
					state->x[rd] = loaded & 0x000000ff;
					break;
				}
				case 0x5: // lhu
				{
					uint16_t loaded = *(uint16_t*)(memory + (state->x[rs1] + imm));
					state->x[rd] = loaded & 0x0000ffff;
					break;
				}
				// TODO: handle if it isn't one of these? Set trap maybe?
			}
			state->pc += 4;
			break;
		}
		case 0x23: // sb, sh, sw
		{
			// In this one, we reuse rs1 as the memory location (well plus the immediate offset) and we use rs2 as the source
			// This means the immediate is split up again
			uint32_t rs1 = (inst >> 15) & 0x1f;
			uint32_t rs2 = (inst >> 20) & 0x1f;
			uint32_t imm = ((inst & 0xfe000000) >> 20) | rd;
			if(inst & (1 << 31))
			{
				imm |= 0xfffff000;
			}
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // sb
				{
					*(uint8_t*)(memory + (state->x[rs1] + imm)) = state->x[rs2];
					break;
				}
				case 0x1: // sh
				{
					*(uint16_t*)(memory + (state->x[rs1] + imm)) = state->x[rs2];
					break;
				}
				case 0x2: // sw
				{
					*(uint32_t*)(memory + (state->x[rs1] + imm)) = state->x[rs2];
					break;
				}
				// TODO: handle default?
			}
			state->pc += 4;
			break;
		}
		case 0x13: // addi, slti, sltiu, xori, ori, andi, slli, srli, srai
		{
			uint32_t rs1 = (inst >> 15) & 0x1f;
			uint32_t imm = (inst >> 20);
			if(inst & (1 << 31))
			{
				imm |= 0xfffff000;
			}
			// funct3 again
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // addi
				{
					state->x[rd] = state->x[rs1] + imm;
					break;
				}
				case 0x2: // slti
				{
					// I'm pretty sure c standard says true statements always get set to 1 but just to make
					// it clear
					state->x[rd] = ((int32_t)state->x[rs1] < (int32_t)imm) ? 1 : 0;
					break;
				}
				case 0x3: // sltiu
				{
					state->x[rd] = ((uint32_t)state->x[rs1] < (uint32_t)imm) ? 1 : 0;
					break;
				}
				case 0x4: // xori
				{
					state->x[rd] = state->x[rs1] ^ imm;
					break;
				}
				case 0x6: // ori
				{
					state->x[rd] = state->x[rs1] | imm;
					break;
				}
				case 0x7: // andi
				{
					state->x[rd] = state->x[rs1] & imm;
					break;
				}
				case 0x1: // slli
				{
					// TODO: these instructions only use the lowest 5 bits of imm, and
					// the standard says the high bits are all 0 (or 1 of them is 1 for srai)
					// I assume it should be illegal operation if that's not the case?
					state->x[rd] = state->x[rs1] << (imm & 0x1f);
					break;
				}
				case 0x5: // srli, srai are differentiated by a 1 in the 30th bit
				{
					uint32_t shamt = imm & 0x1f;
					if(inst & (1 << 30))
					{
						state->x[rd] = (int32_t)(state->x[rs1]) >> shamt;
						if((state->x[rs1] & (1 << 31)) && shamt)
						{
							// Bit shifts by 32 are undefined by c standard so we actually can't use this which is extremely cringe
							// because it won't work on 0 shift... so we just special case it. 
							state->x[rd] |= ~0 << (32 - shamt);
						}
					}
					else
					{
						// Don't do sign extension (don't need to do anything special here)
						state->x[rd] = (uint32_t)(state->x[rs1]) >> shamt;
					}
					break;
				}
			}
			state->pc += 4;
			break;
		}
		case 0x33: // add, sub, sll, slt, sltu, xor, srl, sra, or, and
		{
			uint32_t rs1 = (inst >> 15) & 0x1f;
			uint32_t rs2 = (inst >> 20) & 0x1f;
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // add, sub are differentiated again by funct7 (only 1 bit of it tho), inst bit 30
				{
					// Oh and arithmetic overflow is ignored (aka we don't care, and you know what, just use what our implementation does)
					// This isn't 122
					if(inst & (1 << 30)) // add
					{
						state->x[rd] = state->x[rs1] + state->x[rs2];
					}
					else // sub
					{
						state->x[rd] = state->x[rs1] - state->x[rs2];
					}
					break;
				}
				case 0x1: // sll
				{
					// This only cares about the lower 5 bits
					state->x[rd] = state->x[rs1] << (state->x[rs2] & 0x1f);
					break;
				}
				case 0x2: // slt
				{
					state->x[rd] = ((int32_t)state->x[rs1] < (int32_t)state->x[rs2]) ? 1 : 0;
					break;
				}
				case 0x3: // sltu
				{
					state->x[rd] = ((uint32_t)state->x[rs1] < (uint32_t)state->x[rs2]) ? 1 : 0;
					break;
				}
				case 0x4: // xor
				{
					state->x[rd] = state->x[rs1] ^ state->x[rs2];
					break;
				}
				case 0x5: // srl, sra
				{
					uint32_t shamt = state->x[rs2] & 0x1f;
					if(inst & (1 << 30)) 
					{
						state->x[rd] = (int32_t)(state->x[rs1]) >> shamt;
						if(state->x[rs1] & (1 << 31) && shamt)
						{
							state->x[rd] |= ~0 << (32 - shamt);
						}
					}
					else
					{
						state->x[rd] = (uint32_t)(state->x[rs1]) >> shamt;
					}
					break;
				}
				case 0x6: // or
				{
					state->x[rd] = state->x[rs1] | state->x[rs2];
					break;
				}
				case 0x7: // and
				{
					state->x[rd] = state->x[rs1] & state->x[rs2];
					break;
				}
			}
			state->pc += 4;
			break;
		}
		case 0x0f: // fence, fence.i
		{
			// TODO: do something other than nop?
			state->pc += 4;
			break;
		}
		case 0x73: // ecall, ebreak, csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci
		{
			// TODO: do something other than nop?
			state->pc += 4;
			break;
		}
	}

	// We could have written to 0, so just put it back to 0
	if(rd == 0) 
	{
		state->x[rd] = 0;
	}
}

__global__ void kernelExecuteProgram()
{
	State state;
	
	initState(state);
	// We initalize a fake return address so that we can tell when we're done lol
	// Make sure it's 4 byte aligned!
	uint32_t const DONE_ADDRESS = 0xfffffff0; 
	state.x[1] = DONE_ADDRESS;

	// We set the stack pointer to 0 cuz, uh, sure
	state.x[2] = memorySize; 

	while(1)
	{
		uint32_t inst = *(uint32_t*)(program + state.pc);
		printf("executing instruction: %08x\n", inst);
		runInstruction(&state, inst, memory);
		printf("pc = %u\n", state.pc);
		if(state.pc == DONE_ADDRESS)
		{
			break;
		}
	}
	
    int imageX = blockIdx.x * blockDim.x + threadIdx.x;
    int imageY = blockIdx.y * blockDim.y + threadIdx.y;

    int width = cuConstRendererParams.imageWidth;
    int height = cuConstRendererParams.imageHeight;

    if (imageX >= width || imageY >= height)
        return;

    int offset = 4 * (imageY * width + imageX);
    float shade = .4f + .45f * static_cast<float>(height-imageY) / height;
    float4 value = make_float4(shade, shade, shade, 1.f);

    // Write to global memory: As an optimization, this code uses a float4
    // store, which results in more efficient code than if it were coded as
    // four separate float stores.
    *(float4*)(&cuConstRendererParams.imageData[offset]) = value;
}

int main(int argc, char** argv)
{
    if (argc != 2) {
        printf("Pass one argument, the filename.\n");
        return 1;
    }

    FILE* programFile = fopen(argv[1], "rb");
    if (!programFile) {
        printf("Couldn't open program file \"%s\".\n", argv[1]);
        return 1;
    }
    fseek(programFile, 0L, SEEK_END); // Technically it wants a long... but
    // The program file cannot possibly be more than can fit in a 32 because it's 32 bit lol
    const auto programSize = ftell(programFile);
    rewind(programFile);

    uint8_t* memory = nullptr;
    uint8_t* program = nullptr;

    memory = static_cast<uint8_t*>(malloc(MEMORY_SIZE + programSize));
    if (!memory) {
        printf("Failed to allocate memory for the emulator.\n");
        return 1;
    }
    program = memory + MEMORY_SIZE;
    fread(program, sizeof(uint8_t), programSize, programFile);

    auto state = State();
    // We initalize a fake return address so that we can tell when we're done lol
    state.x[1] = DONE_ADDRESS;
    // We set the stack pointer to 0 cuz, uh, sure
    state.x[2] = MEMORY_SIZE;

	setup();

    auto backend = ClassicalBackend(memory, state);
    backend.run();

    free(memory);

    return 0;
}
