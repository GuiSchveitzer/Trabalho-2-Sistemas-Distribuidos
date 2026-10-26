# Trabalho 2 – T5: Replicação de estado com etcd (Raft) – Ênfase B

Sistemas Distribuídos – UNIVALI – 2º semestre de 2026

**Equipe:** _(preencher: nomes dos integrantes)_
**Tema:** T5 – Replicação de estado / configuração (etcd)
**Ênfase:** B – Travas, leases e fencing

## 1. Requisitos

- Docker (Docker Desktop com WSL 2 no Windows, Docker Engine no Linux) com Docker Compose v2
- Bash (no Windows: **Git Bash**)
- Cerca de 400 MB de RAM livres (cada contêiner tem um limite de memória declarado no compose)

Não é preciso ter Python nem `etcdctl` no computador: tudo roda dentro dos contêineres.

## 2. Topologia

| Contêiner | Papel | Rede interna (Raft :2380) | Rede clientes (API :2379) | Memória |
|---|---|---|---|---|
| etcd1 | membro etcd | 172.30.0.31 | 172.31.0.31 | 256 MB |
| etcd2 | membro etcd | 172.30.0.32 | 172.31.0.32 | 256 MB |
| etcd3 | membro etcd | 172.30.0.33 | 172.31.0.33 | 256 MB |
| cliente | Python + etcdctl, para as medições | – | 172.31.0.100 | 64 MB |
| recurso | recurso compartilhado da ênfase B (HTTP :8000) | – | 172.31.0.50 | 64 MB |
| worker1, worker2 | disputam a trava (ênfase B e E8) | – | 172.31.0.101 / .102 | 64 MB |

- Imagem dos membros: `quay.io/coreos/etcd:v3.5.17` (oficial).
- Imagem dos demais (`t5-cliente`): `python:3.12-alpine` com o `etcdctl` copiado da imagem oficial ([ferramentas/Dockerfile](ferramentas/Dockerfile)).
- Os MACs dos membros são fixos no compose. O Docker 29 sorteia um MAC novo a cada `start`, e os vizinhos ficavam com o ARP antigo em cache, o que deixava o membro reiniciado inacessível por vários segundos.

## 3. Como subir

```bash
docker compose up -d --build
bash scripts/e1_topologia.sh      # confere membros, líder, termo e saúde
```

Para recriar tudo do zero (apaga os dados do etcd): `docker compose down && docker compose up -d --build`.

## 4. Experimentos

Cada script imprime o resultado e salva a evidência em `evidencias/`. Rode a partir da raiz do repositório.

Para recriar o ambiente do zero e rodar **todos** os experimentos em sequência (~20 min):

```bash
bash scripts/executar_todos.sh
```

| Exp. | Script | O que faz |
|---|---|---|
| E1 | `scripts/e1_topologia.sh` | member list, endpoint status (líder, termo, índice), health, memória, endereços |
| E2 | `scripts/e2_caminho.sh` | put enviado a um **seguidor**; métricas de rede mostram o encaminhamento ao líder |
| E3 | `scripts/e3_replicacao.sh` | put num membro, get em outro, watch no terceiro; latência (5×); propagação (5×); `check perf` |
| E4 | `scripts/e4_consistencia.sh` | linearizável × serializável: latência (5×) e leitura num seguidor isolado |
| E5 | `scripts/e5_falha_quorum.sh` | queda do líder (tempo de eleição, 5×); `docker stop` × `docker kill`; quadro de quórum |
| E6 | `scripts/e6_particao.sh` | líder isolado da rede interna: lado majoritário × minoritário; logs de check quorum / pre-vote |
| E7 | `scripts/e7_recuperacao.sh` | membro isolado volta e alcança o líder pelo log (5×); varredura duração da partição × recuperação; hashkv igual nos 3. `python ferramentas/ajuste_rto.py` ajusta o modelo de backoff do TCP aos resultados |
| E7b | `scripts/e7b_snapshot.sh` | recuperação por **snapshot** (`--snapshot-count=1000`). **Recria o cluster.** |
| E8 | `scripts/e8_coordenacao.sh` | termos × revisões; `etcdctl lock` com tomada após queda (5×); `etcdctl elect` |
| E3/E8 | `scripts/e8b_medicoes_extras.sh` | propagação com 1 aquecimento descartado + 5 medições; eleição de líder de aplicação pela API de eleição (`enfase-b/candidato.py`, lease de 10 s, 5×) |
| E9 | `scripts/e9_trava_fencing.sh` | **Ênfase B**: violação da exclusão mútua com `docker pause`, correção com fencing token, caso limite (pausa < TTL) e 5 repetições |

