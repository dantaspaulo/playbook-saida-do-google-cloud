---
name: nuvem-para-vps
description: Planeja e conduz a saída de uma nuvem cobrada por uso (Google Cloud principalmente, com notas para AWS e Azure), com várias VMs e serviços gerenciados, para um servidor de preço fixo (VPS) num provedor de hospedagem, com Docker Swarm, Portainer e Traefik, para cortar custo sem perder dado. Mede o custo real por serviço, faz o inventário só com comandos de leitura, separa o que tem estado do que não tem, dimensiona a VPS pelo uso medido, monta a máquina com segurança, ensaia a cópia dos dados, escreve o plano de corte com janela e volta atrás, põe backup fora da VPS com restauração provada e um vigia externo. Use sempre que alguém falar em conta de nuvem alta, sair do Google Cloud, AWS ou Azure, migrar para VPS, "a fatura do GCP está absurda", trocar Cloud SQL ou Memorystore por contêiner, consolidar VMs numa máquina só, ou montar Docker Swarm com Portainer e Traefik, mesmo que a pessoa não diga "migração".
---

# Da nuvem cobrada por uso para um servidor de preço fixo

Muita empresa pequena paga a nuvem como se fosse grande: várias VMs meio ociosas, banco e cache
gerenciados, balanceador, IPs, discos esquecidos, tudo cobrado por uso. Um servidor só, de preço
fixo por mês (uma VPS num provedor de hospedagem), bem montado e com tudo em contêiner, roda a
mesma carga por uma fração do preço. O risco não está na VPS; está na mudança: perder dado,
ficar fora do ar, ou descobrir depois que algo dependia de um serviço que ninguém lembrava.

Esta skill conduz a mudança em fases curtas, cada uma com uma saída concreta. **Ler é livre;
aplicar qualquer coisa pede o ok da pessoa**, sempre com o comando, o efeito e a volta atrás
escritos antes.

## Regras que valem a migração inteira

- **Nada é apagado na nuvem antiga** até a nova estar no ar e verde por vários dias. Primeiro se
  para, depois (bem depois) se apaga. O dinheiro economizado em uma semana não paga um dado perdido.
- **Serviço com estado é tratado à parte** (banco, cache com dado que importa, busca vetorial,
  índice de busca, arquivos). Cada um tem método de cópia, contagem de conferência e volta atrás.
- **Backup provado antes do corte**: um backup só existe depois que foi restaurado e contado.
- **Um passo por vez**, conferido antes do próximo. Dois passos em voo misturam os sinais.
- **Medir a janela, não o instante**: um painel verde agora não prova que ficou verde a noite toda.
- **Pinar projeto e conta em todo comando de nuvem** (`--project`, perfil, região). Configuração
  ativa errada é o jeito mais comum de mexer no ambiente de outra pessoa.

## Fases

### 1. Medir o custo real

Sem o custo por serviço, a migração vira palpite. Peça à pessoa o CSV de **Faturamento →
Relatórios**, agrupado por serviço e SKU, dos últimos 30 dias (no Google Cloud: Billing → Reports
→ Download CSV). Depois:

```bash
python3 <skill>/scripts/ler_custo.py relatorio.csv
```

Mostra o total, o custo por serviço e os SKUs que mais pesam. Leve à pessoa os 3 maiores e o que
cada um é. Costuma aparecer: VMs ociosas, banco gerenciado superdimensionado, discos e snapshots
órfãos, IPs reservados sem uso, egress, logs.

Às vezes a resposta não é VPS: é desligar o que sobrou. Diga isso quando for o caso.

### 2. Inventário só de leitura

```bash
bash <skill>/scripts/inventario_gcp.sh SEU-PROJETO ./inventario
```

Lista VMs, discos, IPs, bancos, cache, buckets (com tamanho), Cloud Run, funções, clusters,
regras de encaminhamento, DNS, agendador e nomes de segredos. Tudo `list`/`describe`; nada muda.
A saída fica local: contém nomes internos e não deve ir para lugar público.

