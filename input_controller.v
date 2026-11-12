module input_controller #(
    parameter DEBOUNCE_MAX = 20'd1_000_000 // 20ms em clock de 50MHz
)(
    input  wire clk,             // CLOCK_50 da placa DE2-115
    input  wire key_ligar_raw,   // KEY[0] físico (ativo em nível baixo: 0=apertado, 1=solto)
    input  wire key_enviar_raw,  // KEY[1] físico (ativo em nível baixo: 0=apertado, 1=solto)
    
    output reg  system_on,       // 0 = Sistema Desligado, 1 = Sistema Ligado
    output wire send_pulse,      // Pulso de 1 ciclo ao soltar Enviar (apenas se system_on == 1)
    output wire power_on_pulse,  // Pulso de 1 ciclo no instante em que o sistema liga (avisa LCD)
    output wire power_off_pulse, // Pulso de 1 ciclo no instante em que o sistema desliga (avisa LCD)
    output wire mem_reset_base   // 1 quando desligado ou reiniciando (zera os 16 registradores)
);

    // =========================================================================
    // 1. SINCRONIZADORES DE 2 ESTÁGIOS (Evita falhas elétricas/metaestabilidade)
    // =========================================================================
    // Inicializados em 1 porque os botões KEY da DE2-115 ficam em '1' quando soltos
    reg key0_meta = 1'b1, key0_in = 1'b1;
    reg key1_meta = 1'b1, key1_in = 1'b1;

    always @(posedge clk) begin
        key0_meta <= key_ligar_raw;
        key0_in   <= key0_meta;

        key1_meta <= key_enviar_raw;
        key1_in   <= key1_meta;
    end

    // =========================================================================
    // 2. FILTRO DE DEBOUNCE (~20 ms)
    // =========================================================================
    reg [19:0] cnt0 = 20'd0;
    reg [19:0] cnt1 = 20'd0;
    reg key0_stable = 1'b1, key0_prev = 1'b1;
    reg key1_stable = 1'b1, key1_prev = 1'b1;

    always @(posedge clk) begin
        // Debounce do Botão Ligar (KEY[0])
        if (key0_in == key0_stable) begin
            cnt0 <= 20'd0;
        end else begin
            if (cnt0 == DEBOUNCE_MAX - 20'd1) begin
                key0_stable <= key0_in;
                cnt0        <= 20'd0;
            end else begin
                cnt0 <= cnt0 + 20'd1;
            end
        end
        key0_prev <= key0_stable;

        // Debounce do Botão Enviar (KEY[1])
        if (key1_in == key1_stable) begin
            cnt1 <= 20'd0;
        end else begin
            if (cnt1 == DEBOUNCE_MAX - 20'd1) begin
                key1_stable <= key1_in;
                cnt1        <= 20'd0;
            end else begin
                cnt1 <= cnt1 + 20'd1;
            end
        end
        key1_prev <= key1_stable;
    end

    // =========================================================================
    // 3. DETECÇÃO DE SOLTURA (Borda de subida 0 -> 1) E ESTADO GLOBAL
    // =========================================================================
    wire ligar_released  = (~key0_prev) & key0_stable;
    wire enviar_released = (~key1_prev) & key1_stable;

    // Sistema inicia sempre DESLIGADO (0) ao gravar na placa
    initial begin
        system_on = 1'b0;
    end

    always @(posedge clk) begin
        if (ligar_released) begin
            system_on <= ~system_on;
        end
    end

    // =========================================================================
    // 4. SAÍDAS DE CONTROLE PARA A CPU, MEMÓRIA E LCD
    // =========================================================================
    // Bloqueia o envio se o sistema estiver desligado ou desligando neste ciclo
    assign send_pulse      = system_on && (!ligar_released) && enviar_released;

    // Pulsos auxiliares de 1 ciclo para facilitar o trabalho do LCD (Integrante 5)
    assign power_on_pulse  = ligar_released && (!system_on);
    assign power_off_pulse = ligar_released && system_on;

    // Mantém a RAM zerada enquanto desligado e no momento em que liga/desliga
    assign mem_reset_base  = (!system_on) || ligar_released;

endmodule