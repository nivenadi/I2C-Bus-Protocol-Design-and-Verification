/* // -------------------- ECE 560: ASSERTION BASED VEIFICATION ------------------------
// -------------------- PROJECT: VERIFICATION OF I2C PROTOCOL -----------------------
// Term: Fall 2024
// Authors: Nivedita

module i2c_master_slave (
    input logic clk, rst,              // System clock and reset
    input logic [7:0] data_in,         // Data to be sent by master
    input logic rw,                    // Read/Write control: 1 for write, 0 for read
    input logic [6:0] addr,            // 7-bit I2C address
    output logic [7:0] data_out,       // Output data from slave
    output logic done                  // Completion signal
);

    // I²C Bus Lines
    logic scl, scl_en, sda_in;
    logic [7:0] data_wr;
	wire logic sda;
	logic master_drive;

    // Master State Machine
    typedef enum logic [3:0] {
        IDLE,
        START,
        SEND_ADDR,
        SEND_DATA,
        READ_DATA,
        WAIT_ACK_1,
        WAIT_ACK_2,
        STOP,
        COMPLETE
    } master_state_t;

    master_state_t master_state, next_master_state;

    // State machine for I2C slave
    typedef enum logic [2:0] {
        IDLE_S,
        RCV_ADDR,
        ADDR_ACK,
        READ,
        WRITE,
        DATA_ACK
    } state_t;

    state_t current_state, next_state;

    // Slave Memory
    logic [7:0] memory [127:0];       // 128 x 8-bit memory
    logic [6:0] slave_addr;

    // Internal Signals
    logic [3:0] bit_count;             // To count transmitted/received bits of master
    logic [7:0] master_write_reg;      // For serializing/deserializing data
    logic [7:0] master_read_reg;       // For serializing/deserializing data
     
    // Internal signals
    logic sda_out;           // Drive value for SDA
    logic [7:0] data_reg;   // Data shift register
    logic [7:0] addr_reg;    // Address register
    logic [3:0] slave_count; // Bit counter (0 to 7)
	logic slave_drive; //Indicates if slave is driving sda
	logic [7:0] mem[128];

    // Assignments for SCL
    assign scl = (scl_en) ? clk : 1'b1; // SCL toggles only during active transmission
    assign sda = master_drive ? sda_out : (slave_drive ? sda_in : 1'b1);

    // Sequential logic: state transitions
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            master_state <= IDLE;
        end else begin
            master_state <= next_master_state;
        end
    end
	
	always_ff @(posedge clk) begin
	if(rst) bit_count <= 1'b0;
	else if (master_state == SEND_ADDR || master_state == SEND_DATA || master_state == READ_DATA) bit_count <= bit_count + 1;
	else bit_count <= 1'b0;
	end
	
	always_ff @(posedge clk) begin
	if(rst) slave_count <= 1'b0;
	else if (current_state == RCV_ADDR || current_state == WRITE || current_state == READ) slave_count <= slave_count + 1;
	else slave_count <= 1'b0;
	end

    // Combinational logic: next state determination and output control
    always_comb begin
        // Default assignments
        next_master_state = master_state;
        scl_en = 1'b0;
        sda_out = 1'b1; // Default to high (idle)
        done = 1'b0;

        case (master_state)
            IDLE: begin
                master_drive = 1'b0;
                scl_en = 1'b0;
                if (!rst) begin
                    next_master_state = START; // Begin read/write operation
                end
            end

            START: begin
                master_drive = 1'b1;
                sda_out = 1'b0; // Start condition: SDA pulled low
                scl_en = 1'b0;  // Ensure SCL stays high
                next_master_state = SEND_ADDR;
                master_write_reg = {addr, rw}; // Prepare address + RW bit
                data_wr = data_in; // Prepare data to write
            end

            SEND_ADDR: begin
                scl_en = 1'b1;
                master_drive = 1'b1;
				if (bit_count == 7) begin // Reset bit count
						next_master_state = WAIT_ACK_1;
                end else
				 begin
					sda_out = master_write_reg[7 - bit_count];       // Send MSB first
                end
            end

            SEND_DATA: begin
                scl_en = 1'b1;
                master_drive = 1'b1;
                if (bit_count < 7) begin
                    sda_out = data_wr[7 - bit_count];
                end else begin
                    next_master_state = WAIT_ACK_2;
                end
            end

            READ_DATA: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (bit_count < 4'd8) begin
                    master_read_reg[7-bit_count] = sda; // Shift in
                end else begin
                    next_master_state = STOP;
                end
            end

            WAIT_ACK_1: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (!sda) begin // Acknowledge received
                    next_master_state = (rw) ? SEND_DATA : READ_DATA;
                end else begin
                    next_master_state = IDLE;
                end
            end

            WAIT_ACK_2: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (!sda) begin // Acknowledge received
                    next_master_state = STOP;
                end else begin
                    next_master_state = STOP;
                end
            end

            STOP: begin
                scl_en = 1'b0;
                sda_out = 1'b1; // Stop condition: SDA released high
                master_drive = 1'b1;
                next_master_state = COMPLETE;
            end

            COMPLETE: begin
                done = 1'b1;
                master_drive = 1'b0;
                next_master_state = IDLE;
            end

            default: begin
                next_master_state = IDLE;
            end
        endcase
    end

    // Slave FSM Sequential Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE_S;
        end else begin
            current_state <= next_state;
        end
    end
	


    // Slave FSM Combinational Logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE_S: begin
                slave_drive = 1'b0;
				slave_addr = 'x;
                if (scl && !sda) begin // Detect START condition
                    addr_reg = 0;
                    next_state = RCV_ADDR;
                end
            end

            RCV_ADDR: begin
                slave_drive = 1'b0; // Release SDA for input
                addr_reg[7-slave_count] = sda; // Shift in data bits
                if (slave_count == 7) begin
                    next_state = ADDR_ACK;
					slave_addr = addr_reg[7:1];
                end
            end

            ADDR_ACK: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = 1'b0; // Send ACK
                next_state = addr_reg[0] ? WRITE : READ;
            end

            WRITE: begin
                slave_drive = 1'b0; // Release SDA for input
                data_reg[7-slave_count] = sda; // Shift in data bits
                if (slave_count == 7) begin
                    mem[slave_addr] = data_reg;
                    next_state = DATA_ACK;
                end
                
            end

            READ: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = mem[slave_addr][7-slave_count]; // Shift data out
                if (slave_count == 7) begin
                    next_state = IDLE_S;
                end
            end

            DATA_ACK: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = 1'b1; // Send ACK
                next_state = IDLE_S; // Go back to IDLE after ACK
            end
        endcase
    end

    assign data_out = done ? master_read_reg : 1'bx;

endmodule
 */
