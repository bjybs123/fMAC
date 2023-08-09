
testbench: fmac.sv tb.sv
	iverilog -g2012 -o testbench -D DEBUG fmac.sv tb.sv

test: testbench
	vvp testbench

show:
	gtkwave testbench.vcd


clean:
	rm -rf testbench testbench.vcd
