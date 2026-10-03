package dmac_pkg;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 4;
    parameter Q_DEPTH_BITS = 2;

    typedef enum logic [1:0] { F_IDLE=2'd0, F_REQ=2'd1, F_WAIT=2'd2 } f_state_e;
    typedef enum logic [1:0] { D_IDLE=2'd0, D_ISSUE_RD=2'd1, D_ISSUE_WR=2'd2 } d_state_e;
    typedef enum logic [1:0] { U_IDLE=2'd0, U_REQ=2'd1, U_WAIT=2'd2 } u_state_e;

    typedef struct packed {
        logic [31:0] status;         
        logic [31:0] ctrl_len;      
        logic [31:0] dst_addr;       
        logic [31:0] src_addr;       
        logic [31:0] next_desc_ptr;  
    } dma_desc_t;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;
        logic [7:0]            len;
        logic [2:0]            size;
        logic                  rnw;
        logic [Q_DEPTH_BITS:0] id;
    } dma_cmd_t;

    typedef struct packed {
        logic                  is_status;
        logic [1:0]            stat_id;
        logic [7:0]            len;
    } tx_cmd_info_t;

    typedef struct packed {
        logic                  is_fetch;
        logic [7:0]            len;
    } rx_cmd_info_t;

endpackage
