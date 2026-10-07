# Armadilhas de quem já fez

Cada uma: sintoma, causa, o que fazer.

## Rede e cópia
- **A VPN para no meio da cópia grande.** Sintoma: com alguns GB copiados, o túnel UDP (WireGuard)
  morre e o TCP segue. Causa provável: proteção contra inundação do provedor tratando o UDP como
  ataque. Fazer: cópia e réplica por **SSH/TCP**, com um usuário só para isso e sem shell. De quebra,
  a cópia ficou bem mais rápida.
- **Integração externa recusa o IP novo.** Gateway de pagamento com chave restrita por IP devolve
  403; API pública do país recusa IP estrangeiro. Fazer: testar cada integração pelo IP da VPS no
  `pre` do corte, e ter o portão recusando seguir se falhar.

## Proxy na frente (Cloudflare)
- **Websocket cai sem resposta.** Sintoma: "conexão perdida, reconectando" em tela de tempo real.
  Causa: a zona injeta cabeçalhos de localização do visitante (`cf-ipcity`, `cf-region`), e cidade
  com acento ("São Paulo") quebra servidor que exige ASCII nos cabeçalhos do upgrade. Fazer:
  apagar esses cabeçalhos no Traefik (middleware no modelo) ou desligar a transformação na zona.
- **Chave de API restrita por domínio "inválida".** Causa: `Referrer-Policy: same-origin` vindo da
  zona faz o navegador não mandar o Referer a terceiros. Fazer:
  `<meta name="referrer" content="strict-origin-when-cross-origin">` na página.
- **Origem aberta.** Com 80/443 abertos para o mundo, o proxy vira enfeite: falam direto com a VPS,
  pulam o WAF e forjam o IP do visitante. Fazer: `assets/origem-cloudflare.sh`. A lista de faixas
  da Cloudflare vem **sem quebra de linha no fim**: ler com `while read` perde a última faixa.
- **Worker chamando o próprio site** é visto com o país de quem chamou (o datacenter do Worker), não
  do visitante. Regra de bloqueio por país na zona pode barrar o seu próprio vigia.

## Contêiner e Swarm
- **O que mora dentro do contêiner some na recriação:** plugin instalado à mão, keystore,
  credencial gravada no disco do contêiner. Fazer: volume nomeado ou imagem própria com o plugin.
  Depois de recriar, prove a função de verdade (um webhook real), não só a rota de saúde.
- **Deploy derruba requisição.** Sintoma: dezenas de erros 500 a cada atualização. Causa: o Traefik
  leva alguns segundos para perceber a réplica saindo, e o servidor fecha na hora do SIGTERM. Fazer:
  `assets/dreno.sh` (segura o SIGTERM por ~20 s), 2 réplicas e `start-first`. Meça antes e depois
  com um laço de requisições durante o deploy.
- **Volume velho com o mesmo nome** é reaproveitado em silêncio. Renomeie antes; não apague.
- **Tag solta** (`latest`) muda a versão num `--force`. Fixe versões.

## Bancos
- **A máquina nova sobe com outra versão do banco.** Uma versão diferente da testada pode ter um
  defeito que só aparece com o uso real (por exemplo, depois de apagar muitos registros de uma vez,
  como numa limpeza antes da cópia). Fazer: subir na VPS exatamente a versão que foi ensaiada,
  repetir o ensaio depois de qualquer limpeza grande, e tratar atualização de serviço com estado
  como janela própria.
- **Índice grande não recria** com a memória de manutenção padrão. Suba o parâmetro só no restore.
- **Estatística de tabela não é contagem.** Confira com `COUNT(*)`.

## Custo
- **Disco, snapshot e IP sem dono** seguem cobrando depois que a VM some. A nuvem também guarda
  backup automático de instância apagada, e cobra.
- **Sair da infraestrutura não é fechar o projeto:** APIs (login, mapas, reCAPTCHA, IA), um relay e
  o bucket de backup podem continuar. Liste o que fica e o custo de cada um.
- **Preço promocional da VPS** pago adiantado; a renovação pode dobrar. A conta tem que fechar
  no preço cheio.

## Processo
- **Dois passos em voo** fazem o verde de um parecer o verde do outro. Um por vez.
- **Painel verde agora** não diz nada sobre a madrugada inteira. Leia a janela.
- **Script do corte com bug** no próprio teste: tenha um segundo jeito de conferir (as URLs públicas,
  uma operação real), e não confunda falha do instrumento com falha do sistema.
