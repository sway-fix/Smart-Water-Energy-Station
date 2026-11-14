import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Android (emulador): 10.0.2.2 | Web/Windows/Mac/Linux: localhost
// Celular fisico: troque pelo IP do PC na rede (ex: http://192.168.0.10:8080/api)
String get baseUrl =>
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? 'http://10.0.2.2:8080/api'
        : 'http://localhost:8080/api';

void main() => runApp(const EstacaoApp());

class EstacaoApp extends StatelessWidget {
  const EstacaoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Smart Water & Energy Station',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0F6E56),
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF1B2B31),
        ),
        home: const Home(),
      );
}

/// Camada de acesso a API (consumo de dados) com timeout.
class Api {
  static const _t = Duration(seconds: 4);
  static Future<dynamic> get(String p) async {
    final r = await http.get(Uri.parse('$baseUrl$p')).timeout(_t);
    if (r.statusCode == 204 || r.body.isEmpty) return null;
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static Future<void> post(String p, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$baseUrl$p'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(_t);
    if (r.statusCode >= 400) throw Exception('HTTP ${r.statusCode}');
  }
}

const kDark = Color(0xFF0B3C49);
const kTeal = Color(0xFF0F6E56);

String hora(dynamic iso) {
  final t = '$iso';
  return t.length >= 19 ? t.substring(11, 19) : t;
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _aba = 0;
  Map<String, dynamic>? ultima;
  List<dynamic> falhas = [], atuadores = [];
  bool offline = false, carregando = true;
  Timer? _timer;
  final _rnd = Random();
  double _nivel = 60;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _t = 0;
  double _abertura = 0, _qBomba = 0;

  bool _ligado(List<dynamic> l, String nome) =>
      l.any((x) => x['nome'] == nome && x['ligado'] == true);

  /// Simulacao do reservatorio (500 L). Cada leitura = 1 minuto simulado.
  /// - BOMBA (distribuicao): tira agua do reservatorio e manda para a rede (demanda variavel).
  /// - VALVULA (controle): admite agua na entrada e regula a abertura para repor o que a
  ///   bomba retira e levar/manter o nivel em 60%.
  /// Juntas: nivel estavel. So bomba: esvazia. So valvula: enche ate 60% e segura.
  Future<void> _tick() async {
    try {
      var a = await Api.get('/atuadores');
      if (a == null || a.isEmpty) {
        // primeira execucao: comeca com os dois ligados
        await Api.post('/atuadores', {'nome': 'BOMBA', 'ligado': true});
        await Api.post('/atuadores', {'nome': 'VALVULA', 'ligado': true});
        a = await Api.get('/atuadores');
      }
      final bomba = _ligado(a, 'BOMBA'), valvula = _ligado(a, 'VALVULA');
      final manual = _ligado(a, 'MODO_MANUAL'); // valvula aberta sem regulagem
      double r(double x) => (_rnd.nextDouble() * 2 - 1) * x; // ruido
      const volume = 500.0, setpoint = 60.0, qMax = 25.0, kp = 1.0;
      _t++;

      // demanda da rede (L/min): varia ao longo do tempo e tem picos ocasionais
      var demanda = 15 + 4 * sin(_t / 8) + r(2);
      if (_rnd.nextDouble() < 0.06) demanda *= 1.7;

      final qOut = bomba ? demanda : 0.0; // saida (bomba)
      double qIn = 0.0; // entrada (valvula de controle)
      if (valvula) {
        qIn = manual
            ? qMax // manual: abertura total, sem controle (pode transbordar)
            : (qOut + kp * (setpoint - _nivel)).clamp(0.0, qMax).toDouble();
      }
      _abertura = qIn / qMax * 100;
      _qBomba = qOut;

      _nivel = (_nivel + (qIn - qOut) / volume * 100).clamp(1.0, 100.0).toDouble();
      final vazao = bomba ? qOut : qIn;
      final kw = 0.3 +
          (bomba ? 0.8 + 0.1 * qOut : 0) +
          (valvula ? 0.1 + 0.02 * qIn : 0) +
          r(0.05);

      await Api.post('/leituras', {
        'nivel': double.parse(_nivel.toStringAsFixed(1)),
        'vazao': double.parse(max(0.0, vazao).toStringAsFixed(1)),
        'consumoKw': double.parse(kw.toStringAsFixed(2)),
      });
      final u = await Api.get('/leituras/ultima');
      final f = await Api.get('/falhas');
      if (!mounted) return;
      setState(() {
        ultima = u;
        falhas = f ?? [];
        atuadores = a ?? [];
        offline = false;
        carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        offline = true; // nao trava: so mostra o aviso
        carregando = false;
      });
    }
  }

  String _status(String n) {
    if (n == 'MODO_MANUAL') {
      return _estado(n)
          ? 'Ativo • válvula aberta, sem regulagem'
          : 'Desativado • válvula regulando sozinha';
    }
    if (!_estado(n)) return 'Desligada';
    if (n == 'BOMBA') return 'Ligada • ${_qBomba.toStringAsFixed(1)} L/min';
    return _estado('MODO_MANUAL')
        ? 'Aberta • sem regulagem'
        : 'Regulando • abertura ${_abertura.toStringAsFixed(0)}%';
  }

  Future<void> _acionar(String nome, bool ligado) async {
    try {
      await Api.post('/atuadores', {'nome': nome, 'ligado': ligado});
      await _tick();
    } catch (_) {
      if (mounted) setState(() => offline = true);
    }
  }

  bool _estado(String nome) =>
      atuadores.any((a) => a['nome'] == nome && a['ligado'] == true);

  @override
  Widget build(BuildContext context) {
    final telas = [_painel(), _atuadores(), _alertas()];
    return Scaffold(
      body: Column(children: [
        _header(),
        if (offline)
          Container(
            width: double.infinity,
            color: Colors.red.shade700,
            padding: const EdgeInsets.all(8),
            child: const Text('API fora do ar - tentando reconectar...',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          ),
        Expanded(
            child: carregando
                ? const Center(child: CircularProgressIndicator())
                : telas[_aba]),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        backgroundColor: const Color(0xFF16252B),
        indicatorColor: const Color(0xFF2F5A52),
        onDestinationSelected: (i) => setState(() => _aba = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'Painel'),
          const NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Atuadores'),
          NavigationDestination(
              icon: Badge(
                  isLabelVisible: falhas.isNotEmpty,
                  label: Text(falhas.length >= 50 ? '50+' : '${falhas.length}'),
                  child: const Icon(Icons.notifications_rounded)),
              label: 'Alertas'),
        ],
      ),
    );
  }

  Widget _header() => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [kDark, kTeal], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Row(children: [
          const Icon(Icons.water_drop_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Smart Water & Energy',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              Text('Estação 01', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: offline ? Colors.redAccent : Colors.greenAccent),
              const SizedBox(width: 6),
              Text(offline ? 'Offline' : 'Online',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ]),
      );

  BoxDecoration get _card => BoxDecoration(
        color: const Color(0xFF263B43),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      );

  Widget _painel() {
    if (ultima == null) {
      return const Center(child: Text('Sem leituras ainda.'));
    }
    final nivel = (ultima!['nivel'] as num).toDouble();
    final est = estadoNivel(nivel);
    final cor = est.cor;
    final msg = est.texto;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: _card,
        child: Column(children: [
          SizedBox(
            width: 170,
            height: 170,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 170,
                height: 170,
                child: CircularProgressIndicator(
                    value: nivel / 100,
                    strokeWidth: 14,
                    color: cor,
                    backgroundColor: Colors.white12),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${nivel.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                const Text('reservatório', style: TextStyle(color: Colors.white70)),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
                color: cor.withAlpha(45), borderRadius: BorderRadius.circular(20)),
            child: Text(msg,
                style: TextStyle(color: cor.shade200, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: _metrica(Icons.waves_rounded, 'Vazão', '${ultima!['vazao']}', 'L/min',
                Colors.blue)),
        const SizedBox(width: 14),
        Expanded(
            child: _metrica(Icons.bolt_rounded, 'Consumo', '${ultima!['consumoKw']}', 'kW',
                Colors.amber.shade800)),
      ]),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: _card,
        child: Row(children: [
          const Icon(Icons.schedule_rounded, color: Colors.white60),
          const SizedBox(width: 10),
          const Text('Última leitura', style: TextStyle(color: Colors.white70)),
          const Spacer(),
          Text(hora(ultima!['dataHora']), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 6),
      const Center(
          child: Text('Consumo elétrico simulado',
              style: TextStyle(fontSize: 12, color: Colors.white54))),
    ]);
  }

  Widget _metrica(IconData i, String t, String v, String u, Color c) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(backgroundColor: c.withAlpha(40), child: Icon(i, color: c)),
          const SizedBox(height: 12),
          Text(t, style: const TextStyle(color: Colors.white70)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(u, style: const TextStyle(color: Colors.white70))),
          ]),
        ]),
      );

