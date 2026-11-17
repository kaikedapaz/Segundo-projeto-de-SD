module module_mini_cpu (
    // =========================================================================
    // PORTAS DE ENTRADA DA PLACA DE2-115
    // =========================================================================
    input  wire               CLOCK_50,         // Clock principal da placa (50 MHz)
    input  wire [17:0]        SW,               // 18 chaves (switches) para entrada da instrução
    input  wire [3:0]         KEY,              // Botões físicos (KEY[0] = Ligar, KEY[1] = Enviar)

    // =========================================================================
    // SAÍDAS DA CPU (PRONTAS PARA CONECTAR AO MÓDULO DO LCD)
    // =========================================================================
    output wire               system_on,        // Indica se o sistema está ligado (1) ou desligado (0)
    output wire               power_on_pulse,   // Pulso de 1 ciclo no momento em que o sistema é ligado
    output wire               power_off_pulse,  // Pulso de 1 ciclo no momento em que o sistema é desligado
    output reg  [2:0]         op_realizada,     // Opcode da última instrução executada
    output reg  [3:0]         reg_dest_out,     // Endereço do registrador de destino (0 a 15)
    output reg  signed [15:0] resultado_16bits, // Resultado final da operação (16 bits com sinal)
    output reg                start_lcd         // Pulso de 1 ciclo avisando que o resultado está pronto
);

    // =========================================================================
    // 1. DECLARAÇÃO DOS FIOS INTERNOS DE CONEXÃO ENTRE OS MÓDULOS
    // =========================================================================
    
    // Sinais vindos do input_controller
    wire        send_pulse;      // Pulso único gerado ao soltar o botão Enviar
    wire        mem_reset_base;  // Mantém a memória zerada quando desligado ou reiniciando

    // Sinais vindos do instruction_decoder
    wire [2:0]  dec_opcode;      // Opcode extraído dos switches
    wire [3:0]  dec_reg_dest;    // Registrador de destino extraído
    wire [3:0]  dec_reg_src1;    // Registrador fonte 1 (Src1) extraído
    wire [3:0]  dec_reg_src2;    // Registrador fonte 2 (Src2) extraído
    wire [15:0] dec_imm_16bits;  // Valor imediato já convertido para Complemento de 2 (16 bits)
    wire        dec_use_imm;     // 1 se a instrução usa imediato (LOAD, ADDI, SUBI, MUL); 0 caso contrário
    wire        dec_is_special;  // 1 se a instrução for CLEAR ou DISPLAY
    wire        dec_valid_instr; // Pulso de 1 ciclo confirmando que uma instrução válida foi capturada

    // Sinais de controle e dados da memória (RAM 16x16)
    wire        mem_reset;       // Sinal combinado que zera todos os registradores
    reg         mem_we;          // Write Enable: habilita escrita na memória quando em '1'
    wire [15:0] mem_read_data1;  // Valor lido do registrador Src1
    wire [15:0] mem_read_data2;  // Valor lido do registrador Src2
    reg  [15:0] mem_write_data;  // Dado a ser gravado no registrador de destino (Dest)

    // Sinais de entrada e saída da ULA
    wire signed [15:0] ula_operand_a; // Primeiro operando enviado para a ULA
    wire signed [15:0] ula_operand_b; // Segundo operando enviado para a ULA
    wire signed [15:0] ula_result;    // Resultado calculado pela ULA

    // =========================================================================
    // 2. INSTANCIAÇÃO DOS 4 MÓDULOS EXISTENTES
    // =========================================================================

    // Módulo 1: Controlador de Entradas (Debounce dos botões + Estado Liga/Desliga)
    input_controller u_input_ctrl (
        .clk             (CLOCK_50),
        .key_ligar_raw   (KEY[0]),          // Botão físico de Ligar/Desligar
        .key_enviar_raw  (KEY[1]),          // Botão físico de Enviar instrução
        .system_on       (system_on),
        .send_pulse      (send_pulse),
        .power_on_pulse  (power_on_pulse),
        .power_off_pulse (power_off_pulse),
        .mem_reset_base  (mem_reset_base)
    );

    // Módulo 2: Decodificador de Instruções (Fatia os 18 switches conforme o Opcode)
    instruction_decoder u_decoder (
        .clk         (CLOCK_50),
        .system_on   (system_on),
        .send_pulse  (send_pulse),
        .sw          (SW),
        .opcode      (dec_opcode),
        .reg_dest    (dec_reg_dest),
        .reg_src1    (dec_reg_src1),
        .reg_src2    (dec_reg_src2),
        .imm_16bits  (dec_imm_16bits),
        .use_imm     (dec_use_imm),
        .is_special  (dec_is_special),
        .valid_instr (dec_valid_instr)
    );

    // Módulo 3: Banco de Memória (16 registradores de 16 bits: R0 a R15)
    reg fsm_clear_mem; // Ativado pela FSM quando a instrução executada for CLEAR (110)
    
    // A memória é zerada tanto ao desligar/ligar o sistema quanto na instrução CLEAR
    assign mem_reset = mem_reset_base || fsm_clear_mem;

    memoria u_memoria (
        .clk        (CLOCK_50),
        .reset      (mem_reset),
        .we         (mem_we),
        .read_addr1 (dec_reg_src1),     // Endereço de leitura 1 (Src1)
        .read_addr2 (dec_reg_src2),     // Endereço de leitura 2 (Src2)
        .write_addr (dec_reg_dest),     // Endereço de escrita (Dest)
        .write_data (mem_write_data),   // Dado a ser escrito
        .read_data1 (mem_read_data1),   // Saída assíncrona do registrador Src1
        .read_data2 (mem_read_data2)    // Saída assíncrona do registrador Src2
    );

    // Módulo 4: Unidade Lógica e Aritmética (ULA)
    // Multiplexador do Operando B: escolhe entre o imediato ou o registrador Src2
    assign ula_operand_a = mem_read_data1;
    assign ula_operand_b = dec_use_imm ? dec_imm_16bits : mem_read_data2;

    ula u_ula (
        .opcode    (dec_opcode),
        .operand_a (ula_operand_a),
        .operand_b (ula_operand_b),
        .result    (ula_result)
    );

    // =========================================================================
    // 3. MÁQUINA DE ESTADOS FINITOS (FSM) DA UNIDADE DE CONTROLE
    // =========================================================================
    // Definição dos 5 estados do ciclo de execução de uma instrução
    localparam S_IDLE       = 3'd0; // Aguardando uma instrução válida ser enviada
    localparam S_READ       = 3'd1; // Aguarda estabilização da leitura dos registradores
    localparam S_EXECUTE    = 3'd2; // Captura o resultado da ULA ou o valor lido (DISPLAY)
    localparam S_WRITEBACK  = 3'd3; // Grava o resultado na memória (ou limpa no CLEAR)
    localparam S_UPDATE_LCD = 3'd4; // Atualiza as saídas e dispara o gatilho do LCD

    // Opcodes das instruções especiais tratadas diretamente pelo controle
    localparam OP_CLEAR     = 3'b110;
    localparam OP_DISPLAY   = 3'b111;

    reg [2:0]         state;           // Registrador do estado atual da FSM
    reg signed [15:0] exec_result_reg; // Registrador temporário para segurar o resultado

    always @(posedge CLOCK_50) begin
        // Se o sistema estiver desligado, reinicia todos os sinais de controle e saídas
        if (!system_on) begin
            state            <= S_IDLE;
            mem_we           <= 1'b0;
            fsm_clear_mem    <= 1'b0;
            mem_write_data   <= 16'd0;
            exec_result_reg  <= 16'd0;
            op_realizada     <= 3'd0;
            reg_dest_out     <= 4'd0;
            resultado_16bits <= 16'd0;
            start_lcd        <= 1'b0;
        end else begin
            // Sinais de pulso permanecem em '0' por padrão, ativando apenas no estado exato
            mem_we        <= 1'b0;
            fsm_clear_mem <= 1'b0;
            start_lcd     <= 1'b0;

            case (state)
                // -------------------------------------------------------------
                // ESTADO 0 (IDLE): Espera o decodificador sinalizar instrução válida
                // -------------------------------------------------------------
                S_IDLE: begin
                    if (dec_valid_instr) begin
                        state <= S_READ;
                    end
                end

                // -------------------------------------------------------------
                // ESTADO 1 (READ): Dá 1 ciclo para os endereços Src1/Src2
                // estabilizarem na leitura da memória e propagarem até a ULA
                // -------------------------------------------------------------
                S_READ: begin
                    state <= S_EXECUTE;
                end

                // -------------------------------------------------------------
                // ESTADO 2 (EXECUTE): Seleciona o resultado final da operação
                // -------------------------------------------------------------
                S_EXECUTE: begin
                    if (dec_opcode == OP_DISPLAY) begin
                        // Na instrução DISPLAY, o valor exibido é o conteúdo de Src1
                        exec_result_reg <= mem_read_data1;
                    end else if (dec_opcode == OP_CLEAR) begin
                        // Na instrução CLEAR, o resultado numérico é zerado
                        exec_result_reg <= 16'd0;
                    end else begin
                        // Para LOAD, ADD, ADDI, SUB, SUBI e MUL, pega a saída da ULA
                        exec_result_reg <= ula_result;
                    end
                    state <= S_WRITEBACK;
                end

                // -------------------------------------------------------------
                // ESTADO 3 (WRITEBACK): Atualiza o banco de registradores
                // -------------------------------------------------------------
                S_WRITEBACK: begin
                    if (dec_opcode == OP_CLEAR) begin
                        // Ativa o reset da memória por 1 ciclo para zerar R0..R15
                        fsm_clear_mem <= 1'b1;
                    end else if (dec_opcode != OP_DISPLAY) begin
                        // DISPLAY apenas lê; todas as outras instruções gravam em Dest
                        mem_write_data <= exec_result_reg;
                        mem_we         <= 1'b1;
                    end
                    state <= S_UPDATE_LCD;
                end

                // -------------------------------------------------------------
                // ESTADO 4 (UPDATE_LCD): Publica os dados nas saídas da CPU e
                // gera o pulso start_lcd de 1 ciclo para atualizar o visor
                // -------------------------------------------------------------
                S_UPDATE_LCD: begin
                    op_realizada     <= dec_opcode;
                    reg_dest_out     <= dec_reg_dest;
                    resultado_16bits <= exec_result_reg;
                    start_lcd        <= 1'b1;
                    state            <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule