# Dimensionar a VPS pelo uso medido

## O que medir (30 dias, não o instante)

- **CPU:** p95 do uso somado de todas as máquinas, em vCPU (não em % de cada uma).
- **Memória:** p95 da memória **usada** (não a alocada) somada, mais o que cada banco precisa de
  cache para não ir ao disco (buffer do MySQL, heap do Elasticsearch, vetores em memória).
- **Disco:** ocupado hoje por serviço com estado + volumes + imagens.
- **Rede:** tráfego de saída por mês (VPS costuma incluir uma franquia grande; confira).

No Google Cloud, o Monitoring tem esses números por VM; banco gerenciado mostra uso no próprio
painel. Se não houver histórico, meça uma semana antes de comprar.

## Fórmulas de partida

- **vCPU** = p95 somado × 1,5 (folga para pico, deploy e backup rodando junto).
- **RAM** = memória usada p95 somada + cache dos bancos + 25%.
- **Disco** = dados com estado × 2 (cópia local do backup e crescimento) + 20 GB de sistema e imagens.
- Arredonde para o plano acima. Folga de memória vale mais que folga de CPU: faltar memória mata
  processo; faltar CPU só deixa lento.

## Uma máquina ou várias

Comece com **uma máquina com folga**. Menos peças, sem rede entre nós, backup e monitoramento num
lugar só. Separe em mais de uma só com motivo medido: um serviço que disputa disco com o banco,
isolamento exigido, ou carga que não cabe.

## Região e latência

- Plano grande pode não existir na região mais próxima. Meça a latência real (`ping`, ou o tempo de
  uma requisição) do lugar onde estão os usuários até a região disponível. Para aplicação web,
  algo abaixo de ~100 ms costuma passar despercebido; para tempo real, pese mais.
- Serviço que conversa muito com o banco precisa estar **na mesma máquina** do banco: latência entre
  provedores multiplica por consulta.
- Algumas APIs públicas recusam IP de fora do país. Teste cada integração externa pelo IP da VPS
  antes do corte; se alguma recusar, um relay pequeno no país resolve.

## Preço

- Compare o preço **de renovação**, não só o promocional. Plano pago adiantado com desconto pode
  dobrar na renovação; a conta de economia tem que fechar nos dois cenários.
- Some o que fica na nuvem antiga (armazenamento de backup, APIs, um relay) ao custo novo.
- Escreva a conta com a fonte de cada número: fatura, período, câmbio quando houver.
