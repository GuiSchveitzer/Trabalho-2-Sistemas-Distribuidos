#!/usr/bin/env bash
# E2 - Caminho de uma operacao: put enviado a um SEGUIDOR e encaminhado ao lider.
# Evidencias: cabecalho da resposta (revision, raft_term, member_id), RAFT INDEX
# avancando nos 3 membros e metricas de rede mostrando o trafego seguidor -> lider.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e2_caminho.txt"

L=$(lider)
# Escolhe como seguidor o primeiro membro que nao e o lider
for n in 1 2 3; do [ "$n" != "$L" ] && { S=$n; break; }; done
for n in 1 2 3; do [ "$n" != "$L" ] && [ "$n" != "$S" ] && O=$n; done

# Bytes que o membro $1 ja enviou ao membro $2 pela rede Raft
bytes_enviados() {
  py metricas "$(ip_de "$1")" etcd_network_peer_sent_bytes_total \
    | grep "To=\"$(id_de "$2")\"" | awk '{ printf "%.0f", $2 }'
}

{
  titulo "E2 - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "lider = etcd$L ($(id_de "$L"))   seguidor usado = etcd$S ($(id_de "$S"))   outro seguidor = etcd$O ($(id_de "$O"))"

  titulo "RAFT INDEX antes"
  ctl_todos endpoint status -w table

  titulo "put enviado SO ao seguidor etcd$S (endpoint unico), resposta em JSON"
  ctl "$S" put /config/modo "producao" -w json
  echo
  echo "(member_id no cabecalho = quem respondeu ao cliente; raft_term = termo do lider atual)"

  titulo "RAFT INDEX depois: os 3 membros avancam juntos (entrada replicada e aplicada)"
  ctl_todos endpoint status -w table

  titulo "leitura em cada membro"
  for n in 1 2 3; do echo "etcd$n: $(ctl "$n" get /config/modo --print-value-only)"; done

  titulo "encaminhamento: 200 puts de 10 KB enviados ao seguidor etcd$S"
  a_lider=$(bytes_enviados "$S" "$L"); a_outro=$(bytes_enviados "$S" "$O")
  py carga "$(ip_de "$S")" 200 10000
  d_lider=$(bytes_enviados "$S" "$L"); d_outro=$(bytes_enviados "$S" "$O")
  echo "bytes etcd$S -> lider etcd$L        : +$((d_lider - a_lider))"
  echo "bytes etcd$S -> outro seguidor etcd$O: +$((d_outro - a_outro))"
  echo "Conclusao: o seguidor nao replica sozinho; ele repassa a proposta ao lider (~2 MB),"
  echo "que a distribui via AppendEntries. Para o outro seguidor so vao respostas/heartbeats."
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
