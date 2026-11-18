module instruction_decoder (
    input  wire        clk,          
    input  wire        system_on,   
    input  wire        send_pulse,   
    input  wire [17:0] sw,           

    output reg  [2:0]  opcode,       
    output reg  [3:0]  reg_dest,     
    output reg  [3:0]  reg_src1,     
    output reg  [3:0]  reg_src2,    
    output reg  [15:0] imm_16bits,   
    output reg         use_imm,      
    output reg         is_special,   
    output reg         valid_instr   
);

    // 1. DEFINIÇÃO DOS OPCODES
    localparam OP_LOAD    = 3'b000;
    localparam OP_ADD     = 3'b001;
    localparam OP_ADDI    = 3'b010;
    localparam OP_SUB     = 3'b011;
    localparam OP_SUBI    = 3'b100;
    localparam OP_MUL     = 3'b101;
    localparam OP_CLEAR   = 3'b110;
    localparam OP_DISPLAY = 3'b111;

    // 2. EXTRAÇÃO COMBINACIONAL UNIFICADA (OPCODE sempre em SW[17:15])
    wire [2:0]  op_in      = sw[17:15];
    wire        imm_sinal  = sw[6];
    wire [15:0] imm_modulo = {10'd0, sw[5:0]}; 
    wire [15:0] imm_comp2  = imm_sinal ? (~imm_modulo + 16'd1) : imm_modulo;

    // 3. LÓGICA SÍNCRONA DE CAPTURA E DECODIFICAÇÃO
    always @(posedge clk) begin
        if (!system_on) begin
            opcode      <= 3'b000;
            reg_dest    <= 4'b0000;
            reg_src1    <= 4'b0000;
            reg_src2    <= 4'b0000;
            imm_16bits  <= 16'd0;
            use_imm     <= 1'b0;
            is_special  <= 1'b0;
            valid_instr <= 1'b0;
        end else begin
            valid_instr <= 1'b0;

            if (send_pulse) begin
                opcode      <= op_in;
                valid_instr <= 1'b1;

                case (op_in)
                    // TIPO 1: Operações com Registradores
                    // [17:15] Opcode | [14:11] Dest | [10:7] Src1 | [6:3] Src2
                    OP_ADD, OP_SUB: begin
                        reg_dest   <= sw[14:11];
                        reg_src1   <= sw[10:7];
                        reg_src2   <= sw[6:3];
                        imm_16bits <= 16'd0;
                        use_imm    <= 1'b0;
                        is_special <= 1'b0;
                    end

                    // TIPO 2: Operações com Imediato
                    // [17:15] Opcode | [14:11] Dest | [10:7] Src1 | [6] Sinal | [5:0] Imm
                    OP_ADDI, OP_SUBI, OP_MUL: begin
                        reg_dest   <= sw[14:11];
                        reg_src1   <= sw[10:7];
                        reg_src2   <= 4'b0000;
                        imm_16bits <= imm_comp2;
                        use_imm    <= 1'b1;
                        is_special <= 1'b0;
                    end

                    // TIPO 3: Carga
                    // [17:15] Opcode | [14:11] Dest | [6] Sinal | [5:0] Imm
                    OP_LOAD: begin
                        reg_dest   <= sw[14:11];
                        reg_src1   <= 4'b0000;
                        reg_src2   <= 4'b0000;
                        imm_16bits <= imm_comp2;
                        use_imm    <= 1'b1;
                        is_special <= 1'b0;
                    end

                    // TIPO ESPECIAL: CLEAR e DISPLAY
                    // [17:15] Opcode | [14:11] Registrador a exibir (no DISPLAY)
                    OP_CLEAR, OP_DISPLAY: begin
                        reg_dest   <= sw[14:11];
                        reg_src1   <= sw[14:11];
                        reg_src2   <= 4'b0000;
                        imm_16bits <= 16'd0;
                        use_imm    <= 1'b0;
                        is_special <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
