#!/usr/bin/env bash
# Funcoes e variaveis usadas por todos os scripts de experimento.
# Uso: source scripts/comum.sh

# No Git Bash (Windows) impede que caminhos como /config/modo virem C:/Program Files/Git/...
export MSYS_NO_PATHCONV=1

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="${EVID:-$RAIZ/evidencias}"        # pode ser trocado (ex.: EVID=/tmp/teste) para testar sem sobrescrever
# Arquivos de trabalho (logs brutos dos workers e valores intermediarios das medicoes): so servem durante a execucao,
# o conteudo deles vai para as evidencias em evidencias/
TRAB="${TMPDIR:-/tmp}/t5-etcd"
mkdir -p "$EVID" "$TRAB"

EP=172.31.0.31:2379,172.31.0.32:2379,172.31.0.33:2379

# IP (rede de clientes) do membro N
ip_de() { echo "172.31.0.3$1"; }

# etcdctl executado DENTRO do membro N apontando so para o proprio endpoint
# (endpoint unico: nao deixa o cliente trocar de membro e esconder falhas)
ctl() {
  local n=$1; shift
  docker exec "etcd$n" etcdctl --endpoints="$(ip_de "$n"):2379" "$@"
}

# etcdctl com a lista completa de endpoints (executado a partir de um membro vivo)
ctl_todos() {
  local de=${DE:-1}
  docker exec "etcd$de" etcdctl --endpoints="$EP" "$@"
}

# Numero (1, 2 ou 3) do membro que e lider, perguntando a partir do membro $1 (padrao 1)
lider() {
  local de=${1:-1}
  docker exec "etcd$de" etcdctl --endpoints="$EP" endpoint status -w simple 2>/dev/null \
    | awk -F', ' '$5 == "true" { split($1, a, ":"); split(a[1], b, "."); print substr(b[4], 2) }'
}

# Termo Raft visto pelo membro N
termo() {
  ctl "$1" endpoint status -w simple 2>/dev/null | awk -F', ' '{ print $7 }'
}

# Indice Raft visto pelo membro N
indice() {
  ctl "$1" endpoint status -w simple 2>/dev/null | awk -F', ' '{ print $8 }'
}

# Ferramenta Python (ferramentas/etcd_http.py) executada no conteiner "cliente"
py() { docker exec cliente python /app/ferramentas/etcd_http.py "$@"; }

# ID (hexadecimal) do membro N, como aparece nas metricas e no member list
id_de() {
  ctl "$1" endpoint status -w simple 2>/dev/null | awk -F', ' '{ print $2 }'
}

# Particao: derruba (down) ou religa (up) a interface da rede INTERNA do membro N.
# O membro continua acessivel ao cliente pela rede "clientes". Usa um conteiner auxiliar
# no mesmo namespace de rede do membro (a imagem do etcd nao tem shell nem "ip").
# Obs.: "docker network disconnect/connect" tambem funcionaria, mas o connect sorteia
# um MAC novo e os vizinhos demoram para atualizar o cache ARP.
# Imprime o instante da acao (epoch ms, relogio dos conteineres) para medicoes como a do E7.
interface_interna() {
  local n=$1 acao=$2
  docker run --rm --net "container:etcd$n" --cap-add NET_ADMIN t5-cliente \
    sh -c "ip link set dev \$(ip -o -4 addr show | grep ' 172.30.' | cut -d' ' -f2) $acao \
           && python -c 'import time; print(int(time.time() * 1000))'"
}
isola()     { interface_interna "$1" down; }
reconecta() { interface_interna "$1" up; }

# Tempo atual em milissegundos
agora_ms() { date +%s%3N; }

# Recebe numeros (um por linha) e imprime n, media e desvio padrao amostral
estatisticas() {
  # ignora linhas vazias (rodada sem medicao)
  awk 'NF { n++; s += $1; q += $1 * $1; v[n] = $1 }
       END {
         if (n == 0) { print "sem dados"; exit }
         m = s / n
         d = (n > 1) ? sqrt((q - n * m * m) / (n - 1)) : 0
         printf "n=%d  media=%.1f  desvio=%.1f  (valores:", n, m, d
         for (i = 1; i <= n; i++) printf " %s", v[i]
         print ")"
       }'
}

# Espera ate todos os 3 membros responderem saudaveis
espera_saudavel() {
  for _ in $(seq 1 60); do
    if docker exec etcd1 etcdctl --endpoints="$EP" endpoint health >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "cluster nao ficou saudavel em 60 s" >&2
  return 1
}

# Espera ate o arquivo $1 conter o texto $2 (no maximo $3 segundos, padrao 30)
espera_texto() {
  local limite=$(( ${3:-30} * 10 ))
  for _ in $(seq 1 "$limite"); do
    grep -q "$2" "$1" 2>/dev/null && return 0
    sleep 0.1
  done
  echo "tempo esgotado esperando '$2' em $1" >&2
  return 1
}

titulo() { echo; echo "=== $* ==="; }
