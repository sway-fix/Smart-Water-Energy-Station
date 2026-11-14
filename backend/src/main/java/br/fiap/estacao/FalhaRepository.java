package br.fiap.estacao;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface FalhaRepository extends JpaRepository<Falha, Long> {
    List<Falha> findTop50ByOrderByIdDesc();
    Falha findFirstByOrderByIdDesc();
    Falha findFirstByTipoOrderByIdDesc(String tipo);
}
