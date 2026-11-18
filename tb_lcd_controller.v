// =============================================================================
// tb_lcd_controller.v - testbench do lcd_controller com um modelo simples de LCD HD44780
//
// O modelo captura RS/DATA na DESCIDA de EN e confere:
//   * RS/DATA estaveis >= 60 ns antes de EN subir, RW = 0
//   * EN alto por >= 230 ns
//   * intervalo entre comandos >= 37 us (1,52 ms depois de "limpar display";
//     4,1 ms depois do 1o 0x30 da inicializacao)
//   * primeiro 0x30 da inicializacao >= 15 ms depois de system_on subir
// e reproduz o conteudo da DDRAM para comparar com as linhas esperadas.
//
// Usa temporizacao real (50 MHz): a simulacao cobre ~350 ms e pode levar alguns minutos.
// Resultado: "PASSOU" ou "FALHOU" no console.
// =============================================================================
`timescale 1ns/1ps

module tb_lcd_controller;

    reg          clk         = 1'b0;
    reg          rst_n       = 1'b0;
    reg          system_on   = 1'b0;
    reg          frame_ready = 1'b0;
    reg  [255:0] lcd_frame;

    wire [7:0] LCD_DATA;
    wire       LCD_RS, LCD_RW, LCD_EN, LCD_ON, LCD_BLON;

    integer errors = 0;

    lcd_controller #(.CYC_US(50)) dut (
        .clk(clk), .rst_n(rst_n), .system_on(system_on),
        .frame_ready(frame_ready), .lcd_frame(lcd_frame),
        .LCD_DATA(LCD_DATA), .LCD_RS(LCD_RS), .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN), .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON)
    );

    always #10 clk = ~clk;   // 50 MHz

    // ---------------------------------------------------------------- Modelo do LCD
    reg [7:0] ddram [0:127];
    reg [6:0] addr;
    reg       disp_on;
    reg       func_ok;
    reg       entry_ok;
    integer   n30;                 // quantos 0x30 ja chegaram na inicializacao
    integer   need_ns;             // tempo minimo ate o proximo comando
    time      t_en_rise, t_en_fall, t_data_change, t_sys_on;
    integer   i;

    initial begin
        for (i = 0; i < 128; i = i + 1) ddram[i] = 8'h20;
        addr = 0; disp_on = 0; func_ok = 0; entry_ok = 0;
        n30 = 0; need_ns = 0;
        t_en_rise = 0; t_en_fall = 0; t_data_change = 0; t_sys_on = 0;
    end

    always @(LCD_RS or LCD_DATA or LCD_RW) t_data_change = $time;

    always @(posedge LCD_EN) begin
        t_en_rise = $time;
        if ($time - t_data_change < 60) begin
            errors = errors + 1;
            $display("ERRO: setup de RS/DATA < 60 ns em %0t", $time);
        end
        if (LCD_RW !== 1'b0) begin
            errors = errors + 1;
            $display("ERRO: RW deveria ser 0");
        end
    end

    always @(negedge LCD_EN) begin
        if ($time - t_en_rise < 230) begin
            errors = errors + 1;
            $display("ERRO: pulso de EN < 230 ns em %0t", $time);
        end
        if (t_en_fall != 0 && ($time - t_en_fall) < need_ns) begin
            errors = errors + 1;
            $display("ERRO: comando muito cedo em %0t (esperava >= %0d ns)", $time, need_ns);
        end
        t_en_fall = $time;
        need_ns   = 37000;                                     // padrao: 37 us

        if (LCD_RS === 1'b0) begin                             // comando
            if (LCD_DATA === 8'h01) begin                      // limpar display
                for (i = 0; i < 128; i = i + 1) ddram[i] = 8'h20;
                addr = 0;
                need_ns = 1520000;
            end else if (LCD_DATA === 8'h30) begin             // funcao (inicializacao)
                if (n30 == 0) begin
                    if (t_sys_on != 0 && ($time - t_sys_on) < 15000000) begin
                        errors = errors + 1;
                        $display("ERRO: 1o 0x30 antes de 15 ms apos ligar");
                    end
                    need_ns = 4100000;
                end else begin
                    need_ns = 100000;
                end
                n30 = n30 + 1;
            end else if (LCD_DATA === 8'h38) begin             // 8 bits, 2 linhas
                func_ok = 1;
            end else if (LCD_DATA === 8'h06) begin             // modo de entrada, I/D = 1
                entry_ok = 1;
            end else if (LCD_DATA === 8'h08 || LCD_DATA === 8'h0C) begin
                disp_on = LCD_DATA[2];                         // bit D
            end else if (LCD_DATA[7] === 1'b1) begin           // endereco da DDRAM
                addr = LCD_DATA[6:0];
            end else begin
                errors = errors + 1;
                $display("ERRO: comando desconhecido %h", LCD_DATA);
            end
        end else begin                                         // escrita de caractere
            if (!func_ok) begin
                errors = errors + 1;
                $display("ERRO: caractere escrito antes do modo funcional");
            end
            ddram[addr] = LCD_DATA;
            addr = addr + 1;
        end
    end

    // ---------------------------------------------------------------- Auxiliares
    reg [127:0] got1, got2;
    task check_screen;
        input [127:0] exp1;
        input [127:0] exp2;
        input         exp_on;
        input [8*28-1:0] label;
        integer k;
        begin
            for (k = 0; k < 16; k = k + 1) begin
                got1[127 - 8*k -: 8] = ddram[k];
                got2[127 - 8*k -: 8] = ddram[64 + k];
            end
            if (got1 !== exp1 || got2 !== exp2 || disp_on !== exp_on) begin
                errors = errors + 1;
                $display("ERRO em %0s (display %0d, esperado %0d)", label, disp_on, exp_on);
                $display("  esperado: |%0s|", exp1);
                $display("            |%0s|", exp2);
                $display("  obtido  : |%0s|", got1);
                $display("            |%0s|", got2);
            end else begin
                $display("ok  %0s", label);
                $display("    |%0s|  display=%0d", got1, disp_on);
                $display("    |%0s|", got2);
            end
        end
    endtask

    task new_frame;                  // coloca um quadro novo e da o pulso frame_ready
        input [127:0] l1;
        input [127:0] l2;
        begin
            @(negedge clk);
            lcd_frame   = {l1, l2};
            frame_ready = 1'b1;
            @(negedge clk);
            frame_ready = 1'b0;
        end
    endtask

    localparam [127:0] IDLE1 = "          [    ]";
    localparam [127:0] IDLE2 = "          +00000";

    // ---------------------------------------------------------------- Sequencia de teste
    initial begin
        lcd_frame = {IDLE1, IDLE2};
        #100 rst_n = 1'b1;

        // 1) Depois do reset: tela vazia e apagada
        #6_000_000;
        check_screen("                ", "                ", 1'b0, "apos reset (apagada)");

        // 2) Liga: inicializa e escreve a tela inicial
        @(negedge clk); system_on = 1'b1; t_sys_on = $time; n30 = 0;
        #85_000_000;
        if (!func_ok || !entry_ok) begin
            errors = errors + 1;
            $display("ERRO: inicializacao incompleta (func=%0d entry=%0d)", func_ok, entry_ok);
        end
        check_screen(IDLE1, IDLE2, 1'b1, "ligado: tela inicial");

        // 3) Quadro novo
        new_frame("ADD       [0011]", "          +00015");
        #40_000_000;
        check_screen("ADD       [0011]", "          +00015", 1'b1, "ADD R3");

        // 4) Dois quadros durante uma escrita: o ultimo deve prevalecer, sem mistura
        new_frame("SUBI      [0100]", "          -00005");
        #10_000_000;                                      // meio da escrita
        new_frame("MUL       [0101]", "          -00015");
        #5_000_000;
        new_frame("DPL       [0011]", "          +00015"); // mais um, ainda durante a escrita
        #100_000_000;
        check_screen("DPL       [0011]", "          +00015", 1'b1, "ultimo quadro prevalece");

        // 5) CLEAR: so o nome
        new_frame("CLR             ", "                ");
        #40_000_000;
        check_screen("CLR             ", "                ", 1'b1, "CLEAR");

        // 6) Desliga: display apagado e limpo
        @(negedge clk); system_on = 1'b0;
        #10_000_000;
        check_screen("                ", "                ", 1'b0, "desligado");

        // 7) Quadro com o sistema desligado deve ser ignorado
        new_frame("ADD       [0001]", "          +00001");
        #10_000_000;
        check_screen("                ", "                ", 1'b0, "quadro ignorado desligado");

        // 8) Liga de novo (o formatador voltaria ao quadro inicial)
        lcd_frame = {IDLE1, IDLE2};
        @(negedge clk); system_on = 1'b1; t_sys_on = $time; n30 = 0;
        #85_000_000;
        check_screen(IDLE1, IDLE2, 1'b1, "religado: tela inicial");

        if (errors == 0) $display("PASSOU: todos os testes.");
        else             $display("FALHOU: %0d erro(s).", errors);
        $finish;
    end

endmodule
