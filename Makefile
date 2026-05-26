format:
	find rtl -type f \( -name "*.v" -o -name "*.sv" \) \
	| xargs verible-verilog-format --inplace 
