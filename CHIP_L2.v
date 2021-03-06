// Top module of your design, you cannot modify this module!!
module CHIP (	clk,
				rst_n,
	//----------for slow_memD------------
				mem_read_D,
				mem_write_D,
				mem_addr_D,
				mem_wdata_D,
				mem_rdata_D,
				mem_ready_D,
	//----------for slow_memI------------
				mem_read_I,
				mem_write_I,
				mem_addr_I,
				mem_wdata_I,
				mem_rdata_I,
				mem_ready_I,
	//----------for TestBed--------------				
				DCACHE_addr, 
				DCACHE_wdata,
				DCACHE_wen   
			);
	input			clk, rst_n;
	//--------------------------

	output			mem_read_D;
	output			mem_write_D;
	output	[31:4]	mem_addr_D;
	output	[127:0]	mem_wdata_D;
	input	[127:0]	mem_rdata_D;
	input			mem_ready_D;
	//--------------------------
	output			mem_read_I;
	output			mem_write_I;
	output	[31:4]	mem_addr_I;
	output	[127:0]	mem_wdata_I;
	input	[127:0]	mem_rdata_I;
	input			mem_ready_I;
	//----------for TestBed--------------
	output	[29:0]	DCACHE_addr;
	output	[31:0]	DCACHE_wdata;
	output			DCACHE_wen;
	//--------------------------

	// wire declaration  
	// Processor 和 Cache之間
	wire        ICACHE_ren;
	wire        ICACHE_wen;
	wire [29:0] ICACHE_addr;
	wire [31:0] ICACHE_wdata;
	wire        ICACHE_stall;
	wire [31:0] ICACHE_rdata;

	wire        DCACHE_ren;
	wire        DCACHE_wen;
	wire [29:0] DCACHE_addr;
	wire [31:0] DCACHE_wdata;
	wire        DCACHE_stall;
	wire [31:0] DCACHE_rdata;

	//=========================================
		// Note that the overall design of your RISCV includes:
		// 1. pipelined RISCV processor
		// 2. data cache
		// 3. instruction cache


	RISCV_Pipeline i_RISCV(
		// control interface
		.clk            (clk)           , 
		.rst_n          (rst_n)         ,
	//----------I cache interface-------		
		.ICACHE_ren     (ICACHE_ren)    ,
		.ICACHE_wen     (ICACHE_wen)    ,
		.ICACHE_addr    (ICACHE_addr)   ,
		.ICACHE_wdata   (ICACHE_wdata)  ,
		.ICACHE_stall   (ICACHE_stall)  ,
		.ICACHE_rdata   (ICACHE_rdata)  ,
	//----------D cache interface-------
		.DCACHE_ren     (DCACHE_ren)    ,
		.DCACHE_wen     (DCACHE_wen)    ,
		.DCACHE_addr    (DCACHE_addr)   ,
		.DCACHE_wdata   (DCACHE_wdata)  ,
		.DCACHE_stall   (DCACHE_stall)  ,
		.DCACHE_rdata   (DCACHE_rdata)	
	);

	cache D_cache(
		.clk        (clk)         ,
		.proc_reset (~rst_n)      ,
		.proc_read  (DCACHE_ren)  ,
		.proc_write (DCACHE_wen)  ,
		.proc_addr  (DCACHE_addr) ,
		.proc_rdata (DCACHE_rdata),
		.proc_wdata (DCACHE_wdata),
		.proc_stall (DCACHE_stall),
		.mem_read   (mem_read_D)  ,
		.mem_write  (mem_write_D) ,
		.mem_addr   (mem_addr_D)  ,
		.mem_wdata  (mem_wdata_D) ,
		.mem_rdata  (mem_rdata_D) ,
		.mem_ready  (mem_ready_D) 
	);

	cache I_cache(
		.clk        (clk)         ,
		.proc_reset (~rst_n)      ,
		.proc_read  (ICACHE_ren)  ,
		.proc_write (ICACHE_wen)  ,
		.proc_addr  (ICACHE_addr) ,
		.proc_rdata (ICACHE_rdata),
		.proc_wdata (ICACHE_wdata),
		.proc_stall (ICACHE_stall),
		.mem_read   (mem_read_I)  ,
		.mem_write  (mem_write_I) ,
		.mem_addr   (mem_addr_I)  ,
		.mem_wdata  (mem_wdata_I) ,
		.mem_rdata  (mem_rdata_I) ,
		.mem_ready  (mem_ready_I)
	);
endmodule

//==== 2-way Cache ========================================
module L1_cache(
    clk, proc_reset,
    proc_read, proc_write, proc_addr, proc_rdata, proc_wdata, proc_stall,
    mem_read, mem_write, mem_addr, mem_rdata, mem_wdata, mem_ready );
    //---- input/output definition ----------------------
    input          clk;
    // processor interface
    input          proc_reset;
    input          proc_read, proc_write;
    input   [29:0] proc_addr;
    input   [31:0] proc_wdata;
    output         proc_stall;
    output  [31:0] proc_rdata;
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output reg [27:0] mem_addr;
    output reg [127:0] mem_wdata;

	L2_cache inst_L2_cache(
		.clk(clk), .proc_reset(proc_reset),
		.proc_read(mem_read), .proc_write(mem_write), .proc_addr, .proc_rdata, .proc_wdata, .proc_stall,
	);
    
    //---- wire/reg definition ----------------------------
    parameter NUM_BLOCKS = 4;
	parameter BLOCK_ADDR_SIZE = 62;  // log2 NUM_BLOCKS
	parameter TAG_SIZE = 28-BLOCK_ADDR_SIZE;  // 30 - 2 - BLOCK_ADDR_SIZE
    parameter BLOCK_hSIZE = 130+TAG_SIZE;  // 1+1+TAG_SIZE+128
	// cache = [word0, word1, word2, word3] 
	// block = [cache1, cache2]


    parameter IDLE = 2'd0;
    parameter COMP = 2'd1;
    parameter WRITE = 2'd2;
    parameter ALLOC = 2'd3;
    integer i;

    wire valid1, dirty1, hit1;
    wire valid2, dirty2, hit2;
    wire hit;
    wire [BLOCK_ADDR_SIZE-1:0] block_addr;
    wire [TAG_SIZE-1:0] tag;

