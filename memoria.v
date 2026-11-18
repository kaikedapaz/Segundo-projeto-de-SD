module memoria (
    input  wire        clk,
    input  wire        reset,      // Sinal de reset para zerar a memória ao ligar/desligar
    input  wire        we,         // Write enable
    input  wire [3:0]  read_addr1, // Endereço do Registrador Fonte 1 (Src1)
    input  wire [3:0]  read_addr2, // Endereço do Registrador Fonte 2 (Src2)
    input  wire [3:0]  write_addr, // Endereço do Registrador Destino (Dest)
    input  wire [15:0] write_data, // Dados para gravar
    output wire [15:0] read_data1, // Dados do Src1 lidos
    output wire [15:0] read_data2  // Dados do Src2 lidos
);

    reg [15:0] ram [15:0];
    integer i;

    // Escrita e Reset Síncronos
    always @(posedge clk) begin
        if (reset) begin
            // Zera todos os 16 registradores ao reiniciar/ligar (Requisito do projeto)
            for (i = 0; i < 16; i = i + 1) begin
                ram[i] <= 16'h0000;
            end
        end else if (we) begin
            ram[write_addr] <= write_data;
        end
    end

    // Leitura Assíncrona para disponibilizar registradores para a ULA
    assign read_data1 = ram[read_addr1];
    assign read_data2 = ram[read_addr2];

endmodule
