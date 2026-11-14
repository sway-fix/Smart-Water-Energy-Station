package br.fiap.estacao;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api")
@CrossOrigin
public class EstacaoController {
    private final LeituraRepository leituras;
    private final FalhaRepository falhas;
    private final AtuadorRepository atuadores;

    public EstacaoController(LeituraRepository l, FalhaRepository f, AtuadorRepository a) {
        this.leituras = l; this.falhas = f; this.atuadores = a;
    }

    private static final Duration INTERVALO_ALERTAS = Duration.ofSeconds(15);

    /**
     * Registra uma leitura. Se houver anomalia, gera NO MAXIMO 1 alerta a cada 15 s
     * (se varias anomalias ocorrerem juntas, escolhe a que ha mais tempo nao aparece).
     */
    @PostMapping("/leituras")
    public Leitura registrar(@RequestBody Leitura l) {
        l.id = null;
        Leitura salva = leituras.save(l);

        List<Falha> candidatas = new ArrayList<>();
        if (salva.nivel < 20)
            candidatas.add(new Falha("NIVEL_BAIXO", "Nivel critico: " + salva.nivel + "%", salva.id));
        if (salva.nivel > 95)
            candidatas.add(new Falha("NIVEL_ALTO", "Risco de transbordo: " + salva.nivel + "%", salva.id));
        if (salva.consumoKw > 3.3)
            candidatas.add(new Falha("SOBRECONSUMO", "Consumo acima do limite: " + salva.consumoKw + " kW", salva.id));
        if (salva.vazao < 1.0)
            candidatas.add(new Falha("VAZAO_BAIXA", "Vazao quase nula: " + salva.vazao + " L/min", salva.id));
        if (candidatas.isEmpty()) return salva;

        Falha ultima = falhas.findFirstByOrderByIdDesc();
        if (ultima != null && Duration.between(ultima.dataHora, LocalDateTime.now()).compareTo(INTERVALO_ALERTAS) < 0)
            return salva; // ainda dentro dos 15 s do ultimo alerta

        Falha escolhida = candidatas.stream()
                .min(Comparator.<Falha, LocalDateTime>comparing(c -> {
                    Falha u = falhas.findFirstByTipoOrderByIdDesc(c.tipo);
                    return u == null ? LocalDateTime.MIN : u.dataHora;
                }))
                .get();
        falhas.save(escolhida);
        return salva;
    }

    @GetMapping("/leituras")
    public List<Leitura> listar() { return leituras.findTop50ByOrderByIdDesc(); }

    @GetMapping("/leituras/ultima")
    public ResponseEntity<Leitura> ultima() {
        Leitura l = leituras.findFirstByOrderByIdDesc();
        return l == null ? ResponseEntity.noContent().build() : ResponseEntity.ok(l);
    }

    /** Liga/desliga um atuador (BOMBA, VALVULA...). Body: {"nome":"BOMBA","ligado":true} */
    @PostMapping("/atuadores")
    public Atuador acionar(@RequestBody Atuador a) {
        a.atualizadoEm = LocalDateTime.now();
        return atuadores.save(a);
    }

    @GetMapping("/atuadores")
    public List<Atuador> estadoAtuadores() { return atuadores.findAll(); }

    /** Ultimas 50 falhas, da mais recente para a mais antiga. */
    @GetMapping("/falhas")
    public List<Falha> listarFalhas() { return falhas.findTop50ByOrderByIdDesc(); }

    /** Apaga o historico de alertas. */
    @DeleteMapping("/falhas")
    public void limparFalhas() { falhas.deleteAll(); }
}
