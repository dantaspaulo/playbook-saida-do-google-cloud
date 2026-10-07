# Do Google Cloud para uma VPS em uma semana

*O playbook completo, na ordem em que aconteceu. Para a versão curta, veja o [README](README.md).*

## Índice

1. [O ponto de partida](#1-o-ponto-de-partida)
2. [Primeiro, enxugar dentro da nuvem](#2-primeiro-enxugar-dentro-da-nuvem)
3. [A decisão pela VPS](#3-a-decisão-pela-vps)
4. [Montar a máquina](#4-montar-a-máquina)
5. [Ensaiar a cópia de cada dado](#5-ensaiar-a-cópia-de-cada-dado)
6. [O corte, de madrugada](#6-o-corte-de-madrugada)
7. [O dia seguinte](#7-o-dia-seguinte)
8. [O que ficou no Google, e por quê](#8-o-que-ficou-no-google-e-por-quê)
9. [Backup](#9-backup)
10. [Vigiar de fora](#10-vigiar-de-fora)
11. [O que deu errado](#11-o-que-deu-errado)
12. [O que eu faria igual e o que faria diferente](#12-o-que-eu-faria-igual-e-o-que-faria-diferente)
13. [Checklist para copiar](#13-checklist-para-copiar)

---

## 1. O ponto de partida

O ChatADV é uma plataforma de IA para advogados: API, web, filas, busca em texto, busca vetorial,
um hub de modelos e automações. Em setembro de 2026 isso rodava no Google Cloud em cerca de 11
máquinas virtuais (um Swarm de três nós e VMs separadas para busca, vetores e automações), com
banco MySQL gerenciado, armazenamento de arquivos e balanceador.

Enquanto havia crédito promocional, a conta não doía. Quando o crédito acabou, a conta real
apareceu: **cerca de R$ 223 por dia, uns R$ 6,7 mil por mês** (export de faturamento, média de
19 a 23/09/2026, valor líquido). Por serviço, em nove dias completos:

| Serviço | Parte da conta |
|---|---|
| Compute Engine (as VMs) | ~3/4 |
| Cloud SQL (o banco gerenciado) | ~1/4 |
| Rede e armazenamento | o resto, pouco |

A lição já começa aqui: **olhe a conta por serviço e por SKU antes de decidir qualquer coisa**.
A skill deste repositório traz um script que lê o CSV de faturamento e mostra o que pesa.

## 2. Primeiro, enxugar dentro da nuvem

Antes de pensar em sair, cortamos o que dava dentro do próprio Google:
- dois nós do Swarm e um balanceador que não faziam mais falta saíram;
- a busca vetorial foi para a mesma VM da busca em texto;
- discos foram reduzidos ao que era usado de fato;
- o MySQL saiu do banco gerenciado e foi para um contêiner na VM principal, e o Cloud SQL foi
  desligado.

Isso derrubou a conta para uma fração, com risco baixo, em poucos dias. Se o seu problema é só a
conta, **talvez você pare aqui**. Para nós, o resto ainda pagava por uma infraestrutura maior que
a necessária, e a decisão foi zerar a dependência da nuvem para rodar a produção.

## 3. A decisão pela VPS

- **Tamanho:** 8 vCPU, 32 GB de RAM e 400 GB NVMe, com tráfego de sobra. Saiu do uso medido somado
  das máquinas, com folga para pico, deploy e backup rodando juntos.
- **Uma máquina só**, com Docker Swarm de um nó. Menos peças, sem rede entre nós, backup e
  monitoramento num lugar só, e a porta aberta para crescer.
- **Região:** o plano desse tamanho não existia no Brasil, então a VPS fica nos EUA. Medimos a
  latência antes: ~88 ms do Brasil até ela, imperceptível numa aplicação web.
- **Preço:** o plano pago adiantado por dois anos sai bem mais barato que a renovação. **Fiz a
  conta no preço de renovação**: mesmo assim, somando o que ficou no Google, a conta mensal fica
  em torno de R$ 320, contra os R$ 6,7 mil de antes (−95%).

## 4. Montar a máquina

A ordem que recomendo: usuário com sudo e acesso só por chave SSH (testada numa segunda janela antes
de desligar senha e root), atualizações automáticas, firewall só com 22, 80 e 443, Docker,
`docker swarm init`, rede overlay, **Portainer cedo** (para enxergar tudo dali em diante) e o
Traefik como borda com certificados automáticos. O passo a passo está em
[`vps-segura.md`](nuvem-para-vps/references/vps-segura.md) e os modelos em
[`nuvem-para-vps/assets/`](nuvem-para-vps/assets/).

Duas regras que evitaram dor:
- **todo dado que importa em volume nomeado**, nunca no sistema de arquivos do contêiner;
- **versões fixas** nas imagens, nada de `latest`.

## 5. Ensaiar a cópia de cada dado

Cada serviço com estado ganhou método de cópia, conferência e volta atrás próprios:

| Dado | Tamanho | Como foi copiado | Como foi conferido |
|---|---|---|---|
| MySQL (e subiu de 8.0 para 8.4) | ~19 GB no disco | réplica com GTID por túnel SSH, ligada pouco mais de uma hora antes; no corte, promovida | contagem exata em todas as tabelas, nos dois lados |
| Busca em texto (Elasticsearch) | ~95 GB | cópia dos arquivos com 3 min de parada, numa janela própria | contagem por índice e uma busca sentinela |
| Busca vetorial (Qdrant) | ~7 GB, 2,6 GB depois de uma limpeza | `rsync --checksum` com os dois lados parados | zero diferença; busca sentinela |
| Postgres e Mongo dos serviços menores | alguns GB | volumes copiados com o serviço parado | conferência byte a byte |
| Redis | pequeno | arquivo AOF, copiado com o serviço parado | chaves e sentinela |
| Volumes do Swarm | ~16 GB em 17 volumes | pré-cópia antes do corte, delta no corte | retorno do rsync e contagens |
| Arquivos dos usuários | ~31 GB | pré-cópia para armazenamento próprio; a troca da aplicação fica para uma janela separada, com delta | 100% dos objetos da pré-cópia com o mesmo MD5 |

O ensaio serviu para duas coisas: provar que cada cópia funcionava e **medir quanto tempo cada uma
levava**, que é o que definiu o tamanho da janela.

Limpar antes de copiar compensa: tirar o que não tinha mais uso encolheu a busca vetorial de ~7 para
2,6 GB.

## 6. O corte, de madrugada

O corte foi um script com passos nomeados, **um por vez, parando no primeiro erro**, de madrugada,
na faixa de menor uso medido da semana.

| # | Passo | O que conferiu antes de seguir |
|---|---|---|
| 1 | `pre` (nada muda) | nenhum deploy em andamento; réplica do banco com atraso zero; integração de pagamento respondendo pelo IP da VPS; as mesmas imagens, por digest, nos dois lados; foto do estado atual salva para a volta |
| 2 | `pausar` filas e agendador | alguns minutos seguidos sem nenhum job mexendo em dado |
| 3 | `parar` aplicações e depois dados, na origem | cada grupo com zero tarefas rodando |
| 4 | `promover` o banco novo | posição de replicação igual nos dois lados; réplica desligada; escrita liberada na VPS; banco antigo parado (dois bancos aceitando escrita é o pior cenário) |
| 5 | `copiar` o delta final dos volumes | retorno zero, uns 25 segundos |
| 6 | `subir` as stacks na VPS, dados primeiro | tudo convergido em ~10 min |
| 7 | `testar` cada domínio pelo IP da VPS, com o Host certo | páginas e respostas esperadas, **antes** de mexer no DNS |
| 8 | `dns` | troca só onde o valor ainda era o IP antigo |
| 9 | `soltar` filas e agendador | jobs andando |
| 10 | `conferir` as URLs públicas | todas respondendo |

**Tempo fora do ar: 14 minutos**, medido no log.

A volta atrás estava escrita e ensaiada: devolver o DNS, repor as réplicas da origem a partir da
foto do passo 1 e deixar a VPS em somente leitura. Com um detalhe importante: **depois do passo 4,
o que fosse escrito na VPS não existiria na origem**. Por isso a decisão de seguir ou voltar
acontecia no passo 7, com o site ainda parado.

O trabalho foi conduzido por agentes de IA, com o meu ok em cada passo que mudava alguma coisa.
Ler e medir era livre; aplicar, não.

## 7. O dia seguinte

- De manhã, provas com uso real: login, documentos, a IA, pagamento, tempo real.
- No começo da tarde, a infraestrutura do Google foi **parada, não apagada**.
- Registros de DNS que só existiam por causa da arquitetura antiga foram removidos.
- Nos dias seguintes: atualização de um serviço de dados com bug (seção 11), deploy sem queda
  medido, poda diária de imagens no disco, e **a origem fechada** para só aceitar o proxy.
- No sexto dia, com tudo verde, VMs, discos, snapshots automáticos e o IP fixo foram apagados.

## 8. O que ficou no Google, e por quê

Sair do Google com a infraestrutura não é fechar a conta:
- **APIs** que o produto usa (login com Google, mapas, reCAPTCHA, modelos de IA) continuam lá.
- **Um relay pequeno no Brasil:** uma API pública brasileira recusa IP de fora do país. A VPS nos
  EUA chama o relay, e o relay chama a API.
- **Os arquivos dos usuários, por mais alguns dias:** a troca para o armazenamento próprio tem
  janela separada, para não somar risco ao corte do banco.
- **Buckets de backup**, como segundo destino fora da VPS.
- **Um snapshot final**, por um mês, antes de apagar de vez.

Custo do que ficou: poucos reais por dia.

## 9. Backup

- **Diário:** dump de cada banco, com recusa de dump cortado, cópia local de 7 dias e cópia para
  **dois destinos fora da VPS**, em provedores diferentes.
- **Credencial que só cria objetos** (não apaga nem sobrescreve) no destino de backup: se a VPS for
  invadida, o invasor não leva os backups junto. A retenção fica com a regra do próprio bucket. Vale
  para todos os destinos; confira o que cada provedor permite restringir.
- **Semanal, por desenho:** os arquivos dos usuários, snapshots da busca vetorial e uma cópia
  cifrada do sistema, com a chave fora do servidor.
- **Prova de restauração:** o backup é restaurado num contêiner descartável, **sem rede** com a
  produção, e as contagens são comparadas. Backup que nunca foi restaurado é esperança, não backup.

Os modelos estão em [`nuvem-para-vps/assets/backup.sh`](nuvem-para-vps/assets/backup.sh) e
[`backup.teste.sh`](nuvem-para-vps/assets/backup.teste.sh).

## 10. Vigiar de fora

O monitor que mora na VPS cai junto com ela. Por isso:
- **um vigia externo num Cloudflare Worker**, a cada 5 minutos, testando site, API e os outros
  serviços; avisa no grupo depois de **duas rodadas seguidas** com falha (uma falha isolada não
  acorda ninguém) e avisa de novo quando volta. Uma escrita por rodada no KV: 288 por dia, dentro
  do plano grátis. Modelo em [`vigia-worker.js`](nuvem-para-vps/assets/vigia-worker.js);
- **Uptime Kuma** na VPS para o detalhe (latência, certificados, uma busca real a cada 5 minutos);
- **alerta de disco** acima de 80%.

## 11. O que deu errado

**O túnel caiu no meio da cópia.** Com uns 4 GB copiados por VPN (WireGuard, que usa UDP), o UDP
vindo do Google parou de chegar; o TCP seguiu normal. Provável proteção contra inundação tratando
o tráfego como ataque. A cópia e a réplica passaram para **SSH sobre TCP**, com um usuário só para
isso e sem shell. De brinde, a cópia grande foi de ~13 para ~60 MB/s.

**O gateway de pagamento recusou a VPS.** A chave da API era restrita por lista de IPs, e o IP novo
não estava nela. O passo `pre` do corte testava exatamente isso e **recusou seguir** duas vezes, até
o IP ser liberado. Sem o portão, o corte teria seguido com pagamento quebrado.

**Deploy derrubando requisição.** Medimos dezenas de erros 500 a cada atualização (66 e 78 em dois
testes). O Traefik leva alguns segundos para perceber que a réplica está saindo, e o servidor fechava
na hora do SIGTERM. Correção: um invólucro que segura o SIGTERM por 20 segundos
([`dreno.sh`](nuvem-para-vps/assets/dreno.sh)), duas réplicas e `start-first`. Nos serviços em que
aplicamos, **zero erros** no mesmo teste.

**Uma letra derrubando o tempo real.** A Cloudflare pode injetar cabeçalhos com a cidade e o estado
do visitante. "São Paulo" tem acento, e o servidor de websocket exige ASCII nos cabeçalhos do
upgrade: a conexão caía sem resposta, e a tela mostrava "conexão perdida, reconectando". Correção:
apagar esses cabeçalhos na borda (middleware no
[`traefik-stack.yml`](nuvem-para-vps/assets/traefik-stack.yml)).

**Chave de API "inválida" que não era.** A zona mandava `Referrer-Policy: same-origin`, o navegador
parou de enviar o Referer a terceiros, e uma chave restrita por domínio passou a ser recusada.
Correção: `<meta name="referrer" content="strict-origin-when-cross-origin">`.

**Origem acessível sem o proxy.** Com 80 e 443 abertos para o mundo, dá para falar direto com o
servidor, pular o WAF e forjar o IP do visitante, o que torna inútil qualquer limite por IP. A
origem foi fechada para as faixas da Cloudflare, na cadeia `DOCKER-USER` (o Docker publica portas
por fora do UFW). Detalhe que custou 80 segundos: **a lista de faixas vem sem quebra de linha no
fim**, e a última faixa ficou de fora na primeira tentativa. Modelo em
[`origem-cloudflare.sh`](nuvem-para-vps/assets/origem-cloudflare.sh).

**O que morava dentro do contêiner sumiu.** Ao recriar contêineres, perdemos o que não estava em
volume: plugins instalados à mão num serviço de automação e a credencial guardada no keystore da
busca. Correção: volume ou imagem própria, e, depois de recriar, provar a função de verdade (um
webhook real), não só a rota de saúde.

**Uma versão do banco vetorial com defeito.** A VPS subiu com uma versão diferente da que rodava
antes, e ela tinha um defeito que aparecia depois de apagar muitos registros de uma vez: a busca
deu erro por alguns minutos. Ajuste de configuração e a versão de correção resolveram. Lição: subir
na máquina nova exatamente a versão ensaiada, e tratar atualização de serviço com estado como
janela própria.

## 12. O que eu faria igual e o que faria diferente

**Igual:**
- medir antes de mexer, e medir a janela, não o instante;
- enxugar dentro da nuvem antes de sair;
- réplica do banco em vez de dump na hora do corte;
- o roteiro com passos nomeados, um por vez, parando no primeiro erro, com a volta escrita;
- parar antes de apagar, e apagar só dias depois.

**Diferente:**
- cópia por SSH desde o começo, sem VPN;
- fechar a origem para o proxy como parte do próprio roteiro do corte;
- testar todas as integrações externas pelo IP novo uma semana antes, não só no `pre`;
- fazer o inventário do que mora dentro de cada contêiner antes do primeiro redeploy.

## 13. Checklist para copiar

**Medir**
- [ ] CSV de faturamento por serviço e SKU, 30 dias
- [ ] uso real (p95 de CPU e memória, disco ocupado) de cada máquina
- [ ] inventário só de leitura (VMs, discos, IPs, bancos, buckets, serverless, DNS, agendador)
- [ ] o que só aparece fora do inventário: cron externo, webhooks de terceiros, e-mail, domínios

**Decidir**
- [ ] cortar o que dá dentro da nuvem primeiro
- [ ] tabela de serviços com estado: tamanho, método de cópia, conferência, parada aceitável, volta
- [ ] VPS dimensionada pelo uso medido; conta feita no preço de renovação
- [ ] latência medida até a região disponível

**Montar**
- [ ] acesso por chave, senha e root desligados, firewall 22/80/443
- [ ] Swarm, rede overlay, Portainer, Traefik
- [ ] dado em volume nomeado; versões fixas; dreno e `start-first` nas aplicações

**Ensaiar**
- [ ] cópia de cada dado com contagem igual nos dois lados
- [ ] tempo de cada cópia medido
- [ ] integrações externas testadas pelo IP novo
- [ ] backup fora da VPS e restauração provada

**Cortar**
- [ ] TTL do DNS baixo na véspera; aviso a quem precisa
- [ ] roteiro com `pre`, `pausar`, `parar`, `promover`, `copiar`, `subir`, `testar`, `dns`, `soltar`, `conferir` e `voltar`
- [ ] critério de volta escrito antes
- [ ] hora de cada passo anotada; tempo fora do ar medido

**Depois**
- [ ] origem fechada para o proxy
- [ ] vigia externo e alerta de disco
- [ ] nuvem antiga parada (não apagada) por alguns dias
- [ ] lista do que fica na nuvem antiga, com o custo de cada item
- [ ] apagar com calma, conferindo a fatura dos dias seguintes
