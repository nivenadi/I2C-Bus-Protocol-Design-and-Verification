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
	
typedef enum logic [2:0] {
        IDLE_S,
        RCV_ADDR,
        ADDR_ACK,
        READ,
        WRITE,
        DATA_ACK,
		STOP_S
    } state_t;