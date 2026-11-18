// =============================================================================
// top_level.v  -  Integrante 5: integracao de todos os modulos na DE2-115
//
// Fluxo:  KEY/SW -> input_controller -> instruction_decoder -> module_mini_cpu
//         -> lcd_formatter -> lcd_controller -> LCD
//
// ATENCAO: os modulos dos Integrantes 1, 2 e 3 ainda nao foram vistos. Os NOMES DE
// PORTA abaixo seguem a divisao de tarefas (system_on, send_pulse, opcode, reg_dest,
// reg_src1, reg_src2, imm_16bits, op_realizada, reg_dest_out, resultado_16bits,
// start_lcd), mas os demais nomes (clk, rst_n, btn_*, sw, use_imm, is_special) sao
// SUPOSICOES. Ajuste as ligacoes marcadas com "<<< CONFIRMAR" ao contrato real.
//
// Botoes da DE2-115 sao ativos em baixo (apertado = 0). Mapeamento assumido:
//   KEY[1] = Botao Ligar,  KEY[0] = Botao Enviar  (trocar abaixo se o grupo preferir)
// =============================================================================
module top_level (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,          // KEY[1] = Ligar, KEY[0] = Enviar (ativos em baixo)
    input  wire [17:0] SW,

    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,
    output wire        LCD_BLON,

    output wire [1:0]  LEDG          // depuracao: [0] = sistema ligado, [1] = alterna a cada Enviar
);

    // ---------------------------------------------------------------- Reset de partida
    // Segura o reset por alguns ciclos logo apos a configuracao da FPGA.
    reg [3:0] por_cnt = 4'd0;
    wire      por_n   = &por_cnt;
    always @(posedge CLOCK_50)
        if (!por_n) por_cnt <= por_cnt + 4'd1;

   // ---------------------------------------------------------------- Fios entre modulos
    wire        system_on;
    wire [2:0]  op_realizada;
    wire [3:0]  reg_dest_out;
    wire [15:0] resultado_16bits;
    wire        start_lcd;

    wire [255:0] lcd_frame;
    wire         frame_ready;
    wire         fmt_busy;
    
    // (APAGADAS as instâncias u_input e u_decoder, pois já existem dentro de u_cpu)

    // ---------------------------------------------------------------- Integrantes 1, 2 e 3
    // module_mini_cpu já instancia input, decoder, memoria e ula internamente.
    module_mini_cpu u_cpu (
        .CLOCK_50         (CLOCK_50),
        .SW               (SW),
        .KEY              ({2'b11, KEY}), // Preenche os 2 bits faltantes com 1 (solto)
        .system_on        (system_on),
        .power_on_pulse   (),             // Deixado vazio, não é usado no top_level
        .power_off_pulse  (),             // Deixado vazio, não é usado no top_level
        .op_realizada     (op_realizada),
        .reg_dest_out     (reg_dest_out),
        .resultado_16bits (resultado_16bits),
        .start_lcd        (start_lcd)
    );
    // ---------------------------------------------------------------- Integrante 4
    // rst_n = system_on: desligado, o quadro volta ao estado inicial.
    lcd_formatter u_formatter (
        .clk              (CLOCK_50),
        .rst_n            (system_on),
        .start_lcd        (start_lcd),
        .op_realizada     (op_realizada),
        .reg_dest_out     (reg_dest_out),
        .resultado_16bits (resultado_16bits),
        .lcd_frame        (lcd_frame),
        .frame_ready      (frame_ready),
        .busy             (fmt_busy)
    );

    // ---------------------------------------------------------------- Integrante 5
    lcd_controller #(.CYC_US(50)) u_lcd (
        .clk         (CLOCK_50),
        .rst_n       (por_n),
        .system_on   (system_on),
        .frame_ready (frame_ready),
        .lcd_frame   (lcd_frame),
        .LCD_DATA    (LCD_DATA),
        .LCD_RS      (LCD_RS),
        .LCD_RW      (LCD_RW),
        .LCD_EN      (LCD_EN),
        .LCD_ON      (LCD_ON),
        .LCD_BLON    (LCD_BLON)
    );

    // ---------------------------------------------------------------- LEDs de depuracao
    assign LEDG[0] = system_on;
    assign LEDG[1] = 1'b0; // O LED de send_pulse foi desativado pois o sinal é interno à CPU

endmodule
