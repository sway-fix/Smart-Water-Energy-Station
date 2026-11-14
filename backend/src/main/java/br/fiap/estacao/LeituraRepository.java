package br.fiap.estacao;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface LeituraRepository extends JpaRepository<Leitura, Long> {
    Leitura findFirstByOrderByIdDesc();
    List<Leitura> findTop50ByOrderByIdDesc();
}