  Widget _atuadores() => ListView(padding: const EdgeInsets.all(16), children: [
        for (final n in ['BOMBA', 'VALVULA', 'MODO_MANUAL'])
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: _card.copyWith(
                color: _estado(n) ? const Color(0xFF1F4A3E) : const Color(0xFF263B43)),
            child: Row(children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: _estado(n) ? Colors.green : Colors.grey.shade700,
                child: Icon(
                    n == 'BOMBA'
                        ? Icons.water_rounded
                        : n == 'VALVULA'
                            ? Icons.settings_input_component_rounded
                            : Icons.pan_tool_rounded,
                    color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n == 'BOMBA' ? 'Bomba' : n == 'VALVULA' ? 'Válvula' : 'Modo manual',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(_status(n),
                      style: TextStyle(color: _estado(n) ? Colors.green.shade200 : Colors.white70)),
                ]),
              ),
              Switch(value: _estado(n), onChanged: offline ? null : (v) => _acionar(n, v)),
            ]),
          ),
      ]);

  Widget _alertas() {
    final nivel = (ultima?['nivel'] as num?)?.toDouble();
    return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: falhas.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) return _statusNivel(nivel);
          final f = falhas[i - 1];
          final c = corFalha('${f['tipo']}');
          return GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetalheFalha(falha: f))),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: _card,
              child: Row(children: [
                CircleAvatar(
                    backgroundColor: c.withAlpha(40),
                    child: Icon(iconeFalha('${f['tipo']}'), color: c)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f['tipo']}'.replaceAll('_', ' '),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${f['descricao']}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                Text(hora(f['dataHora']),
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
          );
        });
  }

  /// Situacao atual do reservatorio: verde (normal), amarelo (atencao), vermelho (critico).
  Widget _statusNivel(double? nivel) {
    if (nivel == null) return const SizedBox.shrink();
    final est = estadoNivel(nivel);
    final c = est.cor, ic = est.icone, t = est.texto;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: _card.copyWith(border: Border.all(color: c.withAlpha(120))),
      child: Row(children: [
        CircleAvatar(backgroundColor: c.withAlpha(40), child: Icon(ic, color: c)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Reservatório em ${nivel.toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        Text('${nivel.toStringAsFixed(1)}%',
            style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

/// Faixas do reservatorio (usadas no Painel e na aba Alertas):
/// <20 critico | 20-50 medio | 50-80 normal | 80-95 quase cheio | >95 transbordo
class EstadoNivel {
  final MaterialColor cor;
  final IconData icone;
  final String texto;
  const EstadoNivel(this.cor, this.icone, this.texto);
}

EstadoNivel estadoNivel(double n) {
  if (n < 20) return const EstadoNivel(Colors.red, Icons.error_rounded, 'Nível crítico');
  if (n < 50) return const EstadoNivel(Colors.amber, Icons.info_rounded, 'Nível médio');
  if (n <= 80) {
    return const EstadoNivel(Colors.green, Icons.check_circle_rounded, 'Nível normal');
  }
  if (n <= 95) {
    return const EstadoNivel(
        Colors.amber, Icons.warning_amber_rounded, 'Atenção: quase cheio');
  }
  return const EstadoNivel(Colors.red, Icons.error_rounded, 'Risco de transbordo');
}

Color corFalha(String tipo) {
  switch (tipo) {
    case 'NIVEL_BAIXO':
    case 'NIVEL_ALTO':
      return Colors.red; // critico
    case 'SOBRECONSUMO':
      return Colors.amber; // eletricidade
    default:
      return Colors.blue; // VAZAO_BAIXA
  }
}

IconData iconeFalha(String tipo) {
  switch (tipo) {
    case 'SOBRECONSUMO':
      return Icons.bolt_rounded;
    case 'VAZAO_BAIXA':
      return Icons.waves_rounded;
    default:
      return Icons.warning_rounded;
  }
}

class DetalheFalha extends StatelessWidget {
  final Map<String, dynamic> falha;
  const DetalheFalha({super.key, required this.falha});
  @override
  Widget build(BuildContext context) {
    final c = corFalha('${falha['tipo']}');
    return Scaffold(
      appBar: AppBar(title: Text('Falha #${falha['id']}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 32,
              backgroundColor: c.withAlpha(40),
              child: Icon(iconeFalha('${falha['tipo']}'), color: c, size: 34)),
          const SizedBox(height: 16),
          Text('${falha['tipo']}'.replaceAll('_', ' '),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text('${falha['descricao']}', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          Text('Data/hora: ${falha['dataHora']}'),
          Text('Leitura associada: #${falha['leituraId']}'),
        ]),
      ),
    );
  }
}
