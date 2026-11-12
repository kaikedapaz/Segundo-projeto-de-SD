module ula (
    input  wire [2:0]  opcode,      // Opcode de 3 bits (instruções de 000 a 101)
    input  wire signed [15:0] operand_a,   // Primeiro operando (geralmente Src1)
    input  wire signed [15:0] operand_b,   // Segundo operando (Src2 ou Imediato)
    output reg signed [15:0] result       // Resultado final de 16 bits
);

    // Definição dos opcodes segundo a tabela do projeto
    localparam OP_LOAD  = 3'b000;
    localparam OP_ADD   = 3'b001;
    localparam OP_ADDI  = 3'b010;
    localparam OP_SUB   = 3'b011;
    localparam OP_SUBI  = 3'b100;
    localparam OP_MUL   = 3'b101;

    always @(*) begin
        case (opcode)
            OP_LOAD: begin
                result = operand_b; // No LOAD, o resultado é o próprio imediato
            end
            
            OP_ADD, OP_ADDI: begin
                result = operand_a + operand_b;
            end
            
            OP_SUB, OP_SUBI: begin
                result = operand_a - operand_b;
            end
            
            OP_MUL: begin
                result = operand_a * operand_b;
            end
            
            default: begin
                result = 16'h0000;
            end
        endcase
    end

endmodule