# Creating a binfile (raw instructions in .text)

riscv32-unknown-linux-gnu-gcc -c main.c -o test.o -march=rv32id -mabi=ilp32d ; riscv32-unknown-linux-gnu-objcopy -O binary -j .text test.o binfile

# Sanity check to see if our binfile is what we think it is

riscv32-unknown-linux-gnu-objdump -m riscv -b binary -D binfile 
