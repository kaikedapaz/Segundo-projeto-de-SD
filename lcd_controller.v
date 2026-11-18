// =============================================================================
// lcd_controller.v  -  Integrante 5: driver fisico do LCD 16x2 (HD44780) da DE2-115
//
// O que faz:
//   * Sistema LIGA (system_on 0 -> 1): espera, executa a rotina de inicializacao
//     (modo 8 bits / 2 linhas, display off, limpar, modo de entrada, display on)
//     e escreve o quadro atual de lcd_frame (a tela "ociosa" do formatador).
//   * frame_ready = 1 (pulso) com o sistema ligado: escreve os 32 caracteres
//     (linha 1 a partir de DDRAM 0x00, linha 2 a partir de 0x40).
//   * Sistema DESLIGA (system_on 1 -> 0): limpa e apaga o display.
//   * Apos o reset (rst_n), limpa e apaga o display uma vez, para a tela comecar
//     vazia mesmo que o LCD guarde texto de um programa anterior.
//
// Temporizacao (clock de 50 MHz, CYC_US = 50 ciclos por microssegundo):
//   * RS/DATA estaveis 100 ns antes do EN subir.
//   * EN em nivel alto por 500 ns; o LCD captura na descida (1 -> 0).
//   * RS/DATA mantidos por 100 ns depois da descida.
//   * Espera apos cada comando/caractere: 1 ms (como recomenda a especificacao);
//     2 ms apos "limpar display" (o datasheet pede >= 1,52 ms).
//
// Formato de lcd_frame (o mesmo do lcd_formatter):
//   caractere k (0..31) = lcd_frame[255-8*k -: 8]; 0..15 = linha 1, 16..31 = linha 2.
//
// Se frame_ready chegar enquanto uma escrita esta em andamento, o quadro mais novo
// e guardado e escrito logo depois (nunca sai uma tela misturada).
// =============================================================================
module lcd_controller #(
    parameter CYC_US = 50          // ciclos de clock por microssegundo (50 MHz -> 50)
) (
    input  wire         clk,
    input  wire         rst_n,        // reset de hardware (ativo em baixo)
    input  wire         system_on,    // do input_controller (Integrante 1)
    input  wire         frame_ready,  // pulso do lcd_formatter (Integrante 4)
    input  wire [255:0] lcd_frame,    // 32 caracteres ASCII do lcd_formatter

    output reg  [7:0]   LCD_DATA,
    output reg          LCD_RS,
    output wire         LCD_RW,
    output reg          LCD_EN,
    output wire         LCD_ON,
    output wire         LCD_BLON
);

    assign LCD_RW   = 1'b0;   // so escrevemos no LCD
    assign LCD_ON   = 1'b1;   // alimenta o modulo LCD
    assign LCD_BLON = 1'b0;   // a DE2-115 nao tem backlight: nao usar

    // ---------------------------------------------------------------- Tempos
    localparam [20:0] D_PWR = 20000 * CYC_US;   // 20 ms apos ligar (datasheet pede >= 15 ms)
    localparam [20:0] D_5MS =  5000 * CYC_US;   //  5 ms (datasheet pede > 4,1 ms)
    localparam [20:0] D_CMD =  1000 * CYC_US;   //  1 ms por comando/caractere
    localparam [20:0] D_CLR =  2000 * CYC_US;   //  2 ms apos limpar (>= 1,52 ms)

    localparam integer T_SETUP = 5;    // 100 ns
    localparam integer T_HIGH  = 25;   // 500 ns
    localparam integer T_HOLD  = 5;    // 100 ns

    // ---------------------------------------------------------------- Motor de envio
    // Envia 1 byte (RS + 8 bits de dados) ao LCD e depois espera e_delay ciclos.
    // e_nop = 1: so espera (usado no atraso inicial depois de ligar).
    localparam [2:0] E_IDLE  = 3'd0;
    localparam [2:0] E_SETUP = 3'd1;
    localparam [2:0] E_HIGH  = 3'd2;
    localparam [2:0] E_HOLD  = 3'd3;
    localparam [2:0] E_WAIT  = 3'd4;

    reg  [2:0]  es;
    reg  [20:0] ecnt;
    reg  [20:0] edelay_q;
    reg         e_start;      // pedido de envio (pulso de 1 ciclo)
    reg         e_nop;
    reg         e_rs;
    reg  [7:0]  e_data;
    reg  [20:0] e_delay;
    reg         e_done;       // pulso de 1 ciclo: byte enviado e espera concluida

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            es       <= E_IDLE;
            ecnt     <= 21'd0;
            edelay_q <= 21'd0;
            LCD_EN   <= 1'b0;
            LCD_RS   <= 1'b0;
            LCD_DATA <= 8'h00;
            e_done   <= 1'b0;
        end else begin
            e_done <= 1'b0;
            case (es)
                E_IDLE: begin
                    if (e_start) begin
                        edelay_q <= e_delay;
                        ecnt     <= 21'd0;
                        if (e_nop) begin
                            es <= E_WAIT;
                        end else begin
                            LCD_RS   <= e_rs;
                            LCD_DATA <= e_data;
                            es       <= E_SETUP;
                        end
                    end
                end

                E_SETUP: begin                       // RS/DATA estaveis, EN = 0
                    ecnt <= ecnt + 21'd1;
                    if (ecnt == T_SETUP - 1) begin
                        LCD_EN <= 1'b1;              // EN sobe
                        ecnt   <= 21'd0;
                        es     <= E_HIGH;
                    end
                end

                E_HIGH: begin                        // EN = 1
                    ecnt <= ecnt + 21'd1;
                    if (ecnt == T_HIGH - 1) begin
                        LCD_EN <= 1'b0;              // EN desce (1 -> 0): o LCD captura
                        ecnt   <= 21'd0;
                        es     <= E_HOLD;
                    end
                end

                E_HOLD: begin                        // mantem RS/DATA apos a descida
                    ecnt <= ecnt + 21'd1;
                    if (ecnt == T_HOLD - 1) begin
                        ecnt <= 21'd0;
                        es   <= E_WAIT;
                    end
                end

                E_WAIT: begin                        // espera o LCD processar
                    ecnt <= ecnt + 21'd1;
                    if (ecnt == edelay_q - 1) begin
                        e_done <= 1'b1;
                        es     <= E_IDLE;
                    end
                end

                default: es <= E_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------- FSM principal
    localparam [2:0] ST_OFF   = 3'd0;   // desligado, display apagado
    localparam [2:0] ST_INIT  = 3'd1;   // rotina de inicializacao
    localparam [2:0] ST_ON    = 3'd2;   // ligado, esperando quadro novo
    localparam [2:0] ST_WRITE = 3'd3;   // escrevendo as duas linhas
    localparam [2:0] ST_SHUT  = 3'd4;   // rotina de desligamento

    reg [2:0]   st;
    reg [5:0]   step;
    reg         issued;       // 1 = comando enviado ao motor, esperando e_done
    reg         pending;      // chegou quadro novo ainda nao escrito
    reg [255:0] frame_new;    // ultimo quadro recebido (frame_ready)
    reg [255:0] frame_q;      // quadro sendo escrito (estavel durante a escrita)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_SHUT;      // apos o reset: limpa e apaga o display
            step      <= 6'd0;
            issued    <= 1'b0;
            pending   <= 1'b0;
            frame_new <= {32{8'h20}};
            frame_q   <= {32{8'h20}};
            e_start   <= 1'b0;
            e_nop     <= 1'b0;
            e_rs      <= 1'b0;
            e_data    <= 8'h00;
            e_delay   <= D_CMD;
        end else begin
            e_start <= 1'b0;

            // Guarda o quadro mais novo assim que o formatador avisa.
            if (frame_ready) begin
                frame_new <= lcd_frame;
                pending   <= 1'b1;
            end

            case (st)
                // ------------------------------------------------ desligado
                ST_OFF: begin
                    pending <= 1'b0;                 // ignora quadros com o sistema desligado
                    if (system_on) begin
                        st     <= ST_INIT;
                        step   <= 6'd0;
                        issued <= 1'b0;
                    end
                end

                // ------------------------------------------------ inicializacao
                ST_INIT: begin
                    if (!issued) begin
                        if (!system_on) begin        // desligou no meio: apaga tudo
                            st     <= ST_SHUT;
                            step   <= 6'd0;
                        end else begin
                            e_nop   <= 1'b0;
                            e_rs    <= 1'b0;
                            e_start <= 1'b1;
                            issued  <= 1'b1;
                            case (step)
                                6'd0: begin e_nop <= 1'b1; e_data <= 8'h00; e_delay <= D_PWR; end // espera inicial
                                6'd1: begin e_data <= 8'h30; e_delay <= D_5MS; end  // funcao (reset por software) 1
                                6'd2: begin e_data <= 8'h30; e_delay <= D_CMD; end  // funcao 2
                                6'd3: begin e_data <= 8'h30; e_delay <= D_CMD; end  // funcao 3
                                6'd4: begin e_data <= 8'h38; e_delay <= D_CMD; end  // 8 bits, 2 linhas, 5x8
                                6'd5: begin e_data <= 8'h08; e_delay <= D_CMD; end  // display desligado
                                6'd6: begin e_data <= 8'h01; e_delay <= D_CLR; end  // limpar display
                                6'd7: begin e_data <= 8'h06; e_delay <= D_CMD; end  // modo de entrada: cursor -> direita
                                default: begin e_data <= 8'h0C; e_delay <= D_CMD; end // display ligado, sem cursor
                            endcase
                        end
                    end else if (e_done) begin
                        issued <= 1'b0;
                        if (step == 6'd8) begin
                            frame_q <= lcd_frame;    // escreve o quadro atual (tela ociosa)
                            pending <= 1'b0;
                            st      <= ST_WRITE;
                            step    <= 6'd0;
                        end else begin
                            step <= step + 6'd1;
                        end
                    end
                end

                // ------------------------------------------------ ligado e ocioso
                ST_ON: begin
                    if (!system_on) begin
                        st     <= ST_SHUT;
                        step   <= 6'd0;
                        issued <= 1'b0;
                    end else if (pending) begin
                        // trava o quadro para a escrita; se um quadro ainda mais novo
                        // chegar neste mesmo ciclo, usa-se lcd_frame direto (nao se perde)
                        frame_q <= frame_ready ? lcd_frame : frame_new;
                        pending <= 1'b0;
                        st      <= ST_WRITE;
                        step    <= 6'd0;
                        issued  <= 1'b0;
                    end
                end

                // ------------------------------------------------ escrita da tela
                // step 0: endereco da linha 1 (0x80); 1..16: caracteres 0..15
                // step 17: endereco da linha 2 (0xC0); 18..33: caracteres 16..31
                ST_WRITE: begin
                    if (!issued) begin
                        if (!system_on) begin
                            st   <= ST_SHUT;
                            step <= 6'd0;
                        end else begin
                            e_nop   <= 1'b0;
                            e_delay <= D_CMD;
                            e_start <= 1'b1;
                            issued  <= 1'b1;
                            if (step == 6'd0) begin
                                e_rs <= 1'b0; e_data <= 8'h80;
                            end else if (step <= 6'd16) begin
                                e_rs <= 1'b1; e_data <= frame_q[255 - 8*(step - 1) -: 8];
                            end else if (step == 6'd17) begin
                                e_rs <= 1'b0; e_data <= 8'hC0;
                            end else begin
                                e_rs <= 1'b1; e_data <= frame_q[255 - 8*(step - 2) -: 8];
                            end
                        end
                    end else if (e_done) begin
                        issued <= 1'b0;
                        if (step == 6'd33) begin
                            st   <= ST_ON;
                            step <= 6'd0;
                        end else begin
                            step <= step + 6'd1;
                        end
                    end
                end

                // ------------------------------------------------ desligamento
                ST_SHUT: begin
                    if (!issued) begin
                        e_nop   <= 1'b0;
                        e_rs    <= 1'b0;
                        e_start <= 1'b1;
                        issued  <= 1'b1;
                        if (step == 6'd0) begin
                            e_data <= 8'h01; e_delay <= D_CLR;   // limpar display
                        end else begin
                            e_data <= 8'h08; e_delay <= D_CMD;   // display desligado
                        end
                    end else if (e_done) begin
                        issued <= 1'b0;
                        if (step == 6'd1) begin
                            st   <= ST_OFF;
                            step <= 6'd0;
                        end else begin
                            step <= step + 6'd1;
                        end
                    end
                end

                default: begin
                    st     <= ST_SHUT;
                    step   <= 6'd0;
                    issued <= 1'b0;
                end
            endcase
        end
    end

endmodule
