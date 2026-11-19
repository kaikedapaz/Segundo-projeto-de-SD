module lcd_formatter (
		
    input  wire         clk,              // Clock de 50 MHz
    input  wire         rst_n,            // Reset ativo em low
    input  wire         start_lcd,        // Sinaliza a atualizacao do display
    input  wire [2:0]   op_realizada,     // 8 instrucoes possiveis
    input  wire [3:0]   reg_dest_out,     // Endereço do registrador de destino
    input  wire [15:0]  resultado_16bits, // Valor numerico em complemento de 2
    output reg  [255:0] lcd_frame,        // O novo quadro do lcd (atualizado). 
                                          // possui 32 bytes, pois o LCD possui
                                          // 2 linhas, cada uma de 16 bytes cada.
                                          // cada byte e um caractere ASCII.
    output reg          frame_ready,      // Indica que ha um novo quadro
    output wire         busy              // Enquanto busy for 1, o modulo 
                                          // esta formando o novo quadro
);
    // Codigos das instrucoes (em ordem). 
    // Ao todo sao 8 instrucoes possiveis.
    localparam [2:0] OP_LOAD    = 3'b000;
    localparam [2:0] OP_ADD     = 3'b001;
    localparam [2:0] OP_ADDI    = 3'b010;
    localparam [2:0] OP_SUB     = 3'b011;
    localparam [2:0] OP_SUBI    = 3'b100;
    localparam [2:0] OP_MUL     = 3'b101;
    localparam [2:0] OP_CLEAR   = 3'b110;
    localparam [2:0] OP_DISPLAY = 3'b111;

    // Codigos ASCII dos simbolos 
    localparam [7:0] CH_SP    = 8'h20; // <-- Espaço
    localparam [7:0] CH_PLUS  = 8'h2B; // <-- Mais
    localparam [7:0] CH_MINUS = 8'h2D; // <-- Menos
    localparam [7:0] CH_LB    = 8'h5B; // <-- Colchete esquerdo
    localparam [7:0] CH_RB    = 8'h5D; // <-- Colchete direito

    // Estados do modulo
    localparam [1:0] S_IDLE = 2'd0;    // <-- Ocioso
    localparam [1:0] S_CONV = 2'd1;    // <-- Em conversao
    localparam [1:0] S_DONE = 2'd2;    // <-- Quadro concluido
	 
    //----------------------------------------------------------
    // Essa funçao associa a cada instrucao (operacao) um nome de 4 caracteres,
    // retornando cada um dos respectivos nomes
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
                // O caso padrao (nada)
                default:    name_rom = "    ";
            endcase
        end
    endfunction
    //----------------------------------------------------------
	
    //----------------------------------------------------------
    // Ajuste do algoritmo Double Dabble para conversao binario -> BCD.
    // Verifica cada um dos 5 digitos decimais (nibbles de 4 bits) e,
    // se algum for >= 5, soma 3 antes do proximo deslocamento a esquerda
    function [19:0] dd_adjust;
        input [19:0] b;
        reg   [19:0] r;
        begin
            r[19:16] = (b[19:16] >= 4'd5) ? (b[19:16] + 4'd3) : b[19:16]; // <-- Dezena de milhar
            r[15:12] = (b[15:12] >= 4'd5) ? (b[15:12] + 4'd3) : b[15:12]; // <-- Unidade de milhar
            r[11:8]  = (b[11:8]  >= 4'd5) ? (b[11:8]  + 4'd3) : b[11:8];  // <-- Centena
            r[7:4]   = (b[7:4]   >= 4'd5) ? (b[7:4]   + 4'd3) : b[7:4];   // <-- Dezena
            r[3:0]   = (b[3:0]   >= 4'd5) ? (b[3:0]   + 4'd3) : b[3:0];   // <-- Unidade
            dd_adjust = r;
        end
    endfunction
    //----------------------------------------------------------

    //----------------------------------------------------------
    // Cria o novo quadro que aparecera no display e 
    // o monta no vetor f (256 bits = 32 caracteres ASCII)
    function [255:0] build_frame;
        input        idle;
        input [2:0]  op;
        input [3:0]  dest;
        input        neg;
        input [19:0] bcd;
        reg   [255:0] f;
        reg   [31:0]  nm;
        reg           is_clear;
        begin
            f        = {32{CH_SP}};                  // <-- Preenche toda a tela com espacos
            is_clear = (!idle) && (op == OP_CLEAR);  // <-- Verifica se a operacao e CLEAR

            // Posicoes 0 a 3 (linha 1): escreve o nome da operacao ou "----" no reset
            if (!idle) begin
                nm = name_rom(op);
                f[255-8*0 -: 8] = nm[31:24]; // <-- 1o caractere da operacao
                f[255-8*1 -: 8] = nm[23:16]; // <-- 2o caractere da operacao
                f[255-8*2 -: 8] = nm[15:8];  // <-- 3o caractere da operacao
                f[255-8*3 -: 8] = nm[7:0];   // <-- 4o caractere da operacao
            end else begin
                f[255-8*0 -: 8] = CH_MINUS;
                f[255-8*1 -: 8] = CH_MINUS;
                f[255-8*2 -: 8] = CH_MINUS;
                f[255-8*3 -: 8] = CH_MINUS;
            end

            // Se nao for CLEAR, exibe o registrador de destino e o resultado numerico
            if (!is_clear) begin
                // Posicoes 10 a 15 (linha 1): exibe [xxxx] com o endereco em binario
                f[255-8*10 -: 8] = CH_LB; // <-- Abre colchete '['
                f[255-8*15 -: 8] = CH_RB; // <-- Fecha colchete ']'
                if (!idle) begin
                    // Concatena 0011000 (0x30) com cada bit para virar ASCII '0' ou '1'
                    f[255-8*11 -: 8] = {7'b0011000, dest[3]};
                    f[255-8*12 -: 8] = {7'b0011000, dest[2]};
                    f[255-8*13 -: 8] = {7'b0011000, dest[1]};
                    f[255-8*14 -: 8] = {7'b0011000, dest[0]};
                end else begin
                    // No modo idle (reset), preenche com "----" dentro dos colchetes
                    f[255-8*11 -: 8] = CH_MINUS;
                    f[255-8*12 -: 8] = CH_MINUS;
                    f[255-8*13 -: 8] = CH_MINUS;
                    f[255-8*14 -: 8] = CH_MINUS;
                end

                // Posicoes 26 a 31 (canto direito da linha 2): sinal + 5 digitos decimais
                f[255-8*26 -: 8] = neg ? CH_MINUS : CH_PLUS; // <-- Sinal '+' ou '-'
                // Concatena 4'h3 (0x30) com cada digito BCD para virar ASCII '0'..'9'
                f[255-8*27 -: 8] = {4'h3, bcd[19:16]}; // <-- Digito da dezena de milhar
                f[255-8*28 -: 8] = {4'h3, bcd[15:12]}; // <-- Digito da unidade de milhar
                f[255-8*29 -: 8] = {4'h3, bcd[11:8]};  // <-- Digito da centena
                f[255-8*30 -: 8] = {4'h3, bcd[7:4]};   // <-- Digito da dezena
                f[255-8*31 -: 8] = {4'h3, bcd[3:0]};   // <-- Digito da unidade
            end

            build_frame = f;
        end
    endfunction
    //----------------------------------------------------------

    // Registradores internos do modulo
    reg [1:0]  state;   // <-- Estado atual da maquina de estados (FSM)
    reg [2:0]  op_q;    // <-- Guarda a operacao capturada no inicio
    reg [3:0]  dest_q;  // <-- Guarda o registrador de destino capturado
    reg        neg_q;   // <-- Guarda o bit de sinal (1 = negativo, 0 = positivo)
    reg [15:0] shreg;   // <-- Registrador de deslocamento com a magnitude do numero
    reg [19:0] bcd;     // <-- Acumulador dos 5 digitos BCD durante a conversao
    reg [4:0]  cnt;     // <-- Contador de 0 a 15 para os 16 deslocamentos (shifts)
    reg        start_q; // <-- Armazena o estado anterior de start_lcd
	 
    // Detecta borda de subida em start_lcd (transicao de 0 para 1)
    wire start_edge = start_lcd & ~start_q;

    // Modulo ocupado sempre que nao estiver no estado ocioso (S_IDLE)
    assign busy = (state != S_IDLE);

    // Saida combinacional com os digitos BCD ja ajustados pelo Double Dabble
    wire [19:0] bcd_adj = dd_adjust(bcd);

    //----------------------------------------------------------
    // Logica sequencial principal e maquina de estados do formatador
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Zera todos os registradores e exibe o quadro padrao de reset
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
            start_q     <= start_lcd; // <-- Atualiza historico para deteccao de borda
            frame_ready <= 1'b0;      // <-- Garante que frame_ready dure apenas 1 ciclo

            case (state)
                // Estado ocioso: aguarda pulso de inicio para capturar as entradas
                S_IDLE: begin
                    if (start_edge) begin
                        op_q   <= op_realizada;
                        dest_q <= reg_dest_out;
                        neg_q  <= resultado_16bits[15]; // <-- Salva o bit de sinal (MSB)
                        // Se for negativo, converte de complemento de 2 para modulo positivo
                        shreg  <= resultado_16bits[15] ? (~resultado_16bits + 16'd1)
                                                       : resultado_16bits;
                        bcd    <= 20'd0;
                        cnt    <= 5'd0;
                        state  <= S_CONV; // <-- Avanca para o estado de conversao
                    end
                end

                // Estado de conversao: executa 16 ciclos do algoritmo Double Dabble
                S_CONV: begin
                    {bcd, shreg} <= {bcd_adj, shreg} << 1; // <-- Desloca 1 bit para a esquerda
                    cnt          <= cnt + 5'd1;
                    if (cnt == 5'd15)
                        state <= S_DONE; // <-- Apos 16 shifts, finaliza a conversao
                end

                // Estado de conclusao: monta o quadro final e sinaliza que esta pronto
                S_DONE: begin
                    lcd_frame   <= build_frame(1'b0, op_q, dest_q, neg_q, bcd);
                    frame_ready <= 1'b1;   // <-- Pulsa frame_ready por 1 ciclo de clock
                    state       <= S_IDLE; // <-- Retorna para aguardar proxima atualizacao
                end

                default: state <= S_IDLE;
            endcase
        end
    end
    //----------------------------------------------------------

endmodule
