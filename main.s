// Generate a byte-mode QR Code (v1-4)
            .data
            .balign 4

            // OS Constants
            .equ STDOUT, 0

            .equ EXIT,   1
            .equ READ,   3
            .equ WRITE,  4
            .equ OPEN,   5
            .equ CLOSE,  6
            .equ CREATE, 8

            // Program Constants
            .equ MAX_VERSION, 3     // max version supported (1-4)
            .equ MODE, 0b0100       // byte encoding mode (nibble)

            // Error Messages
err_01:     .asciz "Invalid error correction level.\n"
            .equ err_01_len, (.-err_01)

err_02:     .asciz "Only QR versions 1-4 are supported.\n"
            .equ err_02_len, (.-err_02)

            // Variables
msg:        .asciz "https://github.com/barrettotte"
            .equ msg_len, (.-msg)   // (30 chars) TODO: from cmd line args

version:    .space 1                // QR version
eclvl_idx:  .space 1                // error correction level index (L,M,Q,H)
eclvl:      .space 1                // error correction level value (1,0,3,2)
ecprop_idx: .space 1                // error correction properties index
capacity:   .space 1                // max capacity for data words
ecw_block:  .space 1                // error correction words per block
g1_blocks:  .space 1                // number of blocks in group 1
g1b_words:  .space 1                // data words in each group 1 block
count_ind:  .space 1                // character count indicator byte
payload:    .space 80               // max possible payload length (v4-L)

            // Lookup Tables
tbl_eclvl:                          // error correction level lookup
            .byte 1, 0, 3, 2        // L, M, Q, H

tbl_version: //   L, M, Q, H        // version lookup
            .byte 17, 14, 11, 7     // v1
            .byte 32, 26, 20, 14    // v2
            .byte 53, 42, 32, 24    // v3
            .byte 78, 62, 46, 34    // v4

tbl_ecprops:                        // error correction config lookup
            //    0: capacity in bytes
            //    1: error correction words per block
            //    2: blocks in group 1
            //    3: data words in each group 1 block
            .byte 19, 7, 1, 19      //  0: v1-L
            .byte 16, 10, 1, 16     //  1: v1-M
            .byte 13, 13, 1, 13     //  2: v1-Q
            .byte 9, 17, 1, 9       //  3: v1-H
            .byte 34, 10, 1, 34     //  4: v2-L
            .byte 28, 16, 1, 28     //  5: v2-M
            .byte 22, 22, 1, 22     //  6: v2-Q
            .byte 16, 28, 1, 16     //  7: v2-H
            .byte 55, 15, 1, 55     //  8: v3-L
            .byte 44, 26, 1, 44     //  9: v3-M
            .byte 34, 18, 2, 17     // 10: v3-Q
            .byte 26, 22, 2, 13     // 11: v3-H
            .byte 80, 20, 1, 80     // 12: v4-L
            .byte 64, 18, 2, 32     // 13: v4-M
            .byte 48, 26, 2, 24     // 14: v4-Q
            .byte 36, 16, 4, 9      // 15: v4-H

            .text
            .global _start
_start:                             // ***** program entry point *****
            mov  r0, #0             // i = 0
            mov  r1, #msg_len       // length;  TODO: get from command line args
            ldr  r2, =msg           // pointer; TODO: get from command line args
/*
msg_loop:                           // ***** loop over message (debug) *****
            ldrb r3, [r2, r0]       // msg[i]
            add  r0, r0, #1         // i++
            cmp  r0, r1             // compare registers
            ble  msg_loop           // i <= msg_len
*/
save_args:                          // ***** save command line arguments to memory *****
            mov  r0, #2             // TODO: get from command line args  offset 2=Q
            ldr  r1, =eclvl_idx     // pointer to error correction index
            strb r0, [r1]           // store error correction index

set_eclvl:                          // ***** set error correction level *****
            ldr  r1, =eclvl_idx     // pointer to error correction index
            ldrb r0, [r1]           // load error correction index
            mov  r1, #4             // size of error correction table
            cmp  r0, r1             // check error correction
            bhi  bad_eclvl          // branch if error correction invalid

            ldr  r1, =tbl_eclvl     // pointer to error correction table
            ldrb r0, [r1, r0]       // lookup error correction value
            ldr  r1, =eclvl         // pointer to error correction level
            strb r0, [r1]           // save error correction level

find_version:                       // ***** find QR version *****
            mov  r0, #0             // version = 0 (v1)
            ldr  r1, =eclvl_idx     // pointer to error correction index
            ldrb r1, [r1]           // i = eclvl
            ldr  r2, =tbl_version   // pointer to version table
            mov  r3, #msg_len       // load message length
            sub  r3, r3, #1         // msg_len --; null terminator  (TODO: remove ?)
            ldr  r4, =count_ind     // pointer to char count indicator
            strb r3, [r4]           // save msg_len-1 as char count indicator byte
            mov  r4, #MAX_VERSION   // load max QR version supported

