#!/usr/bin/env bash
# E1 - Subida e topologia: membros, lider, termo e indice Raft, saude e memoria.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e1_topologia.txt"

{
  titulo "E1 - $(date '+%Y-%m-%d %H:%M:%S')"

  titulo "member list"
  ctl_todos member list -w table

  titulo "endpoint status (IS LEADER, RAFT TERM, RAFT INDEX)"
  ctl_todos endpoint status -w table

  titulo "endpoint health"
  ctl_todos endpoint health

  titulo "lider atual"
  echo "etcd$(lider)"

  titulo "memoria dos conteineres"
  docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}" etcd1 etcd2 etcd3

  titulo "enderecos (rede interna = Raft :2380 | rede clientes = API :2379)"
  for n in 1 2 3; do
    docker inspect -f "etcd$n  {{range \$rede, \$cfg := .NetworkSettings.Networks}}{{\$rede}}={{\$cfg.IPAddress}}  {{end}}" "etcd$n"
  done
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