// input          proc_read, proc_write;
// input   [29:0] proc_addr;
// input   [31:0] proc_wdata;
// output         proc_stall;
// output  [31:0] proc_rdata;
// // memory interface
// input  [127:0] mem_rdata;
// input          mem_ready;
// output         mem_read, mem_write;
// output reg [27:0] mem_addr;
// output reg [127:0] mem_wdata;

	//---- L2 I/O ---------------------
	wire L2_proc_read, L2_proc_write;
	

    // flip flops
    reg [1:0] state, state_next;
    reg [BLOCK_hSIZE-1:0] cache1 [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache1_next [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache2 [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache2_next [0:NUM_BLOCKS-1];
    reg [NUM_BLOCKS-1:0] lru, lru_next;  // low --> use 1 first

    //==== Combinational Circuit ==========================
    assign block_addr = proc_addr[1+BLOCK_ADDR_SIZE : 2];
    assign tag = proc_addr[29 : 30-TAG_SIZE];
    assign valid1 = cache1[block_addr][BLOCK_hSIZE-1];
    assign dirty1 = cache1[block_addr][BLOCK_hSIZE-2];
    assign valid2 = cache2[block_addr][BLOCK_hSIZE-1];
    assign dirty2 = cache2[block_addr][BLOCK_hSIZE-2];
    assign hit1 = valid1 & (cache1[block_addr][127+TAG_SIZE : 128] == tag);
    assign hit2 = valid2 & (cache2[block_addr][127+TAG_SIZE : 128] == tag);
    assign hit = hit1 | hit2;
    
    assign proc_stall = (state==COMP & (hit | (~proc_read & ~proc_write))) ? 0 : 1;
    assign proc_rdata = (hit1 & proc_read)?
                            proc_addr[1]?
                                proc_addr[0]?
                                    cache1[block_addr][127:96]
                                :   cache1[block_addr][95:64]
                            :   proc_addr[0]?
                                    cache1[block_addr][63:32]
                                :   cache1[block_addr][31:0]
                        : (hit2 & proc_read)?
                            proc_addr[1]?
                                proc_addr[0]?
                                    cache2[block_addr][127:96]
                                :   cache2[block_addr][95:64]
                            :   proc_addr[0]?
                                    cache2[block_addr][63:32]
                                :   cache2[block_addr][31:0]
                        : 32'd0;
    assign mem_read = ~mem_ready && state==ALLOC;
    assign mem_write = ~mem_ready && state==WRITE;

    //---- Finite State Machine ---------------------------
    always @(*) begin
        case(state)
            IDLE: begin
                state_next = COMP;
            end
            COMP: begin
                state_next = (hit | (~proc_read & ~proc_write))? COMP : (dirty1 | dirty2)? WRITE : ALLOC;
            end
            WRITE: begin
                state_next = mem_ready? ALLOC : WRITE;
            end
            ALLOC: begin
                state_next = mem_ready? COMP : ALLOC;                
            end
            default: state_next = state;
        endcase
    end

	//---- Control signals and I/O ------------------------
    always @(*) begin
        //---- I/O signals --------------------------------
        mem_addr = (state==WRITE)?
                        dirty1?
                            {cache1[block_addr][127+TAG_SIZE : 128], block_addr}
                        :   {cache2[block_addr][127+TAG_SIZE : 128], block_addr}
                    : proc_addr[29:2];
        mem_wdata = dirty1? cache1[block_addr][127:0] : cache2[block_addr][127:0];
    
        //---- handle cache_next and lru bits -------------
        for (i=0; i<NUM_BLOCKS; i=i+1) begin
            cache1_next[i] = cache1[i];
            cache2_next[i] = cache2[i];
            lru_next[i] = lru[i];
        end
        lru_next[block_addr] = state==COMP?
                                    hit1? 0 : hit2? 1 : lru[block_addr]
                                : lru[block_addr];

        case(state)
            COMP: begin
                if (hit1 & proc_write) begin
                    cache1_next[block_addr][(proc_addr[1:0])*32+31 -: 32] = proc_wdata;
                    cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b11;
                end else if (hit2 & proc_write) begin
                    cache2_next[block_addr][(proc_addr[1:0])*32+31 -: 32] = proc_wdata;
                    cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b11;
                end else begin  // TODO: remove else?
                    cache1_next[block_addr] = cache1[block_addr];
                    cache2_next[block_addr] = cache2[block_addr];
                end
            end
            WRITE: begin
                if (mem_ready) begin
                    if (dirty1) begin
                        cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end else begin
                        cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end
                end
            end
            ALLOC: begin
                if (!dirty1 & !dirty2) begin
                    if (lru[block_addr]) begin
                        cache2_next[block_addr][127:0] = mem_rdata;
                        cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                        cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end else begin
                        cache1_next[block_addr][127:0] = mem_rdata;
                        cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                        cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end
                end else if (!dirty1) begin
                    cache1_next[block_addr][127:0] = mem_rdata;
                    cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                end else begin
                    cache2_next[block_addr][127:0] = mem_rdata;
                    cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;   
                end
            end
        endcase
    end

    //==== Sequential Circuit =============================
    always@( posedge clk ) begin
        if( proc_reset ) begin
            for (i=0; i<NUM_BLOCKS; i=i+1) begin
                cache1[i] <= 0;
                cache2[i] <= 0;
                lru[i] <= 0;
            end
            state <= IDLE;
        end else begin
            for (i=0; i<NUM_BLOCKS; i=i+1) begin
                cache1[i] <= cache1_next[i];
                cache2[i] <= cache2_next[i];
                lru[i] <= lru_next[i];
            end
            state <= state_next;
        end
    end

endmodule

//==== L2 Cache ===========================================
module L2_cache(
    clk, proc_reset,
    proc_read, proc_write, proc_addr, proc_rdata, proc_wdata, proc_stall,
    mem_read, mem_write, mem_addr, mem_rdata, mem_wdata, mem_ready );
    //---- input/output definition ----------------------
    input          clk;
    // processor interface
    input          proc_reset;
    input          proc_read, proc_write;
    input   [29:0] proc_addr;
    input   [31:0] proc_wdata;
    output         proc_stall;
    output  [31:0] proc_rdata;
    // memory interface
    input  [127:0] mem_rdata;
    input          mem_ready;
    output         mem_read, mem_write;
    output reg [27:0] mem_addr;
    output reg [127:0] mem_wdata;
    
    //---- wire/reg definition ----------------------------
    parameter NUM_BLOCKS = 64;
	parameter BLOCK_ADDR_SIZE = 6;  // log2 NUM_BLOCKS
	parameter TAG_SIZE = 28-BLOCK_ADDR_SIZE;  // 30 - 2 - BLOCK_ADDR_SIZE
    parameter BLOCK_hSIZE = 130+TAG_SIZE;  // 1+1+TAG_SIZE+128
	// cache = [word0, word1, word2, word3] 
	// block = [cache1, cache2]


    parameter IDLE = 2'd0;
    parameter COMP = 2'd1;
    parameter WRITE = 2'd2;
    parameter ALLOC = 2'd3;
    integer i;

    wire valid1, dirty1, hit1;
    wire valid2, dirty2, hit2;
    wire hit;
    wire [BLOCK_ADDR_SIZE-1:0] block_addr;
    wire [TAG_SIZE-1:0] tag;

    // flip flops
    reg [1:0] state, state_next;
    reg [BLOCK_hSIZE-1:0] cache1 [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache1_next [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache2 [0:NUM_BLOCKS-1];
    reg [BLOCK_hSIZE-1:0] cache2_next [0:NUM_BLOCKS-1];
    reg [NUM_BLOCKS-1:0] lru, lru_next;  // low --> use 1 first

    //==== Combinational Circuit ==========================
    assign block_addr = proc_addr[1+BLOCK_ADDR_SIZE : 2];
    assign tag = proc_addr[29 : 30-TAG_SIZE];
    assign valid1 = cache1[block_addr][BLOCK_hSIZE-1];
    assign dirty1 = cache1[block_addr][BLOCK_hSIZE-2];
    assign valid2 = cache2[block_addr][BLOCK_hSIZE-1];
    assign dirty2 = cache2[block_addr][BLOCK_hSIZE-2];
    assign hit1 = valid1 & (cache1[block_addr][127+TAG_SIZE : 128] == tag);
    assign hit2 = valid2 & (cache2[block_addr][127+TAG_SIZE : 128] == tag);
    assign hit = hit1 | hit2;
    
    assign proc_stall = (state==COMP & (hit | (~proc_read & ~proc_write))) ? 0 : 1;
    assign proc_rdata = (hit1 & proc_read)?
                            proc_addr[1]?
                                proc_addr[0]?
                                    cache1[block_addr][127:96]
                                :   cache1[block_addr][95:64]
                            :   proc_addr[0]?
                                    cache1[block_addr][63:32]
                                :   cache1[block_addr][31:0]
                        : (hit2 & proc_read)?
                            proc_addr[1]?
                                proc_addr[0]?
                                    cache2[block_addr][127:96]
                                :   cache2[block_addr][95:64]
                            :   proc_addr[0]?
                                    cache2[block_addr][63:32]
                                :   cache2[block_addr][31:0]
                        : 32'd0;
    assign mem_read = ~mem_ready && state==ALLOC;
    assign mem_write = ~mem_ready && state==WRITE;

    //---- Finite State Machine ---------------------------
    always @(*) begin
        case(state)
            IDLE: begin
                state_next = COMP;
            end
            COMP: begin
                state_next = (hit | (~proc_read & ~proc_write))? COMP : (dirty1 | dirty2)? WRITE : ALLOC;
            end
            WRITE: begin
                state_next = mem_ready? ALLOC : WRITE;
            end
            ALLOC: begin
                state_next = mem_ready? COMP : ALLOC;                
            end
            default: state_next = state;
        endcase
    end

	//---- Control signals and I/O ------------------------
    always @(*) begin
        //---- I/O signals --------------------------------
        mem_addr = (state==WRITE)?
                        dirty1?
                            {cache1[block_addr][127+TAG_SIZE : 128], block_addr}
                        :   {cache2[block_addr][127+TAG_SIZE : 128], block_addr}
                    : proc_addr[29:2];
        mem_wdata = dirty1? cache1[block_addr][127:0] : cache2[block_addr][127:0];
    
        //---- handle cache_next and lru bits -------------
        for (i=0; i<NUM_BLOCKS; i=i+1) begin
            cache1_next[i] = cache1[i];
            cache2_next[i] = cache2[i];
            lru_next[i] = lru[i];
        end
        lru_next[block_addr] = state==COMP?
                                    hit1? 0 : hit2? 1 : lru[block_addr]
                                : lru[block_addr];

        case(state)
            COMP: begin
                if (hit1 & proc_write) begin
                    cache1_next[block_addr][(proc_addr[1:0])*32+31 -: 32] = proc_wdata;
                    cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b11;
                end else if (hit2 & proc_write) begin
                    cache2_next[block_addr][(proc_addr[1:0])*32+31 -: 32] = proc_wdata;
                    cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b11;
                end else begin  // TODO: remove else?
                    cache1_next[block_addr] = cache1[block_addr];
                    cache2_next[block_addr] = cache2[block_addr];
                end
            end
            WRITE: begin
                if (mem_ready) begin
                    if (dirty1) begin
                        cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end else begin
                        cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end
                end
            end
            ALLOC: begin
                if (!dirty1 & !dirty2) begin
                    if (lru[block_addr]) begin
                        cache2_next[block_addr][127:0] = mem_rdata;
                        cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                        cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end else begin
                        cache1_next[block_addr][127:0] = mem_rdata;
                        cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                        cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                    end
                end else if (!dirty1) begin
                    cache1_next[block_addr][127:0] = mem_rdata;
                    cache1_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache1_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;
                end else begin
                    cache2_next[block_addr][127:0] = mem_rdata;
                    cache2_next[block_addr][127+TAG_SIZE : 128] = tag;
                    cache2_next[block_addr][BLOCK_hSIZE-1 : BLOCK_hSIZE-2] = 2'b10;   
                end
            end
        endcase
    end

    //==== Sequential Circuit =============================
    always@( posedge clk ) begin
        if( proc_reset ) begin
            for (i=0; i<NUM_BLOCKS; i=i+1) begin
                cache1[i] <= 0;
                cache2[i] <= 0;
                lru[i] <= 0;
            end
            state <= IDLE;
        end else begin
            for (i=0; i<NUM_BLOCKS; i=i+1) begin
                cache1[i] <= cache1_next[i];
                cache2[i] <= cache2_next[i];
                lru[i] <= lru_next[i];
            end
            state <= state_next;
        end
    end

endmodule

//Disscussion
//1. mem stage 用太多東西，critical path會變大，移到wb stage？(write reg會變comb)
//2. cache 優化，icache, dcache分開寫
//3. branch prediction, jalr predction?
//4. mem read 提前準備好
//5. cache write buffer
//6. ICACHE 可把write部分刪掉
//7. 用gate or 相等表示  test == 2'b01 , !test[1] & test[0]

module RISCV_Pipeline(
	clk, rst_n, ICACHE_ren, ICACHE_wen, ICACHE_addr, ICACHE_wdata, ICACHE_stall, ICACHE_rdata,
				DCACHE_ren, DCACHE_wen, DCACHE_addr, DCACHE_wdata, DCACHE_stall, DCACHE_rdata
);
//==== input/output definition ============================
	input clk, rst_n;
	input ICACHE_stall, DCACHE_stall;
	input [31:0] ICACHE_rdata, DCACHE_rdata;
	output reg ICACHE_ren, ICACHE_wen, DCACHE_ren, DCACHE_wen;
	output reg [29:0] ICACHE_addr, DCACHE_addr;
	output reg [31:0] ICACHE_wdata, DCACHE_wdata;

//==== input/output definition ============================
	parameter R_TYPE = 3'd0;
	parameter I_TYPE = 3'd1;
	parameter S_TYPE = 3'd2;
	parameter B_TYPE = 3'd3;
	parameter UJ_TYPE = 3'd4;

	//========= PC =========
    reg [31:0] PC;
	reg [31:0] PC_nxt;
	reg [31:0] PC_ID, PC_EX;
	reg [31:0] PC_B_ID, PC_jalr_ID;

	//========= Registers =========
    reg [31:0] register [0:31];

    wire [4:0] rs1_ID;  //rs1
    reg [4:0] rs1_EX;
	wire [31:0] rs1_data_ID;
	reg [31:0] rs1_data_EX;

    wire [4:0] rs2_ID;  //rs2
    reg [4:0] rs2_EX;
	wire [31:0] rs2_data_ID;
	reg [31:0] rs2_data_EX;

    wire [4:0] rd_ID;  //rd
    reg [4:0] rd_EX;
    reg [4:0] rd_MEM;
    reg [4:0] rd_WB;

	reg signed [31:0] rd_wdata_EX;
	reg signed [31:0] rd_wdata_MEM_real;
	reg signed [31:0] rd_wdata_MEM;  // rd_w_ --> rd_wdata_
	reg signed [31:0] rd_wdata_WB;

	reg [31:0] compare_rs1;
	reg [31:0] compare_rs2;

	//========= Instruction =========
    wire [31:0] inst_IF;
	reg [31:0] inst_ID;
    wire [6:0] op;
    wire [2:0] func3;
    wire [6:0] func7;

	//========= Immediate =========
    reg [31:0] imme_ID;
    reg [31:0] imme_EX;

	//========= alu ========= 
    reg signed [31:0] alu_in1;
    reg signed [31:0] alu_in2;
    reg signed [31:0] alu_in2_temp;
    reg signed [31:0] alu_out_EX;
    reg signed [31:0] alu_out_MEM;
    reg signed [31:0] alu_out_WB;
    reg [3:0]	alu_ctrl_ID;
    reg [3:0]	alu_ctrl_EX;

	//========= memory ========= 
	reg [31:0] read_data_MEM;  //read from mem

	reg [31:0] wdata_EX;  //write mem
	reg [31:0] wdata_MEM;

	//========= Control unit =========
    reg ctrl_jalr_ID,		ctrl_jalr_EX; 	//在EX要計算是否要PC+4
    reg ctrl_jal_ID,		ctrl_jal_EX; 	//
    reg ctrl_beq_ID;	//beq 在ID做完就沒事了
    reg ctrl_bne_ID;	//beq 在ID做完就沒事了
    reg ctrl_memread_ID,	ctrl_memread_EX, 	ctrl_memread_MEM;
    reg ctrl_memtoreg_ID,	ctrl_memtoreg_EX, 	ctrl_memtoreg_MEM, 	ctrl_memtoreg_WB;
    reg ctrl_memwrite_ID, 	ctrl_memwrite_EX, 	ctrl_memwrite_MEM; 
    reg ctrl_regwrite_ID, 	ctrl_regwrite_EX, 	ctrl_regwrite_MEM, 	ctrl_regwrite_WB;
    reg ctrl_ALUSrc_ID, 	ctrl_ALUSrc_EX;

	reg [1:0] ctrl_FA, ctrl_FB;
	reg [1:0] ctrl_FA_j, ctrl_FB_j;

	reg ctrl_lw_stall;

	reg ctrl_bj_taken;

	//========= wire & reg ==============
    reg	[2:0]	type;
    reg [31:0]	write_rd_MEM;

	//========= Wire assignment ==========
    assign inst_IF = (ctrl_bj_taken | ctrl_jalr_ID)? 32'd0:{ICACHE_rdata[7:0],ICACHE_rdata[15:8],ICACHE_rdata[23:16],ICACHE_rdata[31:24]};

    assign op = inst_ID[6:0];
    assign rd_ID = inst_ID[11:7];  //rd;
    assign rs1_ID = inst_ID[19:15];  //rs1;
    assign rs2_ID = inst_ID[24:20];  //rs2;
    assign func3 = inst_ID[14:12]; 
    assign func7 = inst_ID[31:25];

	assign rs1_data_ID = register[rs1_ID];
	assign rs2_data_ID = register[rs2_ID];


	//========== type =================
    always @(*) begin
        case (op)
            7'b0110011: type = R_TYPE;  //R-type
			7'b0010011: type = I_TYPE;  //I-type
            7'b0000011: type = I_TYPE;  //I-type, lw
            7'b1100111: type = I_TYPE;  //I-type, jalr
            7'b0100011: type = S_TYPE;  //S, sw
            7'b1100011: type = B_TYPE;  //B, beq
            7'b1101111: type = UJ_TYPE;  //jal
            default: type=3'd7;
        endcase
    end

	//==== ID stage: ctrl unit ========
    always @(*) begin
		//default
        imme_ID = 0;
		ctrl_jal_ID = 0;
		ctrl_jalr_ID = 0;
        ctrl_beq_ID = 0;
        ctrl_bne_ID = 0;
        ctrl_memread_ID = 0;
        ctrl_memwrite_ID = 0;
        ctrl_memtoreg_ID = 0;
        ctrl_regwrite_ID = 0;
        ctrl_ALUSrc_ID = 0; 
        case (type)
        R_TYPE: begin
            ctrl_regwrite_ID = 1;
            ctrl_ALUSrc_ID = 0;
        end

        I_TYPE: begin
            ctrl_memread_ID = !op[4] & !op[2];  //lw,才要讀mem
            ctrl_memtoreg_ID = !op[4] & !op[2];  //lw,才要讀mem
            ctrl_regwrite_ID = 1;
            ctrl_ALUSrc_ID = 1;  //給imme
			ctrl_jalr_ID = op[2];  //jalr
			imme_ID = (func3==3'b001 | func3==3'b101)? 
						{ {27{1'b0}} , inst_ID[24:20]}:  //shamt, slli, srai, srli
            			{ {21{inst_ID[31]}}, inst_ID[30:20]};  //addi, andi, ori, xori, slli, srai, srli, slti, lw
        end

        S_TYPE: begin
            ctrl_memwrite_ID = 1;
            ctrl_ALUSrc_ID = 1;			
            imme_ID = { {21{inst_ID[31]}}, inst_ID[30:25], inst_ID[11:7]};  //sw
        end

        B_TYPE: begin
            ctrl_beq_ID = !func3[0];
            ctrl_bne_ID = func3[0];
            ctrl_ALUSrc_ID = 1;			
            imme_ID = { {20{inst_ID[31]}}, inst_ID[7], inst_ID[30:25], inst_ID[11:8], 1'b0 };  //beq, bne
        end

        UJ_TYPE: begin
			ctrl_jal_ID = 1;
            ctrl_regwrite_ID = 1;
            ctrl_ALUSrc_ID = 1;
            imme_ID = { {12{inst_ID[31]}}, inst_ID[19:12], inst_ID[20], inst_ID[30:25], inst_ID[24:21], 1'b0 };  //jal
        end
		default: begin
			imme_ID = 0;
			ctrl_jal_ID = 0;
			ctrl_jalr_ID = 0;
			ctrl_beq_ID = 0;
			ctrl_bne_ID = 0;
			ctrl_memread_ID = 0;
			ctrl_memwrite_ID = 0;
			ctrl_memtoreg_ID = 0;
			ctrl_regwrite_ID = 0;
			ctrl_ALUSrc_ID = 0; 
		end
        endcase
    end

	//==== ID stage: alu_ctrl =========
	always @(*) begin
		if (op==7'b0010011) begin  // I-type without lw, jalr
			if (func3==3'b101) alu_ctrl_ID = func7[5]? 4'd8:4'd7;  //srai, srli
			else if (func3==3'b001) alu_ctrl_ID = 4'd6;  //slli
			else if (func3==3'b010) alu_ctrl_ID = 4'd5;  //slti
			else if (func3==3'b100) alu_ctrl_ID = 4'd4;  ///xori
			else if (func3==3'b110) alu_ctrl_ID = 4'd3;  //ori
			else if (func3==3'b111) alu_ctrl_ID = 4'd2;  //andi
			else alu_ctrl_ID = 4'd0;  //addi
		end
		else if (op==7'b0110011) begin //R-type
			if (func3==3'b000) alu_ctrl_ID = func7[5]? 4'd1:4'd0;  //sub, add
			else if (func3==3'b111) alu_ctrl_ID = 4'd2;  //and
			else if (func3==3'b110) alu_ctrl_ID = 4'd3;  //or
			else if (func3==3'b100) alu_ctrl_ID = 4'd4;  //xor
			else alu_ctrl_ID = 4'd5;  //slt
		end
		else if (op==7'b1100011) begin //beq, bne
			alu_ctrl_ID = 4'd1;
		end
		else begin //jal, sw
			alu_ctrl_ID = 4'd0;
		end
	end

    //======== mux & comb ckt ========
    always @(*) begin
		// Dmem_read		(wen, addr, data)
		DCACHE_ren = ctrl_memread_MEM;
		DCACHE_addr = (ctrl_memread_MEM | ctrl_memwrite_MEM)? alu_out_MEM[31:2] : 0;  // 設條件否則會一直輸出addr
		read_data_MEM = {DCACHE_rdata[7:0], DCACHE_rdata[15:8], DCACHE_rdata[23:16], DCACHE_rdata[31:24]};  // Endian decode
		// tb中rd_wdata_MEM_real不會被用到，lw後的rd不會馬上被用到
		// TODO: suit tb
		rd_wdata_MEM_real = (ctrl_memread_MEM)? read_data_MEM : rd_wdata_MEM;  // rd在mem stage也可能被改(lw)

		// Dmem_write	(wen, addr, data)
		DCACHE_wen = ctrl_memwrite_MEM;
		// case(ctrl_FB) //genaral case，因為sw也有可能forwarded，但tb沒這問題
		// 	2'b00: wdata_EX = rs2_data_EX; 
		// 	2'b01: wdata_EX = rd_wdata_MEM_real; 
		// 	2'b10: wdata_EX = rd_wdata_WB; 
		// 	default:wdata_EX = rs2_data_EX; 
		// endcase
		wdata_EX = rs2_data_EX;  //這也會過
		DCACHE_wdata = {wdata_MEM[7:0],wdata_MEM[15:8],wdata_MEM[23:16],wdata_MEM[31:24]};

		//Icache
		ICACHE_ren = 1'b1;
		ICACHE_wen = 1'b0;
		ICACHE_wdata = 0;
		ICACHE_addr = PC[31:2]; 

		//alu
		case(ctrl_FA)
			2'b00: alu_in1 = rs1_data_EX;
			2'b01: alu_in1 = rd_wdata_MEM;
			2'b10: alu_in1 = rd_wdata_WB;
			default: alu_in1 = rs1_data_EX;
		endcase
		case(ctrl_FB)
			2'b00: alu_in2_temp = rs2_data_EX;
			2'b01: alu_in2_temp = rd_wdata_MEM_real;
			2'b10: alu_in2_temp = rd_wdata_WB;
			default:alu_in2_temp = rs2_data_EX;
		endcase
		alu_in2 = ctrl_ALUSrc_EX? imme_EX : alu_in2_temp;

        case (alu_ctrl_EX)
            4'd0: alu_out_EX = alu_in1 + alu_in2;
            4'd1: alu_out_EX = alu_in1 - alu_in2;
            4'd2: alu_out_EX = alu_in1 & alu_in2;
            4'd3: alu_out_EX = alu_in1 | alu_in2;
            4'd4: alu_out_EX = alu_in1 ^ alu_in2;
            4'd5: alu_out_EX = alu_in1 < alu_in2;
            4'd6: alu_out_EX = alu_in1 << alu_in2;
            4'd7: alu_out_EX = alu_in1 >> alu_in2;
            4'd8: alu_out_EX = alu_in1 >>> alu_in2;
            default: alu_out_EX = 0; 
        endcase

		//rd_w為運算後的值
		rd_wdata_EX = (ctrl_jal_EX | ctrl_jalr_EX)? PC_EX+4 : alu_out_EX;

		//mem_to_register (write rd)
		write_rd_MEM =  ctrl_memtoreg_MEM? read_data_MEM : rd_wdata_MEM_real;

	
		//jalr = rs1 + imme (rs1 forwarded)
		case(ctrl_FA_j) //實際上只有00,10會成立
			2'b00: PC_jalr_ID = rs1_data_ID + imme_ID;
			//2'b01: PC_jalr_ID = rd_wdata_EX + imme_ID;
			2'b10: PC_jalr_ID = rd_wdata_MEM + imme_ID;
			default: PC_jalr_ID = rs1_data_ID + imme_ID;
		endcase

		case(ctrl_FA_j) //實際上只有01
			//2'b00: compare_rs1 = rs1_data_ID;
			2'b01: compare_rs1 = rd_wdata_EX;
			//2'b10: compare_rs1 = rd_wdata_MEM;
			default: compare_rs1 = rs1_data_ID;
		endcase
		// case(ctrl_FB_j) //實際上rs2不需要forwarding
		// 	2'b00: compare_rs2 = rs2_data_ID;
		// 	2'b01: compare_rs2 = rd_wdata_EX;
		// 	2'b10: compare_rs2 = rd_wdata_MEM;
		// 	default: compare_rs2 = rs2_data_ID;
		// endcase
		compare_rs2 = rs2_data_ID;


		//PC_nxt, branch,jal or jalr or pc+4
		PC_B_ID = PC_ID + imme_ID;

		ctrl_bj_taken = ( ((ctrl_beq_ID & compare_rs1==compare_rs2) | ctrl_bne_ID & (compare_rs1!=compare_rs2)) | ctrl_jal_ID);

		PC_nxt = ctrl_jalr_ID? PC_jalr_ID : ctrl_bj_taken? PC_B_ID : PC+4;  //rs1+imme 或 pc+imme 或 pc+4;
    end


	//========= hazard ===========
	always @(*) begin
		//Forwding
		//rs1 at ID, for jalr
		if ( (ctrl_jalr_ID|ctrl_beq_ID|ctrl_bne_ID) & ctrl_regwrite_EX & rd_EX!=0 & rd_EX==rs1_ID) begin //EX
			ctrl_FA_j = 2'b01; 
		end
		else if ( (ctrl_jalr_ID|ctrl_beq_ID|ctrl_bne_ID) & ctrl_regwrite_MEM & rd_MEM!=0 & rd_MEM==rs1_ID) begin //MEM
			ctrl_FA_j = 2'b10; 
		end
		else begin
			ctrl_FA_j = 2'b00;
		end

		//rs2 at ID, for jalr
		if ( (ctrl_beq_ID|ctrl_bne_ID) & ctrl_regwrite_EX & rd_EX!=0 & rd_EX==rs2_ID) begin //EX
			ctrl_FB_j = 2'b01;  
		end
		else if ( (ctrl_beq_ID|ctrl_bne_ID) & ctrl_regwrite_MEM & rd_MEM!=0 & rd_MEM==rs2_ID) begin //MEM
			ctrl_FB_j = 2'b10;  
		end
		else begin
			ctrl_FB_j = 2'b00;
		end

		//(rs1 at EX)
		if (ctrl_regwrite_MEM & rd_MEM!=0 & rd_MEM==rs1_EX) begin
			ctrl_FA = 2'b01;  //差1
		end
		else if (ctrl_regwrite_WB & rd_WB!=0 & rd_WB==rs1_EX) begin
			ctrl_FA = 2'b10;  //差2
		end
		else begin
			ctrl_FA = 2'b00;
		end

		//(rs2 at EX)
		if (ctrl_regwrite_MEM & rd_MEM!=0 & rd_MEM==rs2_EX) begin //& type_EX!=3'd1 若是I-type，不需要用到r2
			ctrl_FB = 2'b01;
		end
		else if (ctrl_regwrite_WB & rd_WB!=0 & rd_WB==rs2_EX) begin
			ctrl_FB = 2'b10;
		end
		else begin
			ctrl_FB = 2'b00;
		end


		//load use hazard
		ctrl_lw_stall = (ctrl_memread_EX & (rd_EX==rs1_ID | rd_EX==rs2_ID));
	end


	//==== Sequential Circuit =========
    integer i;
    always @(posedge clk ) begin
        if (!rst_n) begin
            for (i = 0 ; i<32; i=i+1) begin
                register[i] <= 0 ;
            end

			imme_EX <= 0 ;

			ctrl_jalr_EX <= 0;
			ctrl_jal_EX  <= 0;

			ctrl_memread_EX <= 0;
			ctrl_memread_MEM <= 0;

			ctrl_memtoreg_EX <= 0;
			ctrl_memtoreg_MEM <= 0;
			ctrl_memtoreg_WB <= 0;

			ctrl_memwrite_EX <= 0;
			ctrl_memwrite_MEM <= 0;

			ctrl_regwrite_EX <= 0;
			ctrl_regwrite_MEM <= 0;
			ctrl_regwrite_WB <= 0;

			ctrl_ALUSrc_EX <= 0;

			//inst
			inst_ID <= 0;

			//alu
			alu_ctrl_EX <= 0;
			alu_out_MEM <= 0;
			alu_out_WB <= 0;

			//register
			rs1_EX <= 0;			
			rs2_EX <= 0;			
			rd_EX <= 0;
			rd_MEM <= 0;
			rd_WB <= 0;
		
			rs1_data_EX <= 0; 
			rs2_data_EX <= 0; 

			rd_wdata_MEM <= 0;
			rd_wdata_WB <= 0;

			//PC
			PC_ID <= 0;
			PC_EX <= 0;
            PC <= 0;

        end
        else if (!ICACHE_stall & !DCACHE_stall ) begin
            if (ctrl_regwrite_MEM & rd_MEM!=0) begin
                register[rd_MEM] <= write_rd_MEM;  //可用comb??????????????????????????????????????????
            end
            else begin
                register[0] <=0;
            end

			if (!ctrl_lw_stall) begin
				imme_EX <= imme_ID;

				ctrl_jalr_EX <= ctrl_jalr_ID; 

				ctrl_jal_EX  <= ctrl_jal_ID; 

				ctrl_memread_EX <= ctrl_memread_ID;
				ctrl_memread_MEM <= ctrl_memread_EX;

				ctrl_memtoreg_EX <= ctrl_memtoreg_ID;
				ctrl_memtoreg_MEM <= ctrl_memtoreg_EX;
				ctrl_memtoreg_WB <= ctrl_memtoreg_MEM;

				ctrl_memwrite_EX <= ctrl_memwrite_ID;
				ctrl_memwrite_MEM <= ctrl_memwrite_EX;

				ctrl_regwrite_EX <= ctrl_regwrite_ID;
				ctrl_regwrite_MEM <= ctrl_regwrite_EX;
				ctrl_regwrite_WB <= ctrl_regwrite_MEM;

				ctrl_ALUSrc_EX <= ctrl_ALUSrc_ID;
			end
			else begin //進到EX的東西全部清0
				imme_EX <= 0;

				ctrl_jalr_EX <= 0; 

				ctrl_jal_EX  <= 0; 

				ctrl_memread_EX <= 0;
				ctrl_memread_MEM <= ctrl_memread_EX;

				ctrl_memtoreg_EX <= 0;
				ctrl_memtoreg_MEM <= ctrl_memtoreg_EX;
				ctrl_memtoreg_WB <= ctrl_memtoreg_MEM;

				ctrl_memwrite_EX <= 0;
				ctrl_memwrite_MEM <= ctrl_memwrite_EX;

				ctrl_regwrite_EX <= 0;
				ctrl_regwrite_MEM <= ctrl_regwrite_EX;
				ctrl_regwrite_WB <= ctrl_regwrite_MEM;

				ctrl_ALUSrc_EX <= 0;
			end

			//memory
			wdata_MEM <= wdata_EX;

			//inst
			if (!ctrl_lw_stall) begin
				inst_ID <= inst_IF;
			end
			else begin
				inst_ID <= inst_ID;
			end

			//alu
			alu_out_MEM <= alu_out_EX;
			alu_out_WB <= alu_out_MEM;

			if (!ctrl_lw_stall) begin
				alu_ctrl_EX <= alu_ctrl_ID;
			end
			else begin
				alu_ctrl_EX <= 0;
			end

			//register
			if (!ctrl_lw_stall) begin
				rs1_EX <= rs1_ID;			
				rs2_EX <= rs2_ID;			
				rd_EX <= rd_ID;
				rd_MEM <= rd_EX;
				rd_WB <= rd_MEM;
			
				rs1_data_EX <= rs1_data_ID; 
				rs2_data_EX <= rs2_data_ID; 


				rd_wdata_MEM <= rd_wdata_EX;
				rd_wdata_WB <= ctrl_memread_MEM? read_data_MEM:rd_wdata_MEM;  //可用comb??????????????????????????????????????????

			end
			else begin
				rs1_EX <= 0;			
				rs2_EX <= 0;			
				rd_EX <= 0;
				rd_MEM <= rd_EX;
				rd_WB <= rd_MEM;
			
				rs1_data_EX <= 0; 
				rs2_data_EX <= 0; 


				rd_wdata_MEM <= rd_wdata_EX;
				rd_wdata_WB <= ctrl_memread_MEM? read_data_MEM:rd_wdata_MEM;
			end

			//PC
			if (!ctrl_lw_stall) begin
				PC_ID <= PC;
				PC_EX <= PC_ID;

				PC <= PC_nxt;
			end
			else begin
				PC_ID <= PC_ID;
				PC_EX <= 0;

				PC <= PC;
			end
        end
		//============ stall ================
		else begin 
            if (ctrl_regwrite_MEM & rd_MEM!=0) begin
                register[rd_MEM] <= register[rd_MEM];
            end
            else begin
                register[0] <=0;
            end

			ctrl_jalr_EX <= ctrl_jalr_EX;
			ctrl_jal_EX  <= ctrl_jal_EX; 

			ctrl_memread_EX <= ctrl_memread_EX;
			ctrl_memread_MEM <= ctrl_memread_MEM;

			ctrl_memtoreg_EX <= ctrl_memtoreg_EX;
			ctrl_memtoreg_MEM <= ctrl_memtoreg_MEM;
			ctrl_memtoreg_WB <= ctrl_memtoreg_WB;

			ctrl_memwrite_EX <= ctrl_memwrite_EX;
			ctrl_memwrite_MEM <= ctrl_memwrite_MEM;

			ctrl_regwrite_EX <= ctrl_regwrite_EX;
			ctrl_regwrite_MEM <= ctrl_regwrite_MEM;
			ctrl_regwrite_WB <= ctrl_regwrite_WB;

			ctrl_ALUSrc_EX <= ctrl_ALUSrc_EX;


			//inst
			inst_ID <= inst_ID;

			//imme
			imme_EX <= imme_EX;

			//alu
			alu_ctrl_EX <= alu_ctrl_EX;
			alu_out_MEM <= alu_out_MEM;
			alu_out_WB <= alu_out_WB;

			//register
			rs1_EX <= rs1_EX;			
			rs2_EX <= rs2_EX;			
			rd_EX <= rd_EX;
			rd_MEM <= rd_MEM;
			rd_WB <= rd_WB;
		
			rs1_data_EX <= rs1_data_EX; 
			rs2_data_EX <= rs2_data_EX; 


			rd_wdata_MEM <= rd_wdata_MEM;
			rd_wdata_WB <= rd_wdata_WB;

			//PC
			PC_ID <= PC_ID;
			PC_EX <= PC_EX;
            PC <= PC;
			
		end
    end

endmodule








//==== Sundry =============================================
	"""
	ADD		0000000 rs2 rs1 000 rd 0110011	R-type	+
	SUB		0100000 rs2 rs1 000 rd 0110011	R-type	-
	AND		0000000 rs2 rs1 111 rd 0110011	R-type	&
	OR		0000000 rs2 rs1 110 rd 0110011	R-type	|
	XOR		0000000 rs2 rs1 100 rd 0110011	R-type	^
	SLT		0000000 rs2 rs1 010 rd 0110011	R-type	<

	ADDI	imme[11:0] rs1 000 rd 0010011	I-type	+
	ANDI	imme[11:0] rs1 111 rd 0010011	I-type	&
	ORI		imme[11:0] rs1 110 rd 0010011	I-type	|
	XORI	imme[11:0] rs1 100 rd 0010011	I-type	^
	SLLI	0000000 sh rs1 001 rd 0010011	I-type	<<
	SRAI	0100000 sh rs1 101 rd 0010011	I-type	>>>
	SRLI	0000000 sh rs1 101 rd 0010011	I-type	>>
	SLTI	imme[11:0] rs1 010 rd 0010011	I-type	<
	LW		imme[11:0] rs1 010 rd 0000011	I-type	+
	JALR	imme[11:0] rs1 000 rd 1100111	I-type	+
	NOP(addi)imm[11:0] rs1 000 rd 0010011	I-type	+

	BEQ		imme[12|10:5] rs2 rs1 000 imm[4:1|11] 1100011	B-type	- 
	BNE		imme[12|10:5] rs2 rs1 001 imm[4:1|11] 1100011	B-type	- 

	JAL		imme[20|10:1|11|19:12] rd 1101111				J-type	+

	SW		imme[11:5] rs2 rs1 010 imm[4:0] 0100011			S-type +


	ADD		0000000 rs2 rs1 000 rd 0110011	R-type
	ADDI	imm[11:0] rs1 000 rd 0010011	I-type
	SUB		0100000 rs2 rs1 000 rd 0110011	R-type
	AND		0000000 rs2 rs1 111 rd 0110011	R-type
	ANDI	imme[11:0] rs1 111 rd 0010011	I-type
	OR		0000000 rs2 rs1 110 rd 0110011	R-type
	ORI		imme[11:0] rs1 110 rd 0010011	I-type
	XOR		0000000 rs2 rs1 100 rd 0110011	R-type
	XORI	imme[11:0] rs1 100 rd 0010011	I-type
	SLLI	0000000 sh rs1 001 rd 0010011	I-type
	SRAI	0100000 sh rs1 101 rd 0010011	I-type
	SRLI	0000000 sh rs1 101 rd 0010011	I-type
	SLT		0000000 rs2 rs1 010 rd 0110011	R-type
	SLTI	imme[11:0] rs1 010 rd 0010011	I-type
	BEQ		imme[12|10:5] rs2 rs1 000 imm[4:1|11] 110011	B-type
	BNE		imme[12|10:5] rs2 rs1 001 imm[4:1|11] 110011	B-type
	JAL		imme[20|10:1|11|19:12] rd 1101111				J-type
	JALR	imme[11:0] rs1 000 rd 110011
	LW		imm[11:0] rs1 010 rd 0000011	I-type
	SW		imme[11:5] rs2 rs1 010 imm[4:0] 0100011			S-type
	NOP(addi)imm[11:0] rs1 000 rd 0010011	I-type
	"""