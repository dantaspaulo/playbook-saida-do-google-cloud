# Serviços com estado: classificar, copiar e conferir

## A tabela que guia a migração

Preencha uma linha por item do inventário. É o documento que a pessoa revisa antes de qualquer
passo.

| Item | Tem estado? | Tamanho | Escrita por minuto | Método de cópia | Como conferir | Parada aceitável | Volta atrás |
|---|---|---|---|---|---|---|---|
| ex.: banco principal | sim | 19 GB | alta | réplica + promoção | contagem exata por tabela | minutos | apontar de volta, réplica reversa |
| ex.: cache de sessão | não importa | 1 GB | alta | nenhum (recria) | login funciona | segundos | n/a |
| ex.: arquivos de usuário | sim | 30 GB | baixa | pré-cópia + delta | contagem e soma MD5 | zero (cópia antes) | manter origem |

Perguntas por item:
- **Tem estado?** Se o contêiner morrer e voltar vazio, alguém perde algo? Cache que só acelera não
  tem estado que importe; fila com job pendente tem.
- **Escrita por minuto** decide o método: pouco movimento aceita "parar, copiar, subir"; muito
  movimento pede réplica ou pré-cópia mais delta.
- **Dono do dado:** antes de recriar qualquer contêiner, pergunte o que mora no disco dele.
  Plugin instalado à mão, chave guardada no keystore, arquivo gerado em `/tmp`: tudo some na
  recriação se não estiver em volume.

## Métodos por tipo

### MySQL
- **Pequeno ou pouco movimento:** `mysqldump --single-transaction --routines --triggers --events`
  com a aplicação parada, restaurar, contar.
- **Grande ou muito movimento:** réplica com GTID do banco antigo para o novo (por túnel SSH se não
  houver rede privada), deixar o atraso zerar, e no corte: parar escrita, conferir GTID igual nos
  dois lados, `STOP REPLICA; RESET REPLICA ALL;`, `read_only=OFF` no novo e o antigo parado (dois
  bancos aceitando escrita é o pior cenário).
- **Banco gerenciado (Cloud SQL, RDS)** normalmente aceita ser fonte de réplica externa; confira
  flags exigidas (binlog, GTID) antes do dia.
- **Conferir:** `SELECT COUNT(*)` por tabela nos dois lados (as estatísticas do
  `information_schema` são aproximadas e enganam).
- Mudando de versão maior (ex.: 8.0 → 8.4), suba a versão nova no ensaio e rode a aplicação
  inteira contra ela antes do corte.

### PostgreSQL
- `pg_dump -Fc` por banco (ou `pg_dumpall` para papéis), restaurar com `pg_restore -j`.
- Réplica lógica para banco grande com muito movimento.
- Índices grandes (vetoriais, por exemplo) podem exigir mais `maintenance_work_mem` para recriar.
- **Conferir:** `COUNT(*)` por tabela; consulta sentinela da aplicação.

### MongoDB
- `mongodump --archive --gzip` / `mongorestore`, ou cópia do volume com o serviço parado.
- **Conferir:** `db.colecao.countDocuments({})` por coleção.

### Redis
- Se for só cache: não copie, deixe esquentar de novo.
- Se guarda fila, sessão que importa ou dado: AOF ligado, `BGSAVE`, copiar o arquivo com o serviço
  parado no corte.
- **Conferir:** `DBSIZE` e uma chave sentinela.

### Busca vetorial (Qdrant e similares)
- Snapshot por coleção pela API, ou `rsync --checksum` da pasta de dados com os dois lados parados.
- Antes de copiar, vale limpar vetores órfãos (de documentos apagados): menos para mover.
- **Conferir:** contagem de pontos por coleção e uma busca sentinela com resultado conhecido.

### Elasticsearch / OpenSearch
- Snapshot para repositório (bucket) e restore, ou cópia dos arquivos com o nó parado (mesma versão).
- O keystore (credenciais de repositório) mora dentro do contêiner se não estiver em volume.
- **Conferir:** `_cat/indices` com contagem de documentos e uma busca sentinela.

### Arquivos em bucket (GCS, S3) → armazenamento próprio (MinIO, R2)
- **Pré-cópia** dias antes (`rclone copy` ou `gcloud storage rsync`), **delta** no corte.
- **Conferir:** quantidade de objetos e MD5 (o `rclone check` compara).
- Troque a aplicação para o novo armazenamento numa janela própria, separada do corte do banco.

### Volumes do Docker
- `rsync -aHAX --numeric-ids` com o serviço parado, ou `tar` do volume.
- **Volume com o mesmo nome no destino é reaproveitado em silêncio** pelo Swarm: se já existir um
  velho, renomeie (não apague) antes de subir.

## Conferência: o que conta como "igual"

- Contagem exata por tabela, coleção, índice ou bucket, dos dois lados, depois da parada da escrita.
- Uma consulta sentinela por serviço com resultado conhecido.
- Para arquivos, soma (MD5) e não só quantidade.
- Escreva o resultado com a hora. "Conferi" sem número não é conferência.
