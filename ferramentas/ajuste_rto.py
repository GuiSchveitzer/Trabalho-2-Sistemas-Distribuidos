# E7 - Ajusta o RTO inicial do TCP aos tempos de recuperacao medidos.
# Hipotese: durante a particao a conexao TCP entre os pares continua aberta e o lider retransmite
# com backoff exponencial (RTO, 2*RTO, 4*RTO, ...). Ao religar a rede, o trafego so volta na
# proxima retransmissao, entao: espera = (proximo instante da agenda) - (duracao da particao).
# Le os pares (particao, medido) de evidencias/e7_recuperacao.txt.
# Uso: python ferramentas/ajuste_rto.py
import re
from pathlib import Path

texto = (Path(__file__).parent.parent / "evidencias" / "e7_recuperacao.txt").read_text(encoding="utf-8")
pontos = [(int(p), int(m)) for p, m in re.findall(r"por (\d+) ms, .*?recuperado em (\d+) ms", texto)]
pontos += [(int(p), int(m)) for p, m in re.findall(r"^\d+\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|", texto, re.M)]


def previsto(particao_ms, rto_s):
    # primeiro instante da agenda de retransmissoes depois do fim da particao
    t, r = 0.0, rto_s
    while True:
        t += r
        if t * 1000 > particao_ms:
            return t * 1000 - particao_ms
        r *= 2


def erro(rto_s):
    return sum(abs(previsto(p, rto_s) - m) for p, m in pontos) / len(pontos)


melhor = min((r / 1000 for r in range(180, 320)), key=erro)
print(f"{len(pontos)} medicoes; RTO inicial ajustado = {melhor * 1000:.0f} ms "
      f"(erro medio {erro(melhor):.0f} ms; com 200 ms o erro e {erro(0.2):.0f} ms)")
print(f"{'particao (ms)':>14} {'medido (ms)':>12} {'prev. 200 ms':>13} {'prev. ajustado':>15}")
for p, m in sorted(pontos):
    print(f"{p:>14} {m:>12} {previsto(p, 0.2):>13.0f} {previsto(p, melhor):>15.0f}")
