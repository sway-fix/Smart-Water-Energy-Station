package br.fiap.estacao;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
public class Atuador {
    @Id
    public String nome;   // ex: BOMBA, VALVULA
    public boolean ligado;
    public LocalDateTime atualizadoEm = LocalDateTime.now();
}