### Como as partições são feitas (E4, E6, E7)

Em vez de `docker network disconnect`, o script derruba a interface da rede interna **dentro** do namespace de rede do membro (`ip link set ... down`), usando um contêiner auxiliar temporário. O membro continua acessível ao cliente pela rede `clientes`. O motivo é que o `docker network connect` sorteia um MAC novo e atrasa a reconexão (veja a seção 2).

## 5. Ênfase B – travas, leases e fencing

Arquivos em [enfase-b/](enfase-b/):

- [recurso.py](enfase-b/recurso.py): servidor HTTP com um contador. Detecta e marca a regressão do valor (atualização perdida). Com o fencing ligado, rejeita (HTTP 409) escritas cujo token seja **menor** que o maior token já visto.
- [worker.py](enfase-b/worker.py): pega a trava `trava` no etcd (API HTTP `/v3/lock/lock`) com um lease de TTL 5 s renovado por uma thread de keepalive. Dentro da seção crítica, lê o contador, "processa" e escreve valor+1. O **fencing token** é a `create_revision` da chave da trava, que é global e só cresce no etcd. A trava é a mesma do `etcdctl lock` (receita do pacote `concurrency`: chave `trava/<lease>` e fila pela `create_revision`), chamada pelo serviço `Lock` da API v3 para que o worker controle o próprio lease e leia a revisão; o E8 usa o `etcdctl lock` diretamente.

Cenários do `e9_trava_fencing.sh`:

| Cenário | O que acontece | Resultado esperado |
|---|---|---|
| 0 | dois workers, 5 incrementos cada, sem falhas | valor final 10 |
| 1 | worker1 é congelado (`docker pause`) dentro da seção crítica além do TTL; worker2 pega a trava; worker1 acorda e escreve | **violação**: o valor volta para trás |
| 2 | igual ao 1, com o recurso checando o fencing token | escrita atrasada **rejeitada**; valor correto |
| 3 | pausa de 2 s, menor que o TTL de 5 s | lease sobrevive; sem violação |
| rep | cenários 1 e 2 repetidos 5 vezes | contagem de violações/rejeições e tempo de tomada da trava |

Para rodar um cenário só: `bash scripts/e9_trava_fencing.sh 1`.

## 6. Ferramenta de medição

[ferramentas/etcd_http.py](ferramentas/etcd_http.py) roda no contêiner `cliente` e fala com o etcd pela API HTTP/JSON. Assim as medições não incluem o custo do `docker exec` (~170 ms no Windows). Os comandos estão no cabeçalho do arquivo.

Medições que começam com uma ação no host e terminam num evento dentro do contêiner usam sempre o relógio dos contêineres nas duas pontas: o relógio da VM do Docker Desktop fica ~60 ms à frente do relógio do Windows.

## 7. Estrutura

```
docker-compose.yml       cluster etcd (3 membros) + cliente + recurso + workers
ferramentas/             Dockerfile da imagem cliente, etcd_http.py (medições) e ajuste_rto.py (análise do E7)
enfase-b/                recurso.py e worker.py (ênfase B)
scripts/                 comum.sh (funções compartilhadas), um script por experimento e executar_todos.sh
evidencias/              saídas geradas pelos scripts (usadas no relatório)
relatorio/               relatório em Word e figuras (diagramas próprios; gerar_figuras.py refaz as que dependem das evidências)
```
