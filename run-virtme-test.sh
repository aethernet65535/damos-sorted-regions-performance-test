#!/bin/bash

KERNEL_DIR="/home/user/65535/workspace/oss/linux/kernel/linux_mainline"

echo "START AUTOMATIC TEST!"

echo "START VANILLA!"
vng --run $KERNEL_DIR --rw --memory 8G --cpus 12 --cwd /home/user/65535/workspace/lab/damos-sorted-regions-performance-test --exec "./damon-test.sh vanilla"
echo "VANILLA DONE!"

echo "START DAMON!"
vng --run $KERNEL_DIR --rw --memory 8G --cpus 12 --cwd /home/user/65535/workspace/lab/damos-sorted-regions-performance-test --exec "./damon-test.sh damon"
echo "DAMON DONE!"

echo "START PATCHED!"
vng --run $KERNEL_DIR --rw --memory 8G --cpus 12 --cwd /home/user/65535/workspace/lab/damos-sorted-regions-performance-test --exec "./damon-test.sh damon-optimized"
echo "PATCHED DONE!"

echo "ALL DONE!"
