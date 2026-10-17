# Enfase B - Recurso compartilhado "protegido" por uma trava do etcd.
# Guarda um contador que os workers incrementam com leitura -> processamento -> escrita.
# Se dois workers ficarem na secao critica ao mesmo tempo, uma atualizacao se perde
# (o valor "volta para tras"). Com FENCING ligado, o recurso rejeita escritas cujo
# token (revisao da chave da trava no etcd) seja menor que o maior token ja visto.
#
# Servidor:  python recurso.py
# Cliente:   python recurso.py reset <0|1>   (zera o estado; 1 = liga o fencing)
#            python recurso.py historico
import json
import sys
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORTA = 8000
URL = f"http://172.31.0.50:{PORTA}"

estado = {"valor": 0, "maior_token": 0, "fencing": False, "historico": []}
mutex = threading.Lock()  # protege apenas o estado interno do servidor (threads HTTP)


def registrar(msg):
    linha = f"{time.strftime('%H:%M:%S')}.{int(time.time() * 1000) % 1000:03d} {msg}"
    estado["historico"].append(linha)
    print(linha, flush=True)


def escrever(worker, novo, token):
    # Regra do fencing: aceita token >= maior ja visto (o mesmo detentor pode escrever varias vezes)
    if estado["fencing"] and token < estado["maior_token"]:
        registrar(f"REJEITADA  {worker} token={token} < maior_token={estado['maior_token']} (valor={novo} descartado)")
        return 409, {"ok": False, "motivo": "token antigo"}

    anterior = estado["valor"]
    estado["valor"] = novo
    estado["maior_token"] = max(estado["maior_token"], token)
    aviso = ""
    if novo <= anterior:
        aviso = f"   <-- VIOLACAO: valor voltou de {anterior} para {novo} (atualizacao perdida)"
    registrar(f"ACEITA     {worker} token={token} valor {anterior} -> {novo}{aviso}")
    return 200, {"ok": True}


class Handler(BaseHTTPRequestHandler):
    def responder(self, codigo, corpo):
        dados = json.dumps(corpo).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        with mutex:
            if self.path == "/ler":
                self.responder(200, {"valor": estado["valor"]})
            elif self.path == "/historico":
                self.responder(200, estado)
            else:
                self.responder(404, {})

    def do_POST(self):
        corpo = json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")
        with mutex:
            if self.path == "/escrever":
                self.responder(*escrever(corpo["worker"], corpo["valor"], corpo["token"]))
            elif self.path == "/reset":
                estado.update(valor=0, maior_token=0, fencing=bool(corpo["fencing"]), historico=[])
                registrar(f"RESET      fencing={'LIGADO' if estado['fencing'] else 'DESLIGADO'}")
                self.responder(200, {"ok": True})
            else:
                self.responder(404, {})

    def log_message(self, *args):
        pass  # sem o log padrao de cada requisicao HTTP


def cliente(cmd, args):
    if cmd == "reset":
        req = urllib.request.Request(URL + "/reset", data=json.dumps({"fencing": args[0] == "1"}).encode())
        urllib.request.urlopen(req, timeout=5)
    elif cmd == "historico":
        dados = json.loads(urllib.request.urlopen(URL + "/historico", timeout=5).read())
        print("\n".join(dados["historico"]))
        print(f"\nvalor final = {dados['valor']}   maior_token = {dados['maior_token']}   "
              f"fencing = {'LIGADO' if dados['fencing'] else 'DESLIGADO'}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        cliente(sys.argv[1], sys.argv[2:])
    else:
        print(f"recurso ouvindo na porta {PORTA}", flush=True)
        ThreadingHTTPServer(("0.0.0.0", PORTA), Handler).serve_forever()
