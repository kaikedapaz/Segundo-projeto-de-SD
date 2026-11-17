module lcd_formatter (
    input  wire         clk,               // clock de 50 MHz
    input  wire         rst_n,             // ativo em baixo (ligar a system_on)
    input  wire         start_lcd,         // pulso: ha resultado novo
    input  wire [2:0]   op_realizada,      // opcode da instrucao executada
    input  wire [3:0]   reg_dest_out,      // registrador de destino (ou o consultado, no DISPLAY)
    input  wire [15:0]  resultado_16bits,  // resultado em complemento de 2
    output reg  [255:0] lcd_frame,         // 32 caracteres ASCII prontos
    output reg          frame_ready,       // pulso de 1 ciclo: lcd_frame novo
    output wire         busy               // 1 enquanto converte
);

    // ---------------------------------------------------------------- Constantes
    localparam [2:0] OP_LOAD    = 3'b000;
    localparam [2:0] OP_ADD     = 3'b001;
    localparam [2:0] OP_ADDI    = 3'b010;
    localparam [2:0] OP_SUB     = 3'b011;
    localparam [2:0] OP_SUBI    = 3'b100;
    localparam [2:0] OP_MUL     = 3'b101;
    localparam [2:0] OP_CLEAR   = 3'b110;
    localparam [2:0] OP_DISPLAY = 3'b111;

    localparam [7:0] CH_SP    = 8'h20;  // ' '
    localparam [7:0] CH_PLUS  = 8'h2B;  // '+'
    localparam [7:0] CH_MINUS = 8'h2D;  // '-'
    localparam [7:0] CH_LB    = 8'h5B;  // '['
    localparam [7:0] CH_RB    = 8'h5D;  // ']'

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_CONV = 2'd1;
    localparam [1:0] S_DONE = 2'd2;

    // ---------------------------------------------------------------- Funcoes

    // Tabela de nomes (4 caracteres, o primeiro no byte mais significativo).
    function [31:0] name_rom;
        input [2:0] op;
        begin
            case (op)
                OP_LOAD:    name_rom = "LOAD";
                OP_ADD:     name_rom = "ADD ";
                OP_ADDI:    name_rom = "ADDI";
                OP_SUB:     name_rom = "SUB ";
                OP_SUBI:    name_rom = "SUBI";
                OP_MUL:     name_rom = "MUL ";
                OP_CLEAR:   name_rom = "CLR ";
                OP_DISPLAY: name_rom = "DPL ";
                default:    name_rom = "    ";
            endcase
        end
    endfunction

    // Passo "soma 3" do Double Dabble: cada digito BCD >= 5 recebe +3.
    function [19:0] dd_adjust;
        input [19:0] b;
        reg   [19:0] r;
        begin
            r[19:16] = (b[19:16] >= 4'd5) ? (b[19:16] + 4'd3) : b[19:16];
            r[15:12] = (b[15:12] >= 4'd5) ? (b[15:12] + 4'd3) : b[15:12];
            r[11:8]  = (b[11:8]  >= 4'd5) ? (b[11:8]  + 4'd3) : b[11:8];
            r[7:4]   = (b[7:4]   >= 4'd5) ? (b[7:4]   + 4'd3) : b[7:4];
            r[3:0]   = (b[3:0]   >= 4'd5) ? (b[3:0]   + 4'd3) : b[3:0];
            dd_adjust = r;
        end
    endfunction

    // Monta o quadro completo de 32 caracteres.
    //   idle = 1 -> quadro inicial (tela recem-ligada)
    function [255:0] build_frame;
        input        idle;
        input [2:0]  op;
        input [3:0]  dest;
        input        neg;     // 1 = resultado negativo
        input [19:0] bcd;     // 5 digitos BCD do modulo
        reg   [255:0] f;
        reg   [31:0]  nm;
        reg           is_clear;
        begin
            f        = {32{CH_SP}};              // tudo em branco
            is_clear = (!idle) && (op == OP_CLEAR);

            // Linha 1, esquerda: nome da operacao (caracteres 0..3)
            if (!idle) begin
                nm = name_rom(op);
                f[255-8*0 -: 8] = nm[31:24];
                f[255-8*1 -: 8] = nm[23:16];
                f[255-8*2 -: 8] = nm[15:8];
                f[255-8*3 -: 8] = nm[7:0];
            end

            if (!is_clear) begin
                // Linha 1, direita: "[dddd]" (caracteres 10..15)
                f[255-8*10 -: 8] = CH_LB;
                f[255-8*15 -: 8] = CH_RB;
                if (!idle) begin
                    f[255-8*11 -: 8] = {7'b0011000, dest[3]};  // '0' ou '1'
                    f[255-8*12 -: 8] = {7'b0011000, dest[2]};
                    f[255-8*13 -: 8] = {7'b0011000, dest[1]};
                    f[255-8*14 -: 8] = {7'b0011000, dest[0]};
                end

                // Linha 2, direita: sinal + 5 digitos (caracteres 26..31)
                f[255-8*26 -: 8] = neg ? CH_MINUS : CH_PLUS;
                f[255-8*27 -: 8] = {4'h3, bcd[19:16]};  // 8'h30 + digito
                f[255-8*28 -: 8] = {4'h3, bcd[15:12]};
                f[255-8*29 -: 8] = {4'h3, bcd[11:8]};
                f[255-8*30 -: 8] = {4'h3, bcd[7:4]};
                f[255-8*31 -: 8] = {4'h3, bcd[3:0]};
            end

            build_frame = f;
        end
    endfunction

    // ---------------------------------------------------------------- Registradores
    reg [1:0]  state;
    reg [2:0]  op_q;       // opcode travado
    reg [3:0]  dest_q;     // destino travado
    reg        neg_q;      // sinal travado
    reg [15:0] shreg;      // modulo ainda nao consumido pelo Double Dabble
    reg [19:0] bcd;        // 5 digitos BCD em construcao
    reg [4:0]  cnt;        // contador de deslocamentos (0..15)
    reg        start_q;    // para detectar a borda de subida de start_lcd

    wire start_edge = start_lcd & ~start_q;
    assign busy = (state != S_IDLE);

    // Passo seguinte do Double Dabble (combinacional)
    wire [19:0] bcd_adj = dd_adjust(bcd);

    // ---------------------------------------------------------------- Controle
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            op_q        <= 3'd0;
            dest_q      <= 4'd0;
            neg_q       <= 1'b0;
            shreg       <= 16'd0;
            bcd         <= 20'd0;
            cnt         <= 5'd0;
            start_q     <= 1'b0;
            frame_ready <= 1'b0;
            lcd_frame   <= build_frame(1'b1, 3'd0, 4'd0, 1'b0, 20'd0);
        end else begin
            start_q     <= start_lcd;
            frame_ready <= 1'b0;                    // pulso de 1 ciclo

            case (state)
                // Espera um pulso de start_lcd e trava os dados da CPU.
                S_IDLE: begin
                    if (start_edge) begin
                        op_q   <= op_realizada;
                        dest_q <= reg_dest_out;
                        neg_q  <= resultado_16bits[15];
                        // Modulo: se negativo, inverte e soma 1 (complemento de 2).
                        // -32768 (16'h8000) continua 16'h8000 = 32768 sem sinal: correto.
                        shreg  <= resultado_16bits[15] ? (~resultado_16bits + 16'd1)
                                                       : resultado_16bits;
                        bcd    <= 20'd0;
                        cnt    <= 5'd0;
                        state  <= S_CONV;
                    end
                end

                // 16 iteracoes: soma 3 nos digitos >= 5 e desloca 1 bit.
                S_CONV: begin
                    {bcd, shreg} <= {bcd_adj, shreg} << 1;
                    cnt          <= cnt + 5'd1;
                    if (cnt == 5'd15)
                        state <= S_DONE;
                end

                // Publica o quadro e avisa o lcd_controller.
                S_DONE: begin
                    lcd_frame   <= build_frame(1'b0, op_q, dest_q, neg_q, bcd);
                    frame_ready <= 1'b1;
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
