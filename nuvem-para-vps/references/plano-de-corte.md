# Plano de corte

Escreva o plano como um roteiro de passos nomeados, de preferência num script que roda **um passo
por vez** e **para no primeiro erro**. Cada passo tem: o que faz, o que confere antes de terminar e
o que fazer se falhar. A volta atrás é um passo do roteiro, escrito e ensaiado, não uma ideia.

## Antes do dia

- **Véspera:** TTL do DNS dos registros que vão mudar baixado para 60–300 s.
- **Escolha da janela:** a de menor uso medido (olhe o tráfego por hora da última semana). Confira
  na meia hora anterior que o uso está mesmo baixo.
- **Ensaio completo** feito, com o tempo de cada cópia medido.
- **Avise** quem precisa saber (time, clientes, se for o caso), com início e fim previstos.
- **Integrações externas testadas pelo IP da VPS**: gateway de pagamento com chave restrita por IP,
  APIs com lista de IPs, webhooks de terceiros, envio de e-mail.

## O roteiro (modelo)

| # | Passo | O que faz | Confere antes de seguir |
|---|---|---|---|
| 1 | `pre` | nada muda: só conferências | nenhum deploy em andamento; réplicas sincronizadas (atraso 0); integrações externas respondem pela VPS; mesmas imagens (por digest) nos dois lados; foto do estado atual salva para a volta |
| 2 | `pausar` | pausa filas, agendador e jobs | nenhum job em voo por alguns minutos seguidos |
| 3 | `parar` | aplicações a 0 réplica, depois serviços de dados a 0 (na origem) | cada grupo com 0 tarefas rodando |
| 4 | `promover` | banco novo vira principal | posição de replicação igual nos dois lados; réplica desligada; escrita liberada no novo; banco antigo parado |
| 5 | `copiar` | cópia final (delta) dos volumes e arquivos | retorno 0 e contagens iguais |
| 6 | `subir` | sobe as stacks na VPS, dados primeiro, aplicações depois | todos os serviços convergidos e saudáveis |
| 7 | `testar` | testa cada domínio **pelo IP da VPS** com o cabeçalho Host certo, antes do DNS | respostas e páginas esperadas |
| 8 | `dns` | troca os registros | troca só se o valor atual é o IP antigo (evita sobrescrever mudança de outra pessoa) |
| 9 | `soltar` | libera filas e agendador | jobs andando |
| 10 | `conferir` | URLs públicas, login real, uma operação de escrita real | tudo responde; nada de erro novo no log |
| — | `voltar` | DNS de volta, réplicas da origem repostas pela foto, VPS em somente leitura | o site antigo responde |

**Atenção à volta:** depois do passo 4, o que for escrito no banco novo não existe no antigo. Se
voltar depois disso, essa escrita precisa ser reconciliada ou se perde. Por isso a decisão de seguir
ou voltar acontece no passo 7, antes do DNS, com o site ainda parado.

## Critérios de volta

Defina antes, por escrito, e não negocie na madrugada: por exemplo, contagem diferente em qualquer
tabela, serviço que não converge em X minutos, erro em operação de escrita real.

## Depois

- Anote a hora de cada passo e o tempo fora do ar medido (do `parar` ao `conferir`).
- Deixe a origem **parada, não apagada**, por vários dias.
- Feche a origem da VPS para o proxy (se houver) no mesmo dia.
- Na manhã seguinte, olhe com uso real: login, pagamento, upload, envio de e-mail, tempo real.