// -------------------- ECE 560: ASSERTION BASED VEIFICATION ------------------------
// -------------------- PROJECT: VERIFICATION OF I2C PROTOCOL -----------------------
// Term: Fall 2024
// Authors: Nivedita, Divyasri, Nithisha, KrishnaPriya

module i2c_master_slave (
    input logic clk, rst,              // System clock and reset
    input logic [7:0] data_in,         // Data to be sent by master
    input logic rw,                    // Read/Write control: 1 for write, 0 for read
    input logic [6:0] addr,            // 7-bit I2C address
    output logic [7:0] data_out,       // Output data from slave
    output logic done                  // Completion signal
);

    // I²C Bus Lines
    logic scl, scl_en, sda_in;
    logic [7:0] data_wr;
	wire logic sda;
	logic master_drive;

    // Master State Machine
	typedef enum logic [3:0] {
        IDLE,
        START,
        SEND_ADDR,
        SEND_DATA,
        READ_DATA,
        WAIT_ACK_1,
        WAIT_ACK_2,
        STOP,
        COMPLETE
    } master_state_t;
	
    master_state_t master_state, next_master_state;

    // State machine for I2C slave
	typedef enum logic [2:0] {
        IDLE_S,
        RCV_ADDR,
        ADDR_ACK,
        READ,
        WRITE,
        DATA_ACK,
		STOP_S
    } state_t;
	
    state_t current_state, next_state;

    // Slave Memory  
    logic [6:0] slave_addr;
	logic [7:0] mem[128];

    // Internal Signals
    logic [3:0] bit_count;             // To count transmitted/received bits of master
    logic [7:0] master_write_reg;      // For serializing/deserializing data
    logic [7:0] master_read_reg;       // For serializing/deserializing data
     
    // Internal signals
    logic sda_out;           // Drive value for SDA
    logic [7:0] data_reg;   // Data shift register
    logic [7:0] addr_reg;    // Address register
    logic [3:0] slave_count; // Bit counter (0 to 7)
	logic slave_drive; //Indicates if slave is driving sda


    // Assignments for SCL
    assign scl = (scl_en) ? clk : 1'b1; // SCL toggles only during active transmission
    assign sda = master_drive ? sda_out : (slave_drive ? sda_in : 1'b1);

    // Sequential logic: state transitions
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            master_state <= IDLE;
        end else begin
            master_state <= next_master_state;
        end
    end
	
	always_ff @(posedge clk) begin
	if(rst) bit_count <= 1'b0;
	else if (master_state == SEND_ADDR || master_state == SEND_DATA || master_state == READ_DATA) bit_count <= bit_count + 1;
	else bit_count <= 1'b0;
	end
	
	always_ff @(posedge clk) begin
	if(rst) slave_count <= 1'b0;
	else if (current_state == RCV_ADDR || current_state == WRITE || current_state == READ) slave_count <= slave_count + 1;
	else slave_count <= 1'b0;
	end

    // Combinational logic: next state determination and output control
    always_comb begin
        // Default assignments
        next_master_state = master_state;
        scl_en = 1'b0;
        sda_out = 1'b1; // Default to high (idle)
        done = 1'b0;

        case (master_state)
            IDLE: begin
                master_drive = 1'b0;
                scl_en = 1'b0;
                if (!rst) begin
                    next_master_state = START; // Begin read/write operation
                end
            end

            START: begin
                master_drive = 1'b1;
                sda_out = 1'b0; // Start condition: SDA pulled low
                scl_en = 1'b0;  // Ensure SCL stays high
                next_master_state = SEND_ADDR;
                master_write_reg = {addr, rw}; // Prepare address + RW bit
                data_wr = data_in; // Prepare data to write
            end

            SEND_ADDR: begin
                scl_en = 1'b1;
                master_drive = 1'b1;
				sda_out = master_write_reg[7 - bit_count]; 
				if (bit_count == 7) begin // Reset bit count
						next_master_state = WAIT_ACK_1;
                end
			end
            SEND_DATA: begin
                scl_en = 1'b1;
                master_drive = 1'b1;
				sda_out = data_wr[7 - bit_count];
                if (bit_count == 7) begin
                    next_master_state = WAIT_ACK_2;
                end
            end

            READ_DATA: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (bit_count < 7) begin
                    master_read_reg[7-bit_count] = sda; // Shift in
                end else begin
                    next_master_state = COMPLETE;
                end
            end

            WAIT_ACK_1: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (!sda) begin // Acknowledge received
                    next_master_state = (master_write_reg[0]) ? SEND_DATA : READ_DATA;
                end else begin
                    next_master_state = IDLE;
                end
            end

            WAIT_ACK_2: begin
                scl_en = 1'b1;
                master_drive = 1'b0;
                if (!sda) begin // Acknowledge received
                    next_master_state = COMPLETE;
                end else begin
                    next_master_state = COMPLETE;
                end
            end

            COMPLETE: begin
                scl_en = 1'b0; // Stop condition: SDA released high
                master_drive = 1'b1;
				sda_out = 1'b0;
                next_master_state = STOP;
            end

            STOP: begin
				scl_en = 1'b0;
                done = 1'b1;
				master_drive = 1'b1;
				sda_out = 1'b1;
				
                next_master_state = IDLE;
            end

            default: begin
                next_master_state = IDLE;
            end
        endcase
    end

    // Slave FSM Sequential Logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            current_state <= IDLE_S;
        end else begin
            current_state <= next_state;
        end
    end
	


    // Slave FSM Combinational Logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE_S: begin
                slave_drive = 1'b0;
		slave_addr = '0;
                if (scl && !sda) begin // Detect START condition
                    addr_reg = 0;
                    next_state = RCV_ADDR;
                end
            end

            RCV_ADDR: begin
                slave_drive = 1'b0; // Release SDA for input
                addr_reg[7-slave_count] = sda; // Shift in data bits
                if (slave_count == 7) begin
                    next_state = ADDR_ACK;
					slave_addr = addr_reg[7:1];
                end
            end

            ADDR_ACK: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = 1'b0; // Send ACK
                next_state = addr_reg[0] ? WRITE : READ;
            end

            WRITE: begin
                slave_drive = 1'b0; // Release SDA for input
                data_reg[7-slave_count] = sda; // Shift in data bits
                if (slave_count == 7) begin
					next_state = DATA_ACK;
					mem[slave_addr] = data_reg;
                end         
            end

            READ: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = mem[slave_addr][7-slave_count]; // Shift data out
                if (slave_count == 7) begin
                    next_state = STOP_S;
                end
            end

            DATA_ACK: begin
                slave_drive = 1'b1; // Drive SDA
                sda_in = 1'b0; // Send ACK
                next_state = STOP_S; // Go back to IDLE after ACK
            end
			
			STOP_S: begin
					slave_drive = 1'b0;
					if(scl && sda) next_state = IDLE_S;
			end
        endcase
    end

    assign data_out = done ? master_read_reg : 1'b0;

endmodule


