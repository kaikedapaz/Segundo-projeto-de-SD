module module_mini_cpu (
    input  wire               CLOCK_50,
    input  wire [17:0]        SW,
    input  wire [3:0]         KEY,

    output wire               system_on,
    output wire               power_on_pulse,
    output wire               power_off_pulse,
    output reg  [2:0]         op_realizada,
    output reg  [3:0]         reg_dest_out,
    output reg  signed [15:0] resultado_16bits,
    output reg                start_lcd
);

    // Fios de interconexão
    wire        send_pulse;
    wire        mem_reset_base;
    wire [2:0]  dec_opcode;
    wire [3:0]  dec_reg_dest;
    wire [3:0]  dec_reg_src1;
    wire [3:0]  dec_reg_src2;
    wire [15:0] dec_imm_16bits;
    wire        dec_use_imm;
    wire        dec_is_special;
    wire        dec_valid_instr;

    wire        mem_reset;
    reg         mem_we;
    wire [15:0] mem_read_data1;
    wire [15:0] mem_read_data2;
    reg  [15:0] mem_write_data;

    wire signed [15:0] ula_operand_a;
    wire signed [15:0] ula_operand_b;
    wire signed [15:0] ula_result;

    // Instanciação dos módulos externos
    input_controller u_input_ctrl (
        .clk             (CLOCK_50),
        .key_ligar_raw   (KEY[0]),
        .key_enviar_raw  (KEY[1]),
        .system_on       (system_on),
        .send_pulse      (send_pulse),
        .power_on_pulse  (power_on_pulse),
        .power_off_pulse (power_off_pulse),
        .mem_reset_base  (mem_reset_base)
    );

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

    reg fsm_clear_mem;
    assign mem_reset = mem_reset_base || fsm_clear_mem;

    memoria u_memoria (
        .clk        (CLOCK_50),
        .reset      (mem_reset),
        .we         (mem_we),
        .read_addr1 (dec_reg_src1),
        .read_addr2 (dec_reg_src2),
        .write_addr (dec_reg_dest),
        .write_data (mem_write_data),
        .read_data1 (mem_read_data1),
        .read_data2 (mem_read_data2)
    );

    assign ula_operand_a = mem_read_data1;
    assign ula_operand_b = dec_use_imm ? dec_imm_16bits : mem_read_data2;

    ula u_ula (
        .opcode    (dec_opcode),
        .operand_a (ula_operand_a),
        .operand_b (ula_operand_b),
        .result    (ula_result)
    );

    // =========================================================================
    // UNIDADE DE CONTROLE PRINCIPAL (FSM)
    // =========================================================================
    localparam S_IDLE       = 3'd0;
    localparam S_READ       = 3'd1;
    localparam S_EXECUTE    = 3'd2;
    localparam S_WRITEBACK  = 3'd3;
    localparam S_UPDATE_LCD = 3'd4;

    localparam OP_CLEAR     = 3'b110;
    localparam OP_DISPLAY   = 3'b111;

    reg [2:0]         state;
    reg signed [15:0] exec_result_reg;

    always @(posedge CLOCK_50) begin
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
            // Reseta sinais de controle por padrão para garantir pulsos de 1 ciclo
            mem_we        <= 1'b0;
            fsm_clear_mem <= 1'b0;
            start_lcd     <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (dec_valid_instr) begin
                        state <= S_READ;
                    end
                end

                S_READ: begin
                    state <= S_EXECUTE;
                end

                S_EXECUTE: begin
                    if (dec_opcode == OP_DISPLAY) begin
                        exec_result_reg <= mem_read_data1;
                    end else if (dec_opcode == OP_CLEAR) begin
                        exec_result_reg <= 16'd0;
                    end else begin
                        exec_result_reg <= ula_result;
                    end
                    state <= S_WRITEBACK;
                end

                S_WRITEBACK: begin
                    if (dec_opcode == OP_CLEAR) begin
                        fsm_clear_mem <= 1'b1;
                    end else if (dec_opcode != OP_DISPLAY) begin
                        mem_write_data <= exec_result_reg;
                        mem_we         <= 1'b1;
                    end
                    state <= S_UPDATE_LCD;
                end

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