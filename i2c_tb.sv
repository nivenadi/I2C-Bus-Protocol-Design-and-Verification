// -------------------- ECE 560: ASSERTION BASED VEIFICATION ------------------------
// -------------------- PROJECT: VERIFICATION OF I2C PROTOCOL -----------------------
// Term: Fall 2024
// Authors: Nivedita

module tb_i2c_master_slave;

    // Testbench Signals
    logic clk, rst;
    logic [7:0] data_in;
    logic rw;
    logic [6:0] addr;
    logic [7:0] data_out;
    logic done;

    // Parameters for the testbench
    parameter CLK_PERIOD = 10;

    // DUT Instantiation
    i2c_master_slave dut (
        .clk(clk),
        .rst(rst),
        .data_in(data_in),
        .rw(rw),
        .addr(addr),
        .data_out(data_out),
        .done(done)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Testbench Logic
    initial begin
        // Initialize signals
        clk = 0;
        rst = 1;
        data_in = 8'h00;
        rw = 0;
        addr = 7'h42; // Example 7-bit address

        // Reset sequence
        #(2 * CLK_PERIOD);
        rst = 0;

        // Write operation
        rw = 1;                // Write operation
        data_in = 8'hA5;       // Data to write
        addr = 7'h42;          // Target slave address
        
		wait(done);
		
        // Read operation
        rw = 0;                // Read operation
        addr = 7'h42;          // Target slave address
        #(30 * CLK_PERIOD);  // Wait for the read operation to complete

        // Check results
        if (data_out == 8'hA5) begin
            $display("[PASS] Data read matches data written: %h", data_out);
        end else begin
            $display("[FAIL] Data mismatch. Expected: A5, Got: %h", data_out);
        end

        // End simulation
        $finish;
    end

endmodule