version_loop:                       // ***** Search version lookup table *****
            ldrb r5, [r2, r1]       // msg capacity = tbl_version[(i * 4) + eclvl]
            cmp  r5, r3             // compare msg capacity to msg_len
            bgt  set_version        // msg capacity > msg_len

            add  r0, r0, #1         // version += 1
            add  r1, r1, #4         // i += 4
            cmp  r0, r4             // compare version to max version
            blt  version_loop       // version < MAX_VERSION
            b    bad_version        // unsupported version

set_version:                        // ***** set QR version (zero indexed) *****
            ldr  r1, =version       // pointer to version
            strb r0, [r1]           // save version to memory

set_ec_props:                       // ***** set error correction properties *****
            lsl  r0, #4             // i = version * 16
            ldr  r1, =eclvl_idx     // pointer to error correction level index
            ldrb r1, [r1]           // load error correction level index
            lsl  r1, #2             // j = eclvl_idx * 4
            add  r0, r0, r1         // i += j == (version * 16) + (eclvl_idx * 4)

            ldr  r1, =ecprop_idx    // pointer to error correction properties index
            strb r0, [r1]           // save error correction properties index
            ldr  r1, =tbl_ecprops   // pointer to error correction properties
            ldrb r0, [r1, r0]       // load max data word capacity from EC properties
            ldr  r1, =capacity      // pointer to max capacity
            strb r0, [r1]           // save max capacity
            
            // TODO: set ecw_block from ec props
            // TODO: set g1_blocks from ec props
            // TODO: set g1b_words from ec props

init_payload:                       // ***** Init QR code payload *****
            mov  r1, #MODE          // load mode nibble
            lsl  r1, r1, #4         // shift nibble from low to high
            ldr  r2, =count_ind     // pointer to char count indicator
            ldrb r2, [r2]           // load char count indicator byte
            lsr  r3, r3, #4         // drop count indicator low nibble
            orr  r0, r1, r3         // combine mode with count indicator high byte

            // load high nibble of first char of payload before looping

            nop
            // TODO: everything after here needs refactoring

            ldr  r4, =payload       // pointer to payload
            strb r1, [r4]           // payload[0] = BYTE_ZERO
            add  r3, r3, #1         // i = msg_len + BYTE_ZERO

pad_loop:                           // ***** Pad payload with alternating bytes *****
            cmp  r3, r0             // compare payload size with max capacity
            bgt  split_payload      // i > capacity, pad finished
            mov  r2, #0xEC          // set pad byte
            strb r2, [r4, r3]       // payload[i] = 0xEC
            add  r3, r3, #1         // i++

            cmp  r3, r0             // compare payload size with max capacity
            bgt  split_payload      // i > capacity, pad finished
            mov  r2, #0x11          // set pad byte
            strb r2, [r4, r3]       // payload[i] = 0x11
            add  r3, r3, #1         // i++
            b    pad_loop           // while (i < capacity)

split_payload:                      // ***** Split payload to blocks and groups *****
            // TODO: write payload bytes to file for checking!
            b    tmp_done

tmp_done:                           // TODO: temporary label
            b    _end               // TODO: skip over errors

            // TODO:
            //  - Payload split to groups + blocks
            //  - Reed-Solomon error correction
            //    - Galois field lookup and arithmetic
            //    - Polynomial arithmetic
            //    - Generator polynomial
            //  - Interleave data and error correction data
            //  - Remainder bits
            //  - Create/write image file with QR matrix data
            //  - QR matrix init
            //    - leave quiet zone untouched
            //    - reserved areas
            //    - timing patterns
            //    - finders
            //    - alignment pattern and dark module
            //  - Zigzag QR data
            //  - Mask QR - hardcoded to ?
            //  - Format bits calculation
            //  - Format bits placement adjacent to finders
            // 
            //  Import files:
            //    - galois.s
            //    - polynomial.s
            //    - reed-solomon.s ?
            //
bad_eclvl:                          // ***** invalid error correction level *****
            mov  r7, #WRITE         // syscall number
            mov  r0, #STDOUT        // file descriptor
            ldr  r1, =err_01        // pointer to buffer address
            mov  r2, #err_01_len    // length
            svc  #0                 // invoke syscall
            b    _end               // exit program

bad_version:                        // ***** invalid version *****
            mov  r7, #WRITE         // syscall number
            mov  r0, #STDOUT        // file descriptor
            ldr  r1, =err_02        // pointer to buffer address
            mov  r2, #err_02_len    // length
            svc  #0                 // invoke syscall
            b    _end               // exit program

_end:                               // ***** terminate program *****
            mov  r7, #EXIT          // syscall number
            mov  r0, #0             // exit status
            svc  #0                 // invoke syscall
            .end                    // end of source
