# Imagem dos conteineres cliente/recurso/workers: Python + etcdctl (copiado da imagem oficial do etcd)
FROM python:3.12-alpine
COPY --from=quay.io/coreos/etcd:v3.5.17 /usr/local/bin/etcdctl /usr/local/bin/etcdctl
# Fuso de Brasilia (UTC-3) sem precisar do pacote tzdata
ENV TZ="<-03>3" \
    PYTHONUNBUFFERED=1
