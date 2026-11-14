# Smart Water & Energy Station

Global Solution 2026/2 - Engenharia Mecatronica (2EMR)
Disciplinas: Advanced Programming & Mobile DEV / Tecnicas Avancadas de Programacao

Painel de operacao (app Flutter) + API REST (Spring Boot + H2) da estacao: niveis, vazao,
consumo eletrico simulado, acionamento de atuadores e alertas de falha.

## Integrantes
| Nome completo | RM |
|---|---|
| Pedro de Castro Figueiredo | 561825 |
| Nicolas Cipriano | 562278 |
| Gustavo Henrique | 563874 |

## Estrutura
- `backend/` - Spring Boot 3 (Java 17) + H2 em arquivo
- `mobile/` - app Flutter

## Como executar o backend
Requisitos: Java 17+ e Maven.
```bash
cd backend
mvn spring-boot:run
```
API em `http://localhost:8080`. Banco: `jdbc:h2:file:./data/estacao` (usuario `sa`, senha vazia),
console em `http://localhost:8080/h2-console`.

### Comprovando a persistencia
1. Com o backend rodando, envie uma leitura (ver exemplos abaixo) e confira com `GET /api/leituras`.
2. Pare o backend (Ctrl+C) e rode `mvn spring-boot:run` de novo.
3. `GET /api/leituras` ainda retorna os dados, gravados em `backend/data/estacao.mv.db`.

## Endpoints
| Metodo | Rota | Descricao |
|---|---|---|
| POST | `/api/leituras` | Registra leitura `{"nivel":60,"vazao":12.5,"consumoKw":2.1}`. Gera falha automatica se nivel < 20 ou > 95, consumo > 3,3 kW ou vazao < 1 L/min (no maximo 1 alerta a cada 15 s) |
| GET | `/api/leituras` | Ultimas 50 leituras |
| GET | `/api/leituras/ultima` | Leitura mais recente (204 se vazio) |
| POST | `/api/atuadores` | Aciona atuador `{"nome":"BOMBA","ligado":true}` |
| GET | `/api/atuadores` | Estado atual dos atuadores |
| GET | `/api/falhas` | Ultimas 50 falhas, da mais recente para a mais antiga |
| DELETE | `/api/falhas` | Apaga o historico de alertas |

Exemplos:
```bash
curl -X POST localhost:8080/api/leituras -H "Content-Type: application/json" -d '{"nivel":15,"vazao":0.5,"consumoKw":4.5}'
curl -X POST localhost:8080/api/atuadores -H "Content-Type: application/json" -d '{"nome":"BOMBA","ligado":true}'
curl localhost:8080/api/falhas
```

## Como executar o app
Requisitos: Flutter SDK 3.3+.
```bash
cd mobile
flutter create .        # gera as pastas android/ios (so na primeira vez)
flutter pub get
flutter run
```
- No PC (navegador): `flutter run -d chrome` (abre em localhost, com o backend rodando em `localhost:8080`).
- No PC (janela): `flutter run -d windows` (ou `macos` / `linux`).
- Emulador Android: ja funciona (`10.0.2.2`).
- Celular fisico: troque `baseUrl` em `mobile/lib/main.dart` pelo IP do PC (mesma rede Wi-Fi).

## Como o app funciona
O app simula a estacao: a cada 5 s calcula uma leitura (nivel, vazao e consumo) e envia ao backend,
depois atualiza as telas (Painel, Atuadores, Alertas e detalhe da falha). Se a API cair, aparece a faixa
"API fora do ar" e o app continua funcionando, voltando sozinho quando a API volta.

### Atuadores e simulacao (reservatorio de 500 L)
- **Bomba:** distribui agua do reservatorio para a rede (demanda variavel, com picos).
- **Valvula:** admite agua e regula a abertura sozinha para repor o que a bomba retira,
  mantendo o nivel em ~60%.
- **Modo manual:** valvula aberta por completo, sem regulagem (permite encher e transbordar).

| Bomba | Valvula | Resultado |
|---|---|---|
| Ligada | Ligada | Nivel estavel em ~60% |
| Ligada | Desligada | Nivel desce ate o critico |
| Desligada | Ligada | Enche ate ~60% e mantem |
| Desligada | Desligada | Nivel parado, vazao zero |
| Qualquer | Ligada + Modo manual | Nivel sobe ate o transbordo |

### Faixas de nivel (Painel e aba Alertas)
| Nivel | Estado | Cor |
|---|---|---|
| < 20% | Nivel critico | Vermelho |
| 20% a 50% | Nivel medio | Amarelo |
| 50% a 80% | Nivel normal | Verde |
| 80% a 95% | Atencao: quase cheio | Amarelo |
| > 95% | Risco de transbordo | Vermelho |

### Alertas
Gerados pelo backend a cada leitura, no maximo 1 a cada 15 s: nivel critico (< 20%), nivel alto (> 95%),
sobreconsumo (> 3,3 kW) e vazao baixa (< 1 L/min). Os dados de consumo e vazao sao simulados.
