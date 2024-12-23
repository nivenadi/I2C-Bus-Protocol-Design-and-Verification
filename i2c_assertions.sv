// -------------------- ECE 560: ASSERTION BASED VEIFICATION ------------------------
// -------------------- PROJECT: VERIFICATION OF I2C PROTOCOL -----------------------
// Term: Fall 2024
// Authors: Nivedita
	
module i2c_assert(
	input logic clk, rst,              // System clock and reset
    input logic [7:0] data_in,         // Data to be sent by master
    input logic rw,                    // Read/Write control: 1 for write, 0 for read
    input logic [6:0] addr,            // 7-bit I2C address
    input logic [7:0] data_out,       // Output data from slave
    input logic done,                  // Completion signal
    // I²C Bus Lines
    input logic scl, scl_en, sda_in,
    input logic [7:0] data_wr,
	input logic sda,
	input logic master_drive,
    input master_state_t master_state, next_master_state,
    input state_t current_state, next_state,
    // Slave Memory
    input logic [7:0] mem [127:0],      // 128 x 8-bit memory
    input logic [6:0] slave_addr,
    // Internal Signals
    input logic [3:0] bit_count,             // To count transmitted/received bits of master
    input logic [7:0] master_write_reg,      // For serializing/deserializing data
    input logic [7:0] master_read_reg,      // For serializing/deserializing data 
    // Internal signals
    input logic sda_out,         // Drive value for SDA
    input logic [7:0] data_reg,   // Data shift register
    input logic [7:0] addr_reg,    // Address register
    input logic [3:0] slave_count, // Bit counter (0 to 7)
	input logic slave_drive //Indicates if slave is driving sda
	);

	property stable_addr;
		disable iff(rst)
		(master_state == START) |-> $stable(addr) until done;
	endproperty
	
	property stable_rw;
		disable iff(rst)
		(master_state == START) |-> $stable(rw) until done;
	endproperty
	
	property stable_data_in;
		disable iff(rst)
		(master_state == START) |-> $stable(data_in) until done;
	endproperty

	assume property (@(posedge clk) stable_addr);
	assume property (@(posedge clk) stable_rw);
	assume property (@(posedge clk) stable_data_in);
	
 	//1. Start condition  - Passed
	property p_start_condition;
        @(posedge clk)
		disable iff(rst)
        (master_state == START) |-> ($fell(sda) && scl);
    endproperty
    a_start_condition: assert property(p_start_condition);

	//2. Slave addr ack handling - Passed
	property p_ack_1;
		@(posedge clk)
		disable iff(rst)
		(current_state == ADDR_ACK) |-> (!sda_in && !sda && slave_drive);
	endproperty
	a_ack_1: assert property(p_ack_1);
	
	//3. Slave data ack handling - Passed
	property p_ack_2;
		@(posedge clk)
		disable iff(rst)
		(current_state == DATA_ACK) |-> (!sda_in && !sda && slave_drive);
	endproperty
	a_ack_2: assert property(p_ack_2);
	
    // 4. Stop Condition Detection - Passed
    property p_stop_condition;
        @(posedge clk)
		disable iff(rst)
        (master_state == STOP) |-> ($rose(sda) && scl);
    endproperty
    a_stop_condition: assert property(p_stop_condition);

    // 5. Address Transmission
    property p_addr_transfer;
		logic [6:0] addr_in;
        @(posedge clk)
		disable iff(rst)
        ((master_state == START), addr_in = addr) |-> ##9 ((current_state == ADDR_ACK) && slave_addr == addr_in);
    endproperty
    a_addr_transfer: assert property(p_addr_transfer);
	
	// 6. Address Transmission by master - Simultaneous receive by slave
	property p_addr_tx_rx;
		@(posedge clk)
		disable iff(rst)
		(master_state == SEND_ADDR) |-> (current_state == RCV_ADDR);
	endproperty
	a_addr_tx_rx: assert property(p_addr_tx_rx);
	
	// 7.It takes 8 clock cycles to send addr and rw bit.
	property p_cycles_addr;
		@(posedge clk)
		disable iff(rst)
		(master_state == START) |-> ##1 (master_state == SEND_ADDR)[*8] ##1 (master_state == WAIT_ACK_1);
	endproperty
	a_cycles_addr: assert property(p_cycles_addr);
	
	// 8. scl clock toggling while master is transferring or receiving information
	property p_scl_toggle;
		@(clk)
		disable iff(rst)
		(master_state != IDLE) && (master_state != START) && (master_state != STOP) && (master_state != COMPLETE) 
		|-> (scl == clk);
	endproperty
	a_scl_toggle: assert property(p_scl_toggle);
	
	// 9. Once start is detected, slave starts receving data
	property p_start_slave;
		@(posedge clk)
		disable iff(rst)
		(current_state == IDLE) && (master_state == START) |=> (current_state == RCV_ADDR);
	endproperty
	a_start_slave: assert property(p_start_slave);
	
	
	// 10. State Transition of slave during Write
	property p_slave_states_write;
		@(posedge clk)
		disable iff(rst)
		(current_state == IDLE_S) && (master_state == START && rw) |-> ##1 (current_state == RCV_ADDR)[*8] ##1 (current_state == ADDR_ACK)
		##1 (current_state == WRITE)[*8] ##1 (current_state == DATA_ACK) ##1 (current_state == STOP_S) ##2 (current_state == IDLE_S);
	endproperty
	a_slave_states_write: assert property(p_slave_states_write);
	
	// 11. State Transition of master during Write
	property p_master_states_write;
		@(posedge clk)
		disable iff(rst)
		(master_state == START && rw) |=> (master_state == SEND_ADDR)[*8] ##1 (master_state == WAIT_ACK_1) ##1 (master_state == SEND_DATA)[*8] ##1 (master_state == WAIT_ACK_2) ##1 (master_state == COMPLETE) ##1 (master_state == STOP);
	endproperty
	a_master_states_write: assert property(p_master_states_write);
	
	
	// 12. Data validation during Write - Failed, Writing into memory is not proper.
	property p_data_transfer;
		logic [7:0] data_write;
		logic [6:0] addr_in;
		@(posedge clk)
		disable iff(rst)
		((master_state == START) && rw, data_write = data_in, addr_in = addr) |->
		##18 ((current_state == DATA_ACK) &&(data_reg == data_write));
	endproperty
	a_data_transfer: assert property(p_data_transfer);
		
	// 13. Bus Idle Detection
    property p_bus_idle;
        @(posedge clk)
		disable iff(rst)
        (master_state == IDLE) |-> (sda === 1 && scl === 1);
    endproperty
    a_bus_idle: assert property(p_bus_idle);
	
	// 14. State Transition of master during Read
	property p_master_states_read;
		@(posedge clk)
		disable iff(rst)
		(master_state == START && !rw) |=> (master_state == SEND_ADDR)[*8] ##1 (master_state == WAIT_ACK_1) ##1 (master_state == READ_DATA)[*8] ##1 (master_state == COMPLETE) ##1 (master_state == STOP);
	endproperty
	a_master_states_read: assert property(p_master_states_read);
	
	// 15. State Transition of slave during Read
	property p_slave_states_read;
		@(posedge clk)
		disable iff(rst)
		(current_state == IDLE_S) && (master_state == START && !rw) |-> ##1 (current_state == RCV_ADDR)[*8] ##1 (current_state == ADDR_ACK)
		##1 (current_state == READ)[*8] ##1 (current_state == STOP_S) ##2 (current_state == IDLE_S);
	endproperty
	a_slave_states_read: assert property(p_slave_states_read);
	
	// 16. Write states synchronization
	property p_write_sync;
		@(posedge clk)
		disable iff(rst)
		(master_state == SEND_DATA) |-> (current_state == WRITE);
	endproperty
	a_write_sync: assert property(p_write_sync);
	
	// 17. Read state synchronization
	property p_read_sync;
		@(posedge clk)
		disable iff(rst)
		(master_state == READ_DATA) |-> (current_state == READ);
	endproperty
	a_read_sync: assert property(p_read_sync);
	
	// 18. 
/*


    // 7. State Transitions
    property start_to_send_addr;
        @(posedge clk) disable iff(rst)
        (master_state == START) |=> (master_state = SEND_ADDR);
    endproperty
    property7: assert property(start_to_send_addr) else $error("State transitions failed.");

    // 8. Reset Behavior
    property reset_behavior;
        @(posedge clk) disable iff(rst)
        rst |-> (master_shift_reg == 0 && master_data_reg == 0 && master_bit_count == 0 &&
         ack_received == 0 && done == 0);
    endproperty
    property8: assert property(reset_behavior) else $error("Reset behavior failed.");

    

    // 10. Repeated Start Condition
    property repeated_start_condition;
        @(posedge clk) disable iff(rst)
        ($fell(sda) && scl === 1 && $past($fell(sda)) && !$rose(scl));
    endproperty
    property10: assert property(repeated_start_condition) else $error("Repeated start condition failed."); */
endmodule