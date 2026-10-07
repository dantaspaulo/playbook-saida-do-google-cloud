# Montar a VPS, na ordem

Cada passo tem o comando de referência. Rode com a pessoa, confira, e só então siga.

## 1. Acesso

1. Crie um usuário com sudo e coloque a sua chave SSH nele.
2. Teste o login por chave **numa segunda janela**, sem fechar a primeira.
3. Só então desligue senha e root no SSH (`/etc/ssh/sshd_config`: `PasswordAuthentication no`,
   `PermitRootLogin no`) e reinicie o serviço. Confira de novo numa janela nova.
4. Atualizações de segurança automáticas (`unattended-upgrades` no Ubuntu) e `fail2ban` para o SSH.

## 2. Firewall

- Entrada liberada: 22 (SSH), 80 e 443. O resto fechado (`ufw default deny incoming`).
- **O Docker publica portas por fora do UFW.** Uma porta publicada num serviço fica aberta para a
  internet mesmo com o UFW negando. Duas regras:
  - publique porta só no proxy (Traefik); os outros serviços falam pela rede overlay;
  - filtros para portas publicadas vão na cadeia `DOCKER-USER` do iptables, não no UFW.
- Com Cloudflare (ou outro proxy) na frente, **feche 80 e 443 para tudo que não for o proxy** no
  mesmo dia do corte: `assets/origem-cloudflare.sh`. Com a origem aberta, qualquer um fala direto
  com o servidor, pula o WAF e falsifica o cabeçalho de IP do visitante, o que torna inútil
  qualquer limite por IP. Meça antes (um `tcpdump` de algumas horas mostra quem chega direto) e
  deixe a regra persistir no boot.

## 3. Docker e Swarm

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER          # entre de novo depois
docker swarm init
docker network create -d overlay --attachable publica
```

Dois avisos: `curl | sh` executa o que vier do endereço (leia o script antes, ou instale pelo
repositório oficial do Docker para a sua distribuição); e estar no grupo `docker` equivale a ser
root na máquina, então só o seu usuário entra nele.

Swarm com um nó só já dá: stacks declarativas, atualização sem queda (`order: start-first`),
segredos, reinício automático e a porta aberta para crescer.

## 4. Traefik e Portainer

```bash
export ACME_EMAIL=voce@dominio.com
docker stack deploy -c assets/traefik-stack.yml borda

openssl rand -base64 24 | tee /dev/tty | docker secret create portainer_admin -   # guarde a senha
export PORTAINER_HOST=painel.dominio.com MEU_IP=203.0.113.10
docker stack deploy -c assets/portainer-stack.yml portainer
```

- Portainer exposto é alvo: o modelo já sobe com lista de IPs permitidos e com o admin criado a
  partir de um segredo. O certificado novo aparece em registros públicos em minutos, e robôs
  vigiam esses registros procurando painel sem dono. Melhor ainda: acesso com login na frente
  (Cloudflare Access, por exemplo).
- **Fixe versões das imagens** (a estável do dia, nunca `latest`). Um `docker service update --force`
  re-resolve a tag no registro e pode trazer versão nova sem você pedir.

## 5. As aplicações

Partindo de `assets/app-exemplo-stack.yml`:
- dado que importa em **volume nomeado**, nunca no sistema de arquivos do contêiner;
- `update_config: order: start-first` e pelo menos 2 réplicas do que atende usuário;
- `stop_grace_period` maior que o dreno (`assets/dreno.sh`): o Traefik demora alguns segundos para
  tirar a réplica que está saindo da roleta, e quem morre na hora devolve erro nesse intervalo;
- `healthcheck` real (uma rota que toca o banco), não só "o processo está vivo";
- limites de memória por serviço, para um vazamento não derrubar a máquina inteira.

## 6. Disco

- Poda periódica de imagens e cache de build (`docker system prune -af --filter until=168h` num
  timer), rotação de log do Docker (`max-size`, `max-file` no `daemon.json`).
- Alerta quando o disco passar de ~80%.
