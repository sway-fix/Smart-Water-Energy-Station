package br.fiap.estacao;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
public class Leitura {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    public Long id;
    public double nivel;      // % do reservatorio
    public double vazao;      // L/min
    public double consumoKw;  // kW (simulado)
    public LocalDateTime dataHora;

    @PrePersist
    void antes() { if (dataHora == null) dataHora = LocalDateTime.now(); }
}
