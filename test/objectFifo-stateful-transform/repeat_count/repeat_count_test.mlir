//===- repeat_count_test.mlir -----------------------------------*- MLIR -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Copyright (C) 2024, Advanced Micro Devices, Inc.
//
//===----------------------------------------------------------------------===//

// RUN: aie-opt --aie-objectFifo-stateful-transform %s | FileCheck %s

// CHECK: module @repeatCount {
// CHECK:   aie.device(npu1) {
// CHECK:     memref.global "public" @of1_cons : memref<16xi32>
// CHECK:     memref.global "public" @of1 : memref<16xi32>
// CHECK:     %{{.*}}tile_1_2 = aie.tile(1, 2)
// CHECK:     %{{.*}}tile_1_3 = aie.tile(1, 3)
// CHECK:     %of1_cons_buff_0 = aie.buffer(%{{.*}}tile_1_3) {sym_name = "of1_cons_buff_0"} : memref<16xi32> 
// CHECK:     %of1_cons_prod_lock = aie.lock(%{{.*}}tile_1_3, 0) {init = 1 : i32, sym_name = "of1_cons_prod_lock"}
// CHECK:     %of1_cons_cons_lock = aie.lock(%{{.*}}tile_1_3, 1) {init = 0 : i32, sym_name = "of1_cons_cons_lock"}
// CHECK:     %of1_buff_0 = aie.buffer(%{{.*}}tile_1_2) {sym_name = "of1_buff_0"} : memref<16xi32> 
// CHECK:     %of1_prod_lock = aie.lock(%{{.*}}tile_1_2, 0) {init = 3 : i32, sym_name = "of1_prod_lock"}
// CHECK:     %of1_cons_lock = aie.lock(%{{.*}}tile_1_2, 1) {init = 0 : i32, sym_name = "of1_cons_lock"}
// CHECK:     aie.flow(%{{.*}}tile_1_2, DMA : 0, %{{.*}}tile_1_3, DMA : 0)
// CHECK:     func.func @some_work(%arg0: memref<16xi32>) {
// CHECK:       return
// CHECK:     }
// CHECK:     %core_1_2 = aie.core(%{{.*}}tile_1_2) {
// CHECK:       %c0 = arith.constant 0 : index
// CHECK:       %c1 = arith.constant 1 : index
// CHECK:       %c12 = arith.constant 12 : index
// CHECK:       scf.for %arg0 = %c0 to %c12 step %c1 {
// CHECK:         aie.use_lock(%of1_prod_lock, AcquireGreaterEqual, 3)
// CHECK:         func.call @some_work(%of1_buff_0) : (memref<16xi32>) -> ()
// CHECK:         aie.use_lock(%of1_cons_lock, Release, 3)
// CHECK:       }
// CHECK:       aie.end
// CHECK:     }
// CHECK:     %mem_1_2 = aie.mem(%{{.*}}tile_1_2) {
// CHECK:       %0 = aie.dma_start(MM2S, 0, ^bb1, ^bb2, repeat_count = 2)
// CHECK:     ^bb1:  // 2 preds: ^bb0, ^bb1
// CHECK:       aie.use_lock(%of1_cons_lock, AcquireGreaterEqual, 1)
// CHECK:       aie.dma_bd(%of1_buff_0 : memref<16xi32>, 0, 16)
// CHECK:       aie.use_lock(%of1_prod_lock, Release, 1)
// CHECK:       aie.next_bd ^bb1
// CHECK:     ^bb2:  // pred: ^bb0
// CHECK:       aie.end
// CHECK:     }
// CHECK:     %mem_1_3 = aie.mem(%{{.*}}tile_1_3) {
// CHECK:       %0 = aie.dma_start(S2MM, 0, ^bb1, ^bb2)
// CHECK:     ^bb1:  // 2 preds: ^bb0, ^bb1
// CHECK:       aie.use_lock(%of1_cons_prod_lock, AcquireGreaterEqual, 1)
// CHECK:       aie.dma_bd(%of1_cons_buff_0 : memref<16xi32>, 0, 16)
// CHECK:       aie.use_lock(%of1_cons_cons_lock, Release, 1)
// CHECK:       aie.next_bd ^bb1
// CHECK:     ^bb2:  // pred: ^bb0
// CHECK:       aie.end
// CHECK:     }
// CHECK:   }
// CHECK: }

module @repeatCount {
 aie.device(npu1) {
    %tile12 = aie.tile(1, 2)
    %tile13 = aie.tile(1, 3)

    aie.objectfifo @of1 (%tile12, {%tile13}, 1 : i32) {repeat_count = 3 : i32} : !aie.objectfifo<memref<16xi32>>

    func.func @some_work(%lineOut : memref<16xi32>) -> () {
       return
    }

    %core12 = aie.core(%tile12) {
      %c0 = arith.constant 0 : index
      %c1 = arith.constant 1 : index
      %height = arith.constant 12 : index

      scf.for %indexInHeight = %c0 to %height step %c1 {
         %subview = aie.objectfifo.acquire @of1 (Produce, 1) : !aie.objectfifosubview<memref<16xi32>>
         %elem0 = aie.objectfifo.subview.access %subview[0] : !aie.objectfifosubview<memref<16xi32>> -> memref<16xi32>
         func.call @some_work(%elem0) : (memref<16xi32>) -> ()
         aie.objectfifo.release @of1 (Produce, 1)
      }

      aie.end
   }
 }
}
