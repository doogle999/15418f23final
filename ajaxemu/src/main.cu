#include <iostream>

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <cuda.h>
#include <cuda_runtime.h>

#include <chrono>
#include <atomic>
#include <random>

#include "mpi.h"

typedef struct State
{
    uint32_t pc;
    uint32_t x[32];
} State;

typedef struct Result
{
    int32_t returnVal;
    int32_t errorCode;
} Result;

typedef struct BranchData
{
    uint32_t hasBeenTaken;
    uint32_t hasBeenSkipped;
} BranchData;

// void setup()
// {
//     int deviceCount = 0;
//     std::string name;
//     cudaError_t err = cudaGetDeviceCount(&deviceCount);

//     printf("---------------------------------------------------------\n");
//     printf("Initializing CUDA for Cuda Fuzzer\n");
//     printf("Found %d CUDA devices\n", deviceCount);

//     for(int i = 0; i < deviceCount; i++)
// 	{
//         cudaDeviceProp deviceProps;
//         cudaGetDeviceProperties(&deviceProps, i);
//         name = deviceProps.name;

//         printf("Device %d: %s\n", i, deviceProps.name);
//         printf("   SMs:        %d\n", deviceProps.multiProcessorCount);
//         printf("   Global mem: %.0f MB\n", static_cast<float>(deviceProps.totalGlobalMem) / (1024 * 1024));
//         printf("   CUDA Cap:   %d.%d\n", deviceProps.major, deviceProps.minor);
//     }
//     printf("---------------------------------------------------------\n");
// }

