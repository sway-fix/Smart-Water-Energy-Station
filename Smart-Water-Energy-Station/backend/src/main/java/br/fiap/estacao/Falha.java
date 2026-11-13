package br.fiap.estacao;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
public class Falha {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    public Long id;
    public String tipo;
    public String descricao;
    public Long leituraId;
    public LocalDateTime dataHora = LocalDateTime.now();

    public Falha() {}
    public Falha(String tipo, String descricao, Long leituraId) {
        this.tipo = tipo; this.descricao = descricao; this.leituraId = leituraId;
    }
}
