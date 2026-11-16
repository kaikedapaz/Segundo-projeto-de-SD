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

    // 1. DEFINIÇÃO DOS OPCODES (Tabela da Página 6 do Projeto)
    localparam OP_LOAD    = 3'b000;
    localparam OP_ADD     = 3'b001;
    localparam OP_ADDI    = 3'b010;
    localparam OP_SUB     = 3'b011;
    localparam OP_SUBI    = 3'b100;
    localparam OP_MUL     = 3'b101;
    localparam OP_CLEAR   = 3'b110;
    localparam OP_DISPLAY = 3'b111;

    // 2. EXTRAÇÃO COMBINACIONAL DOS CAMPOS (Fatiamento dos Switches)
    wire [2:0] op_tipo2 = sw[17:15]; 
    wire [2:0] op_tipo1 = sw[14:12]; 
    wire [2:0] op_tipo3 = sw[13:11]; 
    wire [2:0] op_esp   = sw[6:4];  
    wire        imm_sinal   = sw[6];
    wire [15:0] imm_modulo  = {10'd0, sw[5:0]}; 
    wire [15:0] imm_comp2   = imm_sinal ? (~imm_modulo + 16'd1) : imm_modulo;

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
                
                if (op_tipo2 == OP_ADDI || op_tipo2 == OP_SUBI || op_tipo2 == OP_MUL) begin
                    // TIPO 2: Operações Aritméticas com Imediato (18 bits)
                    opcode      <= op_tipo2;
                    reg_dest    <= sw[14:11];
                    reg_src1    <= sw[10:7];
                    reg_src2    <= 4'b0000;
                    imm_16bits  <= imm_comp2;
                    use_imm     <= 1'b1;
                    is_special  <= 1'b0;
                    valid_instr <= 1'b1;

                end else if (op_tipo1 == OP_ADD || op_tipo1 == OP_SUB) begin
                    // TIPO 1: Operações Aritméticas com Registradores (15 bits)
                    opcode      <= op_tipo1;
                    reg_dest    <= sw[11:8];
                    reg_src1    <= sw[7:4];
                    reg_src2    <= sw[3:0];
                    imm_16bits  <= 16'd0;
                    use_imm     <= 1'b0;
                    is_special  <= 1'b0;
                    valid_instr <= 1'b1;

                end else if ((sw[17:7] == 11'd0) && (op_esp == OP_CLEAR || op_esp == OP_DISPLAY)) begin
                    // TIPO ESPECIAL: Controle e Saída (8 bits)
                    opcode      <= op_esp;
                    reg_dest    <= sw[3:0]; 
                    reg_src1    <= sw[3:0]; 
                    reg_src2    <= 4'b0000;
                    imm_16bits  <= 16'd0;
                    use_imm     <= 1'b0;
                    is_special  <= 1'b1;
                    valid_instr <= 1'b1;

                end else if ((sw[17:14] == 4'd0) && (op_tipo3 == OP_LOAD)) begin
                    // TIPO 3: Operações de Carga (14 bits)
                    opcode      <= OP_LOAD;
                    reg_dest    <= sw[10:7];
                    reg_src1    <= 4'b0000;
                    reg_src2    <= 4'b0000;
                    imm_16bits  <= imm_comp2;
                    use_imm     <= 1'b1;
                    is_special  <= 1'b0;
                    valid_instr <= 1'b1;
                end
            end
        end
    end

endmodule