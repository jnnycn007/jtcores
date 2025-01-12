#!/bin/bash -e
echo "ERROR: compilation error" > sim.log
HDL=../../../hdl
iverilog -g2012 test.v $HDL/video/jtframe_tilemap.v $HDL/video/jtframe_vtimer.v ../../../../cores/gng/hdl/jtgng_timer.v -o sim -DSIMULATION # && sim -lxt | tee sim.log
./sim -lxt +define+SIZE_TEST | tee sim.log
./sim -lxt +param+test.BPP=2 | tee -a sim.log
rm -f sim
if grep ERROR sim.log; then
	echo FAIL
	exit 1
else
	echo PASS
fi