
// PIPELINED MIPS32 PROCESSOR

module pipe_MIPS32 (clk1, clk2);

input clk1, clk2;   // Two-phase clock


// Pipeline Registers

reg [31:0] PC, IF_ID_IR, IF_ID_NPC;
reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
reg [2:0]  ID_EX_type, EX_MEM_type, MEM_WB_type;
reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
reg        EX_MEM_cond;
reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;


// Register File and Memory

reg [31:0] Reg [0:31];
reg [31:0] Mem [0:1023];


// Opcodes

parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011,
          SLT=6'b000100, MUL=6'b000101, HLT=6'b111111,
          LW=6'b001000, SW=6'b001001,
          ADDI=6'b001010, SUBI=6'b001011, SLTI=6'b001100,
          BNEQZ=6'b001101, BEQZ=6'b001110;


// Instruction Types

parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010,
          STORE=3'b011, BRANCH=3'b100, HALT=3'b101;


reg HALTED;
reg TAKEN_BRANCH;

// Initial safe values
initial begin
    PC = 0;
    HALTED = 0;
    TAKEN_BRANCH = 0;
    EX_MEM_IR = 0;
end


// IF STAGE

always @(posedge clk1)
if (HALTED == 0)
begin
    // Branch taken
    if (((EX_MEM_IR[31:26]==BEQZ)  && (EX_MEM_cond==1)) ||
        ((EX_MEM_IR[31:26]==BNEQZ) && (EX_MEM_cond==0)))
    begin
        IF_ID_IR  <= #2 Mem[EX_MEM_ALUOut];
        IF_ID_NPC <= #2 EX_MEM_ALUOut + 1;
        PC        <= #2 EX_MEM_ALUOut + 1;
        TAKEN_BRANCH <= #2 1'b1;
    end
    else
    begin
        IF_ID_IR  <= #2 Mem[PC];
        IF_ID_NPC <= #2 PC + 1;
        PC        <= #2 PC + 1;
        TAKEN_BRANCH <= #2 1'b0;
    end
end



// ID STAGE

always @(posedge clk2)
if (HALTED == 0)
begin
    // Read rs register
    if (IF_ID_IR[25:21] == 5'b00000)
        ID_EX_A <= #2 0;
    else
        ID_EX_A <= #2 Reg[IF_ID_IR[25:21]];

    // Read rt register
    if (IF_ID_IR[20:16] == 5'b00000)
        ID_EX_B <= #2 0;
    else
        ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];

    ID_EX_NPC <= #2 IF_ID_NPC;
    ID_EX_IR  <= #2 IF_ID_IR;

    // Sign extension
    ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, IF_ID_IR[15:0]};

    case (IF_ID_IR[31:26])
        ADD,SUB,AND,OR,SLT,MUL: ID_EX_type <= #2 RR_ALU;
        ADDI,SUBI,SLTI:         ID_EX_type <= #2 RM_ALU;
        LW:                     ID_EX_type <= #2 LOAD;
        SW:                     ID_EX_type <= #2 STORE;
        BNEQZ,BEQZ:             ID_EX_type <= #2 BRANCH;
        HLT:                    ID_EX_type <= #2 HALT;
        default:                ID_EX_type <= #2 HALT;
    endcase
end

// EX STAGE

always @(posedge clk1)
if (HALTED == 0)
begin
    EX_MEM_type <= #2 ID_EX_type;
    EX_MEM_IR   <= #2 ID_EX_IR;

    case (ID_EX_type)

        RR_ALU:
        case (ID_EX_IR[31:26])
            ADD: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
            SUB: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
            AND: EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
            OR : EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
            SLT: EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_B);
            MUL: EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
            default: EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
        endcase

        RM_ALU:
        case (ID_EX_IR[31:26])
            ADDI: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
            SUBI: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
            SLTI: EX_MEM_ALUOut <= #2 (ID_EX_A < ID_EX_Imm);
            default: EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
        endcase

        LOAD, STORE:
        begin
            EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
            EX_MEM_B      <= #2 ID_EX_B;
        end

        BRANCH:
        begin
            EX_MEM_ALUOut <= #2 ID_EX_NPC + ID_EX_Imm;
            EX_MEM_cond   <= #2 (ID_EX_A == 0);
        end

        default: ;
    endcase
end


// MEM STAGE

always @(posedge clk2)
if (HALTED == 0)
begin
    MEM_WB_type <= #2 EX_MEM_type;
    MEM_WB_IR   <= #2 EX_MEM_IR;

    case (EX_MEM_type)

        RR_ALU, RM_ALU:
            MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;

        LOAD:
            MEM_WB_LMD <= #2 Mem[EX_MEM_ALUOut];

        STORE:
            if (TAKEN_BRANCH == 0 && EX_MEM_ALUOut < 1024)
                Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;

        default: ;
    endcase
end


// WB STAGE

always @(posedge clk1)
if (HALTED == 0)
begin
    if (TAKEN_BRANCH == 0)
    case (MEM_WB_type)

        RR_ALU:
            Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut;

        RM_ALU:
            Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut;

        LOAD:
            Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD;

        HALT:
            HALTED <= #2 1'b1;

        default: ;
    endcase
end

endmodule