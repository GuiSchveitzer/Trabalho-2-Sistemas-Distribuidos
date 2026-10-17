# Evidências

Saídas geradas pelos scripts de `scripts/`. Cada execução de um script sobrescreve os seus arquivos.

## Evidências principais (citadas no relatório)

| Arquivo | Experimento |
|---|---|
| `e1_topologia.txt` | E1 – membros, líder, termo, índice, saúde e memória |
| `e2_caminho.txt` | E2 – put num seguidor e métricas de encaminhamento ao líder |
| `e3_replicacao.txt`, `e3_watch.log` | E3 – replicação, watch, latências, propagação e check perf |
| `e4_consistencia.txt` | E4 – leitura linearizável × serializável |
| `e5_falha_quorum.txt` | E5 – tempo de eleição, transferência de liderança e quadro de quórum |
| `e6_particao.txt` | E6 – líder isolado: os dois lados da partição e logs |
| `e7_recuperacao.txt` | E7 – recuperação por log e varredura partição × recuperação |
| `e7b_snapshot.txt` | E7 – recuperação por snapshot |
| `e8_coordenacao.txt` | E8 – termos × revisões, etcdctl lock e etcdctl elect |
| `e9_cenario0.txt` … `e9_cenario3.txt` | E9 – cenários da ênfase B |
| `e9_cenariorep.txt` | E9 – resumo das 5 repetições dos cenários 1 e 2 |

## Detalhe das repetições do E9

- `e9/rep_f0_r1.txt` … `rep_f0_r5.txt` – sem fencing, rodadas 1 a 5.
- `e9/rep_f1_r1.txt` … `rep_f1_r5.txt` – com fencing, rodadas 1 a 5.

Cada arquivo tem a linha do tempo dos dois workers e o histórico do recurso daquela rodada.

Os logs brutos de cada worker são só arquivos de trabalho: os scripts os gravam em uma pasta temporária
(`$TMPDIR/t5-etcd`) e todo o conteúdo deles já aparece nas evidências acima.