int classicalExecuteInstruction(State* state, uint32_t inst, uint8_t* memory, uint8_t* program, uint32_t memorySize, uint32_t programSize, BranchData* branchResults)
{
	// Normally this is the destination register, but in S and B type instructions
	// where there is not destination register these same bits communicate parts of an immediate
	// value. We always need to look at these bits as a unit no matter what
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
			state->pc = (state->x[rs1] + (int32_t)imm) & ~1;
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
			int32_t takeBranch = 0;
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // beq
				{
					if(state->x[rs1] == state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x1: // bne
				{
					if(state->x[rs1] != state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x4: // blt (this is signed)
				{
					if((int32_t)state->x[rs1] < (int32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x5: // bge (this is signed)
				{
					if((int32_t)state->x[rs1] >= (int32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x6: // bltu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] < (uint32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x7: // bgeu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] >= (uint32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				// TODO: handle if it isn't one of these? Set trap maybe?
			}
			if(takeBranch)
			{
				uint32_t zero = 0;
				__atomic_compare_exchange_n(&(branchResults[state->pc >> 2].hasBeenTaken), &zero, (uint32_t)1, true, __ATOMIC_RELAXED, __ATOMIC_RELAXED);
				state->pc += (int32_t)imm;
			}
			else
			{
				uint32_t zero = 0;
				__atomic_compare_exchange_n(&(branchResults[state->pc >> 2].hasBeenSkipped), &zero, (uint32_t)1, true, __ATOMIC_RELAXED, __ATOMIC_RELAXED);
				state->pc += 4;
			}
			
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
				//printf("sign extended, %u, %d\n", imm, (int32_t)imm);
			}
			// funct3 again
			uint32_t memOffset = (state->x[rs1] + (int32_t)imm);

			uint32_t funct3 = (inst >> 12) & 0x7;
			uint32_t extra = 0;
			switch(funct3)
			{
				case 0x0: { extra = 0; break; }
				case 0x1: { extra = 1; break; }
				case 0x2: { extra = 3; break; }
				case 0x4: { extra = 0; break; }
				case 0x5: { extra = 1; break; }
			}

			// printf("memOffset, extra, %u, %u\n", memOffset, extra);
			// printf("reg value %u\n", state->x[rs1]);
			
			if(memOffset + extra >= memorySize)
			{
			    state->x[0] = -2;
			    return -2;
			}
			uint8_t* basePtr = memory;
			if(memOffset < programSize)
			{
				if(memOffset + extra >= programSize)
				{
					state->x[0] = -1;
					return -1;
				}
				basePtr = program;
			}
			
			switch(funct3)
			{
				case 0x0: // lb
				{
					uint8_t loaded = *(uint8_t*)(basePtr + memOffset);
					state->x[rd] = (loaded & (1 << 7)) ? loaded | 0xffffff00 : loaded;
					break;
				}
				case 0x1: // lh
				{
					uint16_t loaded = *(uint16_t*)(basePtr + memOffset);
					state->x[rd] = (loaded & (1 << 15)) ? loaded | 0xffff0000 : loaded;
					break;
				}
				case 0x2: // lw
				{
					state->x[rd] = *(uint32_t*)(basePtr + memOffset);
					break;
				}
				case 0x4: // lbu
				{
					uint8_t loaded = *(uint8_t*)(basePtr + memOffset);
					state->x[rd] = loaded & 0x000000ff;
					break;
				}
				case 0x5: // lhu
				{
					uint16_t loaded = *(uint16_t*)(basePtr + memOffset);
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

			// printf("Storing value: %u to: %u\n", state->x[rs2], (uint32_t)(state->x[rs1] + (int32_t)imm));
			
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // sb
				{
					*(uint8_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
					break;
				}
				case 0x1: // sh
				{
					*(uint16_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
					break;
				}
				case 0x2: // sw
				{
					*(uint32_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
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
					state->x[rd] = state->x[rs1] + (int32_t)imm;
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
					if((inst & (1 << 30)) == 0) // add
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

	return 0;
}

__device__ __inline__ int executeInstruction(State* state, uint32_t inst, uint8_t* memory, uint8_t* program, uint32_t memorySize, uint32_t programSize, BranchData* branchResults)
{
	// Normally this is the destination register, but in S and B type instructions
	// where there is not destination register these same bits communicate parts of an immediate
	// value. We always need to look at these bits as a unit no matter what
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
			state->pc = (state->x[rs1] + (int32_t)imm) & ~1;
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
			int32_t takeBranch = 0;
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // beq
				{
					if(state->x[rs1] == state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x1: // bne
				{
					if(state->x[rs1] != state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x4: // blt (this is signed)
				{
					if((int32_t)state->x[rs1] < (int32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x5: // bge (this is signed)
				{
					if((int32_t)state->x[rs1] >= (int32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x6: // bltu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] < (uint32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				case 0x7: // bgeu (this is unsigned)
				{
					if((uint32_t)state->x[rs1] >= (uint32_t)state->x[rs2]) { takeBranch = 1; }
					break;
				}
				// TODO: handle if it isn't one of these? Set trap maybe?
			}
			if(takeBranch)
			{
				atomicCAS(&(branchResults[state->pc >> 2].hasBeenTaken), (uint32_t)0, (uint32_t)1);
				state->pc += (int32_t)imm;
			}
			else
			{
				atomicCAS(&(branchResults[state->pc >> 2].hasBeenSkipped), (uint32_t)0, (uint32_t)1);
				state->pc += 4;
			}
			
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
				//printf("sign extended, %u, %d\n", imm, (int32_t)imm);
			}
			// funct3 again
			uint32_t memOffset = (state->x[rs1] + (int32_t)imm);

			uint32_t funct3 = (inst >> 12) & 0x7;
			uint32_t extra = 0;
			switch(funct3)
			{
				case 0x0: { extra = 0; break; }
				case 0x1: { extra = 1; break; }
				case 0x2: { extra = 3; break; }
				case 0x4: { extra = 0; break; }
				case 0x5: { extra = 1; break; }
			}

			// printf("memOffset, extra, %u, %u\n", memOffset, extra);
			// printf("reg value %u\n", state->x[rs1]);
			
			if(memOffset + extra >= memorySize)
			{
			    state->x[0] = -2;
			    return -2;
			}
			uint8_t* basePtr = memory;
			if(memOffset < programSize)
			{
				if(memOffset + extra >= programSize)
				{
					state->x[0] = -1;
					return -1;
				}
				basePtr = program;
			}
			
			switch(funct3)
			{
				case 0x0: // lb
				{
					uint8_t loaded = *(uint8_t*)(basePtr + memOffset);
					state->x[rd] = (loaded & (1 << 7)) ? loaded | 0xffffff00 : loaded;
					break;
				}
				case 0x1: // lh
				{
					uint16_t loaded = *(uint16_t*)(basePtr + memOffset);
					state->x[rd] = (loaded & (1 << 15)) ? loaded | 0xffff0000 : loaded;
					break;
				}
				case 0x2: // lw
				{
					state->x[rd] = *(uint32_t*)(basePtr + memOffset);
					break;
				}
				case 0x4: // lbu
				{
					uint8_t loaded = *(uint8_t*)(basePtr + memOffset);
					state->x[rd] = loaded & 0x000000ff;
					break;
				}
				case 0x5: // lhu
				{
					uint16_t loaded = *(uint16_t*)(basePtr + memOffset);
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

			// printf("Storing value: %u to: %u\n", state->x[rs2], (uint32_t)(state->x[rs1] + (int32_t)imm));
			
			switch((inst >> 12) & 0x7)
			{
				case 0x0: // sb
				{
					*(uint8_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
					break;
				}
				case 0x1: // sh
				{
					*(uint16_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
					break;
				}
				case 0x2: // sw
				{
					*(uint32_t*)(memory + (uint32_t)(state->x[rs1] + (int32_t)imm)) = state->x[rs2];
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
					state->x[rd] = state->x[rs1] + (int32_t)imm;
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
					if((inst & (1 << 30)) == 0) // add
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

	return 0;
}

__global__ void kernelExecuteProgram(uint8_t* program, uint8_t* globalMemory, uint32_t memorySize, int32_t argc, uint32_t argv, uint32_t programSize, uint32_t entry, Result* globalResults, uint32_t maxOps, BranchData* branchResults)
{
    uint32_t index = blockIdx.x * blockDim.x + threadIdx.x;

	uint8_t* memory = globalMemory + (memorySize * index);

	Result* myResults = globalResults + index;

	State state;

	for(int i = 0; i < 32; i++)
	{
		state.x[i] = 0;
	}

	state.pc = entry;

	uint32_t const DONE_ADDRESS_CUDA = 0xfffffff0;
	
	state.x[1] = DONE_ADDRESS_CUDA;
	state.x[2] = argv;

	state.x[10] = argc;
	state.x[11] = argv;

	int count = 0;
	while(count < maxOps)
	{
		uint32_t inst = *(uint32_t*)(program + state.pc);
		//printf("executing instruction: %08x\n", inst);
		//printf("pc = %u\n", state.pc);
		if(executeInstruction(&state, inst, memory, program, memorySize, programSize, branchResults) || state.pc == DONE_ADDRESS_CUDA)
		{
			break;
		}
		count++;
	}

	// if(index % 1000 == 0)
	// {
	// 	printf("my word was \"%s\" and i completed in %d cycles\n", (memory + *(uint32_t*)(memory + (argv + 4))), count);
	// }

	myResults->returnVal = state.x[10];
	myResults->errorCode = state.x[0]; // If we have an error, just write to x[0] and self destruct out of the loop
}

void classicalExecuteProgram(uint8_t* program, uint8_t* memory, uint32_t memorySize, int32_t argc, uint32_t argv, uint32_t programSize, uint32_t entry, Result* results, uint32_t maxOps, BranchData* branchResults)
{
	State state;
	for(int i = 0; i < 32; i++)
	{
		state.x[i] = 0;
	}
	state.pc = entry;
	uint32_t const DONE_ADDRESS_CLASSICAL = 0xfffffff0;
	
	state.x[1] = DONE_ADDRESS_CLASSICAL;
	state.x[2] = argv;

	state.x[10] = argc;
	state.x[11] = argv;

	int count = 0;
	while(count < maxOps)
	{
		uint32_t inst = *(uint32_t*)(program + state.pc);
		//printf("executing instruction: %08x\n", inst);
		if(classicalExecuteInstruction(&state, inst, memory, program, memorySize, programSize, branchResults) || state.pc == DONE_ADDRESS_CLASSICAL)
		{
			break;
		}
		count++;
	}

	results->returnVal = state.x[10];
    results->errorCode = state.x[0]; // If we have an error, just write to x[0] and self destruct out of the loop
}

int loadToMemory(int argc, char** argv, uint32_t INSTANCE_COUNT, uint32_t MEMORY_SIZE, uint8_t** pout, uint8_t** mout, Result** rout, BranchData** bout, uint32_t* psizeout, int32_t* acout, uint32_t* ssout, uint32_t* epout)
{
	if(argc < 4)
	{
        printf("Format: <program file to execute> <entry address as a number in hex> <args to be passed to subject program (at least 1)>");
        return 1;
    }

	// First step: program instructions
	// Reading the program instructions into a buffer
    FILE* programFile = fopen(argv[1], "rb");
    if(!programFile)
	{
        printf("Couldn't open program file \"%s\".\n", argv[1]);
        return 1;
    }
    fseek(programFile, 0, SEEK_END); 
    uint32_t const programSize = ftell(programFile);
    rewind(programFile);
	uint8_t* program = (uint8_t*)malloc(programSize);
    if(!program)
	{
        printf("Failed to allocate enough memory for the instructions for the emulator.\n");
        return 1;
    }
    fread(program, sizeof(uint8_t), programSize, programFile); // We're offset by 4 so we can force 0 addr to be special
	// At this point, host has the program instructions in memory

	// Second step: we need to initialize the state for the processor. This means setting register 0 to all 0s,
	// setting register 1 to the done address (right after last instruction in program), setting register 1 to the top of the stack,
	// setting register 10 to argc, and setting register 11 to argv. To calculate done address and top of stack, we just need to the
	// size of the program and the size of the argument strings, so that means we need to have the input already
	// We also need to set pc, which is constant across instances. All these things we pass when we invoke the kernel
	
	// Third step: input (we're going to base all of our program variability on argv)
	// So we need to produce images of the arguments to send to the device. This is going to reside just above the instance's stack
	// Basically: every instance needs space for initial stuff + some actual stack memory to execute with
	// Nothing is on the stack to start, we pass argc and argv by setting registers 10 and 11
	// So above the stack we have: actual strings, then pointers to them pointed to by argv, then the actual stack
	// So now we allocate the memory images for the program
	uint8_t* memory = (uint8_t*)malloc(MEMORY_SIZE * INSTANCE_COUNT);
	if(!memory)
	{
		printf("Failed to allocate enough memory for the emulator.\n");
		return 1;
	}
	memset(memory, 0, MEMORY_SIZE * INSTANCE_COUNT);
	// For now, we're literally just going to pass through arguments from our actual call of this program.
	// So argv[3..] correspond to argv[1..] in the subject program and argv[1] in our program is argv[0] in subject
	int32_t argcSubj = argc - 2;
	uint32_t* argvSubjOffsets = (uint32_t*)malloc(argcSubj * sizeof(uint32_t));
	argvSubjOffsets[0] = strlen(argv[1]) + 1;
	strncpy((char*)(memory + (MEMORY_SIZE - argvSubjOffsets[0])), argv[1], argvSubjOffsets[0]);
	for(int32_t i = 1; i < argcSubj; i++)
	{
		// Can't use stpcpy because we need to know size before hand because we are storing "backwards" because we only know
		// Higher address because stack grows down
		uint32_t tempLength = strlen(argv[i + 2]) + 1;
	    argvSubjOffsets[i] = tempLength + argvSubjOffsets[i - 1];
		if(argvSubjOffsets[i] > MEMORY_SIZE)
		{
			printf("MEMORY_SIZE insufficient to store arg strings for subject program\n");
			return 1;
		}
		strncpy((char*)(memory + (MEMORY_SIZE - argvSubjOffsets[i])), argv[i + 2], tempLength);
	}
	
	// Still need to copy the pointers to these
	uint32_t argvArrayEnd = argvSubjOffsets[argcSubj - 1];
	argvArrayEnd = argvArrayEnd + ((4 - (argvArrayEnd % 4)) % 4); // Alignment...
	if(argvArrayEnd + (4 * argcSubj) >= MEMORY_SIZE)
	{
		printf("MEMORY_SIZE insufficient to store arg strings for subject program\n");
		return 1;
	}
	for(int32_t i = 0; i < argcSubj; i++)
	{
		// All programs see their memory as offset relative to their own memory chunk so this is ok to copy
		*(uint32_t*)(memory + (MEMORY_SIZE - argvArrayEnd - (4 * (i + 1)))) = MEMORY_SIZE - argvSubjOffsets[argcSubj - i - 1];
	}
	// Now all args are copied to the first instances host memory, so we copy them to all the instances
	uint32_t stackStart = MEMORY_SIZE - (argvArrayEnd + (argcSubj * 4)); // Remember, starting stack pointer value is not usable immediately, dec first, so this ok

	char randBuf[32];
	uint32_t maxIn = (argvSubjOffsets[1] - argvSubjOffsets[0]);
	if(maxIn > 31)
	{
		maxIn = 31;
	}
	randBuf[maxIn] = '\0';
    srand(time(NULL));

	for(uint32_t i = 1; i < INSTANCE_COUNT; i++)
	{
		// Make sure memory size is big enough or problems will happen
		memcpy(memory + ((MEMORY_SIZE * i) + stackStart), memory + stackStart, MEMORY_SIZE - stackStart);

		for(int j = 0; j < maxIn; j++)
		{
			randBuf[j] = (rand() % 26) + 97;
		}
		strncpy((char*)(memory + (MEMORY_SIZE * i) + (MEMORY_SIZE - argvSubjOffsets[1])), randBuf, (argvSubjOffsets[1] - argvSubjOffsets[0]));
	}
	free(argvSubjOffsets);
	// Should now have both program and memory images on the device

	uint32_t entryPoint = (uint32_t)strtol(argv[2], NULL, 16);

	uint32_t programInstCount = programSize / 4;

	Result* localResults = (Result*)malloc(INSTANCE_COUNT * sizeof(Result));
	BranchData* localBranchData = (BranchData*)malloc(programInstCount * sizeof(BranchData));
	if(!localResults || !localBranchData)
	{
		printf("FAILED TO malloc results\n");
		return 1;
	}
	memset(localBranchData, 0, sizeof(BranchData) * programInstCount);

	*pout = program;
	*mout = memory;
	*rout = localResults;
	*bout = localBranchData;
	*psizeout = programSize;
	*acout = argcSubj;
	*ssout = stackStart;
	*epout = entryPoint;

	return 0;
}

int main(int argc, char** argv)
{
	int pid;
	int nproc;
	MPI_Init(&argc, &argv);
	MPI_Comm_rank(MPI_COMM_WORLD, &pid);
    MPI_Comm_size(MPI_COMM_WORLD, &nproc);
    MPI_Comm_set_errhandler(MPI_COMM_WORLD, MPI_ERRORS_ARE_FATAL);
    MPI_Barrier(MPI_COMM_WORLD);

	uint8_t* program;
	uint8_t* memory;
	Result* localResults;
	BranchData* localBranchData;
	uint32_t programSize;
	int32_t argcSubj;
	uint32_t stackStart;
	uint32_t entryPoint;

	uint8_t* deviceProgramImage;
	uint8_t* deviceMemoryImage;
	Result* deviceResultImage;
	BranchData* deviceBranchDataImage;

	uint8_t* spareMemory;

	dim3 blockDim(256);
	dim3 gridDim(16);

	uint32_t const MAX_OPS = 10000;	
	uint32_t const MEMORY_SIZE = 4 * 1024; // This needs to be 4 byte aligned or bad things happen because cuda memory access rules
	uint32_t INSTANCE_COUNT = 1;
	if(pid == 0)
	{
		INSTANCE_COUNT = blockDim.x * gridDim.x;

		if(loadToMemory(argc, argv, INSTANCE_COUNT, MEMORY_SIZE, &program, &memory, &localResults, &localBranchData, &programSize, &argcSubj, &stackStart, &entryPoint))
		{
			return 1;
		}
		cudaError_t programMallocErrorCode = cudaMalloc(&deviceProgramImage, programSize);
		if(programMallocErrorCode != cudaSuccess)
		{
			printf("FAILED TO CUDA MALLOC: %s\n", cudaGetErrorString(programMallocErrorCode));
			return 1;
		}

		cudaError_t mallocMemoryImageError = cudaMalloc(&deviceMemoryImage, MEMORY_SIZE * INSTANCE_COUNT);
		if(mallocMemoryImageError != cudaSuccess)
		{
			printf("FAILED TO CUDA MALLOC: %s\n", cudaGetErrorString(mallocMemoryImageError));
			return 1;
		}

		cudaError_t mallocResultImageError = cudaMalloc(&deviceResultImage, INSTANCE_COUNT * sizeof(Result));
		if(mallocResultImageError != cudaSuccess)
		{
			printf("FAILED TO CUDA MALLOC: %s\n", cudaGetErrorString(mallocResultImageError));
			return 1;
		}
		uint32_t programInstCount = programSize / 4;
		cudaError_t mallocBranchDataImageError = cudaMalloc(&deviceBranchDataImage, sizeof(BranchData) * (programInstCount));
		if(mallocBranchDataImageError != cudaSuccess)
		{
			printf("FAILED TO CUDA MALLOC: %s\n", cudaGetErrorString(mallocBranchDataImageError));
			return 1;
		}
		cudaMemcpy(deviceProgramImage, program, programSize, cudaMemcpyHostToDevice);
		cudaMemcpy(deviceBranchDataImage, localBranchData, sizeof(BranchData) * (programInstCount), cudaMemcpyHostToDevice);
		cudaMemcpy(deviceMemoryImage, memory, MEMORY_SIZE * INSTANCE_COUNT, cudaMemcpyHostToDevice);
	}
	else
	{
		if(loadToMemory(argc, argv, INSTANCE_COUNT, MEMORY_SIZE, &program, &memory, &localResults, &localBranchData, &programSize, &argcSubj, &stackStart, &entryPoint))
		{
			return 1;
		}

		spareMemory = (uint8_t*)malloc(MEMORY_SIZE * INSTANCE_COUNT);
		memcpy((spareMemory + stackStart), memory + stackStart, MEMORY_SIZE - stackStart);
	}

	int goodToGo = 1;
	MPI_Barrier(MPI_COMM_WORLD);
	auto startTime = std::chrono::high_resolution_clock::now();

	MPI_Request doneReq;

uint32_t argv1Len = 0; 

    uint32_t maxIn = 0; 

	if(pid != 0)
	{
		MPI_Irecv(&goodToGo,
				  1,
				  MPI_INT,
				  0,
				  0,
				  MPI_COMM_WORLD,
				  &doneReq);

		argv1Len = strlen((char*)(spareMemory + *(uint32_t*)(spareMemory + stackStart + 4)));
		maxIn = argv1Len;
		if(maxIn > 31)
		{
			maxIn = 31;
		}
	}

	uint64_t instancesRun = 0;

	while(goodToGo)
	{
		if(pid == 0)
		{
			//cudaMemcpy(deviceMemoryImage, memory, MEMORY_SIZE * INSTANCE_COUNT, cudaMemcpyHostToDevice);
			
			kernelExecuteProgram<<<gridDim, blockDim>>>(deviceProgramImage, deviceMemoryImage, MEMORY_SIZE, argcSubj, stackStart, programSize, entryPoint, deviceResultImage, MAX_OPS, deviceBranchDataImage);

			cudaError_t errorCode = cudaPeekAtLastError();
			if(errorCode != cudaSuccess)
			{
		        printf("FAILED TO LAUNCH KERNEL: %s\n", cudaGetErrorString(errorCode));
	        }
			cudaDeviceSynchronize();

			goodToGo = 0;
			for(int i = 1; i < nproc; i++)
			{
				MPI_Send(&goodToGo,
						 1,
						 MPI_INT,
						 i,
						 0,
						 MPI_COMM_WORLD);
			}
		}
		else
		{
			char randBuf[32];
			randBuf[maxIn] = '\0';
			for(int i = 0; i < maxIn; i++)
			{
				randBuf[i] = (rand() % 26) + 97;
			}
			
			for(int i = 0; i < INSTANCE_COUNT; i++)
			{
				memcpy(memory + ((MEMORY_SIZE * i) + stackStart), spareMemory + stackStart, MEMORY_SIZE - stackStart);
				// This is jsut beautiful -- we don't need to recalculate where argv[1] is because we have the stack LMAO
				char* argv1 = (char*)(memory + (MEMORY_SIZE * i) + *(uint32_t*)(spareMemory + stackStart + 4));
				strncpy(argv1, randBuf, maxIn);
			}
			
		    classicalExecuteProgram(program, memory, MEMORY_SIZE, argcSubj, stackStart, programSize, entryPoint, localResults, MAX_OPS, localBranchData);

			int flag = 0;
			MPI_Test(&doneReq, &flag, MPI_STATUS_IGNORE);
	    }
		instancesRun += INSTANCE_COUNT;
	}

	uint64_t totalInstancesRun = 0;
	MPI_Allreduce(&instancesRun, &totalInstancesRun, 1, MPI_UINT64_T, MPI_SUM, MPI_COMM_WORLD);
	
	auto midExecTime = std::chrono::high_resolution_clock::now();
	MPI_Barrier(MPI_COMM_WORLD);

	if(pid == 0)
	{
		cudaMemcpy(localBranchData, deviceBranchDataImage, sizeof(BranchData) * (programSize / 4), cudaMemcpyDeviceToHost);
	}

	// for(uint32_t i = 0; i < (programSize / 4); i++)
	// {
	// 	if((((uint32_t*)program)[i] & 0x7f) == 0x63)
	// 	{
	// 		printf("pid %d, Branch at address %x was", pid, i * 4);
	// 		if(localBranchData[i].hasBeenTaken) printf(" taken");
	// 		if(localBranchData[i].hasBeenSkipped) printf(" skipped");
	// 		printf("\n");
	// 	}
	// }

	MPI_Allreduce(MPI_IN_PLACE, localBranchData, 2 * (programSize / 4), MPI_UINT32_T, MPI_BOR, MPI_COMM_WORLD);
	auto finishTime = std::chrono::high_resolution_clock::now();
    printf("pid %d, Exec took %lu us, full + comm took %lu us, ran %lu instances\n", pid, std::chrono::duration_cast<std::chrono::microseconds>(midExecTime - startTime).count(), std::chrono::duration_cast<std::chrono::microseconds>(finishTime - startTime).count(), instancesRun);

	MPI_Barrier(MPI_COMM_WORLD);
	
	if(pid == 0)
	{
	    printf("Total of %lu instances run across %d processes, 1 of which used the gpu\n", totalInstancesRun, nproc);
		for(uint32_t i = 0; i < (programSize / 4); i++)
		{
			if((((uint32_t*)program)[i] & 0x7f) == 0x63)
			{
				printf("Branch at address %x was", i * 4);
				if(localBranchData[i].hasBeenTaken) printf(" taken");
				if(localBranchData[i].hasBeenSkipped) printf(" skipped");
				printf("\n");
			}
		}
	}

	MPI_Barrier(MPI_COMM_WORLD);
	
	if(pid == 0)
	{
		cudaFree(deviceProgramImage);
		cudaFree(deviceMemoryImage);
		cudaFree(deviceResultImage);
		cudaFree(deviceBranchDataImage);
	}
	else
	{		
		free(spareMemory);
	}

	free(memory);
	free(program);
	free(localResults);
	free(localBranchData);

	MPI_Finalize();

    return 0;

	// At this point, device has the program instructions in memory

	// Second step: we need to initialize the state for the processor. This means setting register 0 to all 0s,
	// setting register 1 to the done address (right after last instruction in program), setting register 1 to the top of the stack,
	// setting register 10 to argc, and setting register 11 to argv. To calculate done address and top of stack, we just need to the
	// size of the program and the size of the argument strings, so that means we need to have the input already
	// We also need to set pc, which is constant across instances. All these things we pass when we invoke the kernel
	
	// Third step: input (we're going to base all of our program variability on argv)
	// So we need to produce images of the arguments to send to the device. This is going to reside just above the instance's stack
	// Basically: every instance needs space for initial stuff + some actual stack memory to execute with
	// Nothing is on the stack to start, we pass argc and argv by setting registers 10 and 11
	// So above the stack we have: actual strings, then pointers to them pointed to by argv, then the actual stack
	// So now we allocate the memory images for the program
	// uint8_t* memory = (uint8_t*)malloc(MEMORY_SIZE * INSTANCE_COUNT);
	// if(!memory)
	// {
	// 	printf("Failed to allocate enough memory for the emulator.\n");
	// 	return 1;
	// }
	// memset(memory, 0, MEMORY_SIZE * INSTANCE_COUNT);
	// // For now, we're literally just going to pass through arguments from our actual call of this program.
	// // So argv[3..] correspond to argv[1..] in the subject program and argv[1] in our program is argv[0] in subject
	// int32_t argcSubj = argc - 2;
	// uint32_t* argvSubjOffsets = (uint32_t*)malloc(argcSubj * sizeof(uint32_t));
	// argvSubjOffsets[0] = strlen(argv[1]) + 1;
	// strncpy((char*)(memory + (MEMORY_SIZE - argvSubjOffsets[0])), argv[1], argvSubjOffsets[0]);
	// for(int32_t i = 1; i < argcSubj; i++)
	// {
	// 	// Can't use stpcpy because we need to know size before hand because we are storing "backwards" because we only know
	// 	// Higher address because stack grows down
	// 	uint32_t tempLength = strlen(argv[i + 2]) + 1;
	//     argvSubjOffsets[i] = tempLength + argvSubjOffsets[i - 1];
	// 	if(argvSubjOffsets[i] > MEMORY_SIZE)
	// 	{
	// 		printf("MEMORY_SIZE insufficient to store arg strings for subject program\n");
	// 		return 1;
	// 	}
	// 	strncpy((char*)(memory + (MEMORY_SIZE - argvSubjOffsets[i])), argv[i + 2], tempLength);
	// }
	
	// // Still need to copy the pointers to these
	// uint32_t argvArrayEnd = argvSubjOffsets[argcSubj - 1];
	// argvArrayEnd = argvArrayEnd + ((4 - (argvArrayEnd % 4)) % 4); // Alignment...
	// if(argvArrayEnd + (4 * argcSubj) >= MEMORY_SIZE)
	// {
	// 	printf("MEMORY_SIZE insufficient to store arg strings for subject program\n");
	// 	return 1;
	// }
	// for(int32_t i = 0; i < argcSubj; i++)
	// {
	// 	// All programs see their memory as offset relative to their own memory chunk so this is ok to copy
	// 	*(uint32_t*)(memory + (MEMORY_SIZE - argvArrayEnd - (4 * (i + 1)))) = MEMORY_SIZE - argvSubjOffsets[argcSubj - i - 1];
	// }
	// // Now all args are copied to the first instances host memory, so we copy them to all the instances
	// uint32_t stackStart = MEMORY_SIZE - (argvArrayEnd + (argcSubj * 4)); // Remember, starting stack pointer value is not usable immediately, dec first, so this ok
	// char randBuf[4];
	// randBuf[3] = '\0';
	// srand(pid * 43214 + 321);
	// for(uint32_t i = 1; i < INSTANCE_COUNT; i++)
	// {
	// 	// Make sure memory size is big enough or problems will happen
	// 	memcpy(memory + ((MEMORY_SIZE * i) + stackStart), memory + stackStart, MEMORY_SIZE - stackStart);

	// 	randBuf[0] = (rand() % 26) + 97;
	// 	randBuf[1] = (rand() % 26) + 97;
	// 	randBuf[2] = (rand() % 26) + 97;
	// 	strncpy((char*)(memory + (MEMORY_SIZE * i) + (MEMORY_SIZE - argvSubjOffsets[1])), randBuf, (argvSubjOffsets[1] - argvSubjOffsets[0]));
	// }
	// // Finally can copy all of them to device... a little wasteful, since much of this will be zeroes, but I figure better than many small calls
	// // could theoretically seperate these regions of memory but would require complex redirect system on emulator memory system...

	// free(argvSubjOffsets);
	// // Should now have both program and memory images on the device

	// uint32_t entryPoint = (uint32_t)strtol(argv[2], NULL, 16);

	// // Oh, and we have to set up a place for return values + important codes

	// Result* localResults = (Result*)malloc(INSTANCE_COUNT * sizeof(Result));
	// BranchData* localBranchData = (BranchData*)malloc(programInstCount * sizeof(BranchData));
	// if(!localResults || !localBranchData)
	// {
	// 	printf("FAILED TO malloc results\n");
	// 	return 1;
	// }

	// auto startTime = std::chrono::high_resolution_clock::now();
	// //



	// auto finishTime = std::chrono::high_resolution_clock::now();

	// printf("Kernel took %lu us\n", std::chrono::duration_cast<std::chrono::microseconds>(finishTime - startTime).count());

	// // Print results
	// //cudaMemcpy(localResults, deviceResultImage, sizeof(Result) * INSTANCE_COUNT, cudaMemcpyDeviceToHost);

	// for(uint32_t i = 0; i < INSTANCE_COUNT; i++)
	// {
	// 	printf("Instance %u: return %d, errorCode %d\n", i, localResults[i].returnVal, localResults[i].errorCode);
	// }
	// free(localResults);

	// //cudaMemcpy(localBranchData, deviceBranchDataImage, sizeof(BranchData) * programInstCount, cudaMemcpyDeviceToHost);

	// for(uint32_t i = 0; i < programInstCount; i++)
	// {
	// 	if((((uint32_t*)program)[i] & 0x7f) == 0x63)
	// 	{
	// 		printf("Branch at address %x was", i * 4);
	// 		if(localBranchData[i].hasBeenTaken) printf(" taken");
	// 		if(localBranchData[i].hasBeenSkipped) printf(" skipped");
	// 		printf("\n");
	// 	}
	// }

    // MPI_Barrier(MPI_COMM_WORLD);
	// printf("NOW ALL REDUCING\n");

	// MPI_Allreduce(MPI_IN_PLACE, localBranchData, 2 * programInstCount, MPI_UINT32_T, MPI_BOR, MPI_COMM_WORLD);

	// for(uint32_t i = 0; i < programInstCount; i++)
	// {
	// 	if((((uint32_t*)program)[i] & 0x7f) == 0x63)
	// 	{
	// 		printf("Branch at address %x was", i * 4);
	// 		if(localBranchData[i].hasBeenTaken) printf(" taken");
	// 		if(localBranchData[i].hasBeenSkipped) printf(" skipped");
	// 		printf("\n");
	// 	}
	// }
	// free(localBranchData);

	// // Printing memory dumps
	// //cudaMemcpy(memory, deviceMemoryImage, sizeof(uint8_t) * MEMORY_SIZE * INSTANCE_COUNT, cudaMemcpyDeviceToHost);

	// // uint32_t const BYTES_PER_LINE = 4 * 4;
	// // for(uint32_t j = 0; j < INSTANCE_COUNT; j++)
	// // {
	// // 	for(uint32_t i = 0; i < MEMORY_SIZE - programSize; i += 1)
	// // 	{
	// // 		if(MEMORY_SIZE - i == stackStart)
	// // 		{
	// // 			printf("\n");
	// // 		}
	// // 		if(i % BYTES_PER_LINE == 0)
	// // 		{
	// // 			printf("\n");
	// // 		}
	// // 		printf("%02x ", *(uint8_t*)(memory + (j * MEMORY_SIZE) + MEMORY_SIZE - i - 1));
	// // 	}
	// // 	printf("\n");
	// // }
   
	
    // free(memory);
	// free(program);

}
