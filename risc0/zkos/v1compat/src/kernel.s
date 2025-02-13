// Copyright 2024 RISC Zero, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

.equ USER_START_ADDR, 0x00010000
.equ STACK_TOP, 0xfff00000
.equ USER_REGS_ADDR, 0xffff0080
.equ MEPC_ADDR, 0xffff0200
.equ GLOBAL_OUTPUT_ADDR, 0xffff0240
.equ ECALL_DISPATCH_ADDR, 0xffff1000
.equ ECALL_TABLE_SIZE, 7
.equ HOST_ECALL_TERMINATE, 0
.equ HOST_ECALL_READ, 1
.equ HOST_ECALL_SHA, 4
.equ WORD_SIZE, 4
.equ MAX_IO_BYTES, 1024
.equ REG_T0, 5
.equ REG_A0, 10
.equ REG_A1, 11
.equ REG_A2, 12
.equ REG_A3, 13
.equ REG_A4, 14

.section .text
.global _start
_start:
    # Load the global pointer from the place the linker put it
    # Note: we definitely don't want this relaxed since the GP is invalid
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    # Set the kernel stack pointer near the top of kernel memory
    li sp, STACK_TOP

    # Initialize the ecall dispatch table
    li t0, ECALL_DISPATCH_ADDR
    la t1, _ecall_dispatch
    sw t1, 0(t0)

    # Initialize useful constants
    li t3, USER_REGS_ADDR
    la t4, _ecall_table
    li t5, ECALL_TABLE_SIZE
    li t6, MAX_IO_BYTES

    # Load the user program entry into MEPC
    li a0, USER_START_ADDR
    li a1, MEPC_ADDR
    lw a2, 0(a0)
    addi a2, a2, -WORD_SIZE
    sw a2, 0(a1)

    # Jump into userspace
    mret

_ecall_table:
    j _ecall_halt
    fence # input
    j _ecall_software
    j _ecall_sha
    fence # bigint
    fence # user
    fence # bigint2

_ecall_dispatch:
    # load t0 from userspace
    lw a0, REG_T0 * WORD_SIZE (t3)
    # check that ecall request is within range
    bge a0, t5, 1f
    # adjust index so that it points to word sized entries
    slli a0, a0, 2
    # compute the table entry
    add a1, t4, a0
    # jump into dispatch table
    jr a1
1:
    fence # panic

_ecall_halt:
    # copy output digest from pointer in a1 to GLOBAL_OUTPUT_ADDR
    lw t0, REG_A1 * WORD_SIZE (t3) # out_state
    li t1, GLOBAL_OUTPUT_ADDR
    lw t2, 0(t0)
    sw t2, 0(t1)
    lw t2, 4(t0)
    sw t2, 4(t1)
    lw t2, 8(t0)
    sw t2, 8(t1)
    lw t2, 12(t0)
    sw t2, 12(t1)
    lw t2, 16(t0)
    sw t2, 16(t1)
    lw t2, 20(t0)
    sw t2, 20(t1)
    lw t2, 24(t0)
    sw t2, 24(t1)
    lw t2, 28(t0)
    sw t2, 28(t1)

    li a7, HOST_ECALL_TERMINATE
    lw a0, REG_A0 * WORD_SIZE (t3) # user_exit
    li a1, 0
    ecall

_ecall_software:
    # prepare a software ecall
    li a7, HOST_ECALL_READ
    lw a0, REG_A2 * WORD_SIZE (t3) # syscall_ptr -> fd
    lw a1, REG_A0 * WORD_SIZE (t3) # from_host_ptr -> buf
    lw a2, REG_A1 * WORD_SIZE (t3) # from_host_len -> len
    slli a2, a2, 2

    # check if length is > 1024
    bltu t6, a2, 1f

    # call the host
    ecall

    # read (a0, a1) back from host
    # fd == 0 means read (a0, a1) from host
    li a0, 0
    # read into user registers starting at a0
    addi a1, t3, REG_A0 * WORD_SIZE
    # read two words from host
    li a2, 2 * WORD_SIZE
    # call the host
    ecall

    # return back to userspace
    mret
1:
    j ecall_software

_ecall_sha:
    lw a0, REG_A0 * WORD_SIZE (t3) # out_state
    lw a1, REG_A1 * WORD_SIZE (t3) # in_state
    lw a2, REG_A2 * WORD_SIZE (t3) # block_ptr1
    lw a3, REG_A3 * WORD_SIZE (t3) # block_ptr2
    lw a4, REG_A4 * WORD_SIZE (t3) # count
    j ecall_sha