Complete com o que só a pessoa sabe: cron fora da nuvem, webhooks de terceiros apontando para IPs,
e-mail transacional, domínios, quem acessa o quê.

### 3. Classificar e decidir o que vai

Para cada item do inventário, preencha a tabela de `references/estado.md`: tem estado? tamanho?
como copiar? como contar para conferir? quanto tempo fora do ar aguenta? Esta é a peça central do
plano. O que não tem dono nem uso some aqui, antes de migrar (não carregue lixo).

### 4. Dimensionar a VPS pelo uso medido

Use o uso real (p95 de CPU e memória dos últimos 30 dias, disco ocupado), não o tamanho contratado
na nuvem. Fórmulas e folgas em `references/dimensionamento.md`. Prefira uma máquina só, com folga,
a um cluster: menos peças, menos rede, menos custo. Cluster entra quando há motivo medido.

### 5. Montar a VPS

Siga `references/vps-segura.md` na ordem: usuário sem root, SSH só por chave, firewall com só
22/80/443 (e 80/443 só para o proxy, se houver Cloudflare na frente), atualizações automáticas,
Docker, `docker swarm init`, rede overlay, Traefik e Portainer pelos modelos em `assets/`.

Dado que precisa sobreviver vai em **volume nomeado**, nunca no sistema de arquivos do contêiner:
um redeploy recria o contêiner e leva junto o que estava dentro.

### 6. Ensaiar a cópia

Copie os dados para a VPS **sem desligar nada** e suba a aplicação contra a cópia. Compare as
contagens (linhas por tabela, chaves, vetores, documentos, arquivos) com os comandos de
`references/estado.md`. Meça quanto tempo cada cópia levou: é isso que define a janela do corte.

### 7. Backup fora da VPS, com restauração provada

Adapte `assets/backup.sh` e `assets/backup.teste.sh`: dumps diários de cada serviço com estado,
cópia para um armazenamento **fora da VPS** (outro provedor ou bucket), retenção, e um teste que
restaura num contêiner temporário e confere as contagens. Rode o teste antes do corte.

### 8. Plano de corte

Escreva o plano a partir de `references/plano-de-corte.md`: janela de baixo uso, TTL do DNS
reduzido na véspera, ordem dos passos, conferência entre eles, critério de volta atrás e o
caminho da volta. Revise com a pessoa linha a linha. No dia, siga o plano e anote a hora de cada
passo.

### 9. Vigiar de fora

Um vigia que roda **fora** da VPS: se a máquina cair, quem está dentro dela não avisa. O modelo
`assets/vigia-worker.js` roda num Cloudflare Worker a cada 5 minutos, testa os endereços e avisa
depois de falhas seguidas. Complemente com um Uptime Kuma e com o alerta de disco.

### 10. Desligar a nuvem antiga, devagar

Depois de dias verdes: exportação final dos dados que estavam lá, **parar** (não apagar) VMs e
bancos, conferir a fatura dos dias seguintes, e só então apagar. Guarde o que pode ser útil
(snapshot final em armazenamento barato) pelo tempo que a pessoa decidir.

## Armadilhas

Leia `references/armadilhas.md` antes do corte. As que mais custam: porta de origem aberta
deixando o site acessível sem o proxy, cabeçalho de localização com acento derrubando websocket
atrás da Cloudflare, política de referência que quebra chave de API restrita por domínio, disco da
VPS enchendo com imagens e logs, e o serviço que só aparecia na fatura.

## Entrega

Ao fim de cada fase, deixe para a pessoa: o que foi feito, o que foi medido (com a janela), o que
falta e o próximo passo. No fim da migração: custo antes e depois com a fonte, tempo fora do ar
medido, e a lista do que ainda está ligado na nuvem antiga.
