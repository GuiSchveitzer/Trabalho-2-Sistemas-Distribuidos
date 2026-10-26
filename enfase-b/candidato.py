# Candidato a lider de aplicacao usando a API de eleicao do etcd (/v3/election/campaign).
# Diferente do "etcdctl elect" (sessao fixa de 60 s), aqui o candidato cria o proprio lease
# com TTL escolhido e o renova a cada TTL/3. Se o processo morrer, o lease vence e o
# proximo candidato da fila assume.
#
# Uso: python candidato.py <nome> <ip_etcd> <nome_eleicao> [--ttl 10]
import argparse
import base64
import json
import threading
import time
import urllib.request


def http(url, corpo, timeout=10):
    req = urllib.request.Request(url, data=json.dumps(corpo).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def b64(texto):
    return base64.b64encode(texto.encode()).decode()


def renovar(etcd, lease, ttl):
    while True:
        time.sleep(ttl / 3)
        http(f"{etcd}/v3/lease/keepalive", {"ID": lease})


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("nome")
    p.add_argument("ip_etcd")
    p.add_argument("eleicao")
    p.add_argument("--ttl", type=int, default=10)
    a = p.parse_args()
    etcd = f"http://{a.ip_etcd}:2379"

    lease = http(f"{etcd}/v3/lease/grant", {"TTL": a.ttl})["ID"]
    threading.Thread(target=renovar, args=(etcd, lease, a.ttl), daemon=True).start()
    print(f"CANDIDATO {a.nome} lease={lease} TTL={a.ttl}s", flush=True)

    # Bloqueia ate este candidato ser o dono da menor create_revision do prefixo da eleicao
    resp = http(f"{etcd}/v3/election/campaign",
                {"name": b64(a.eleicao), "value": b64(f"{a.nome}-e-o-lider"), "lease": lease},
                timeout=None)
    rev = resp.get("leader", {}).get("rev")
    print(f"LIDER {a.nome} rev={rev} t_ms={int(time.time() * 1000)}", flush=True)
    while True:
        time.sleep(3600)
