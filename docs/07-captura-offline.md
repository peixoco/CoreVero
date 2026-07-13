# 07 — Captura Offline (outbox + autorização), Sprint 3

> Como garantir que uma picagem nunca se perde por falta de rede, sem atravessar a linha "o kiosk nunca lê o PIN".
> Princípio que este documento defende: **"captura imune à rede" são duas decisões, não uma.** Uma é barata e segura; a outra troca uma propriedade de segurança e tem de ser decidida de olhos abertos.
> Documentos relacionados: `02-stack-e-padroes.md` (§2.3), `01-arquitetura-bd.md`, `06-jurisdicao-rh.md`.

---

## 1. O problema (e porque é grave)

Hoje o fluxo são **três idas ao servidor em sequência**: `iniciar_picagem` (valida PIN) → `registar_picagem` (escreve) → upload da foto. Sem rede, a **primeira** chamada falha e a câmara nem abre. Offline, o colaborador **não pica de todo**. _[Certain]_

Isto não é um incómodo de UX — é um **registo legal de tempos** (CT art. 202.º). Um corte de rede a meio do turno que impeça uma picagem é uma falha de conformidade, não um bug menor. O instinto de "não podemos perder registos" está certo. _[Certain]_

Mas há um segundo perigo, mais subtil, que tem de guiar todo o desenho: **uma picagem silenciosamente perdida é pior do que uma picagem recusada à frente do colaborador.** Se o trabalhador pica, vê "✓", e horas depois o registo é descartado no servidor, ele acredita que picou e não picou. Para um registo legal, a falha tem de ser **visível no momento ou exposta ao admin** — nunca engolida. _[Certain]_

---

## 2. A distinção que muda tudo

O doc 02 §2.3 fala em "captura imune à rede" como se fosse uma coisa. São duas, e convém separá-las porque têm custos opostos:

| Peça                                    | O que torna imune à rede                                                                         | Custo | Risco de segurança                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------ | ----- | ---------------------------------- |
| **A — Escrita imune** (outbox)          | O _registo_ (verificação + picagem + foto) não depende de a rede estar viva no instante do toque | Baixo | Nenhum novo                        |
| **B — Autorização imune** (PIN offline) | A _abertura da câmara_ não depende do servidor para validar o PIN                                | Alto  | **Material de PIN no dispositivo** |

A Peça A resolve o caso comum (cortes curtos) e **não toca em nada de segurança**. A Peça B é a única forma de picar durante um corte **prolongado** (router em baixo uma hora) — e é onde mora o problema, porque obriga a ter algo contra o qual validar o PIN no tablet, partilhado com o POS.

**A tese deste documento:** fazer a Peça A já, e tratar a Peça B como uma decisão separada e consciente — não a contrabandear sob a palavra "outbox". _[Likely]_

---

## 3. Peça A — a outbox (escrita imune à rede)

Desenho, alinhado com o doc 02 §2.3 (um só caminho de escrita; online drena em milissegundos, offline espera):

1. No instante do toque, o cliente **carimba `momento_dispositivo`** (hora autoritária) e mete na fila local um item: `{ codigo, pin, tipo, momento, foto_bytes }`. _[Certain]_
2. A fila **drena** assim que há rede: por cada item, chama `registar_picagem` → recebe `{ verificacao_id, foto_path }` → faz upload da foto para esse caminho.
3. **O id continua a ser gerado no servidor**, no momento do drain. O cliente não precisa do id no instante da captura — só guarda os bytes da foto e os inputs. Isto **preserva a autoridade do servidor** da Fase 2 e **não exige alteração de schema**. _[Certain]_
4. A foto vive no `FileSystem` do dispositivo até o upload confirmar; depois é apagada localmente. _[Certain]_
   **Idempotência (o detalhe que parte se for ignorado):** se o drain registar a picagem mas a app morrer antes de guardar o `verificacao_id` devolvido, uma repetição **regista a picagem duas vezes**. Duas saídas: _[Likely]_

- (i) `registar_picagem` aceita uma **chave de idempotência** do cliente (o id do item da outbox); a segunda chamada com a mesma chave devolve o resultado anterior em vez de inserir. Robusto, exige uma coluna/índice.
- (ii) aceitar duplicados raros e **deduplicar no servidor** (único por trabalhador+tipo+minuto). Mais simples, menos exato.
- Recomendação: **(i)**, porque um registo legal de tempos não deve ter duplicados "raros". _[Likely]_
  **Importante:** a Peça A, sozinha, só cobre cortes que aconteçam **depois** de a câmara abrir (a `iniciar_picagem` já passou online). Cobre o blip de rede a meio da transação — o caso mais comum. Não cobre o colaborador que chega à frente do tablet **já** sem rede. Esse é o domínio da Peça B.

---

## 4. Peça B — autorização offline (o conflito do PIN)

Para abrir a câmara offline, o dispositivo tem de validar o PIN **sem servidor**. Isso colide de frente com a regra "o kiosk nunca lê a coluna `pin`". Três opções:

### Opção 1 — Não validar offline; recusar no drain

Offline, aceita qualquer código+PIN, captura, mete na fila. O servidor valida no drain; PIN errado → item recusado.

- **Mata-se sozinha por duas razões:** captura **rostos de tentativas inválidas** (viola a minimização RGPD — foi precisamente por isto que pusemos o PIN antes da câmara) e produz **picagens silenciosamente perdidas** (o §1 diz que isto é o pior). **Rejeitada.** _[Certain]_

### Opção 2 — Cache local de material de PIN (recomendada, condicional)

A cache de leitura fina (doc 02 §2.3 já a prevê para "códigos ativos") passa a guardar, por trabalhador ativo da loja: `codigo_pessoal`, `nome`, `trabalhador_id` e um **derivado do PIN** (não o PIN em claro). Offline, valida o PIN contra o derivado → câmara abre só se bater. No drain, o servidor **revalida** (defesa em profundidade).

- **A verdade desconfortável, sem a vender bonita:** um PIN de 4 dígitos tem 10 000 combinações. Qualquer hash, por mais lento, é forçável em segundos por quem extraia a cache. Portanto **o derivado do PIN não é uma fronteira de segurança** — é um mecanismo de _disponibilidade_. _[Certain]_
- **Porque é, ainda assim, aceitável:** a segurança deste sistema **nunca assentou no segredo do PIN**. O PIN é fraco por desenho; a **foto é a prova**. Mesmo que um atacante extraia a cache e aprenda todos os PINs da loja, para forjar uma picagem teria de produzir **a foto do rosto certo** — e a revisão humana apanha a fraude. Cachear PINs não remove uma propriedade que fosse sustentadora. _[Likely]_
- **O que cachear PINs _aumenta_ mesmo:** concentra os PINs de toda a loja num sítio extraível, num tablet partilhado com o POS. Sobe o raio de dano de um tablet roubado/comprometido. _[Certain]_
- **Mitigação que torna o derivado útil:** em vez de hash simples, **HMAC com uma chave de dispositivo** guardada no enclave seguro (iOS Keychain). Assim, extrair o ficheiro de cache **sozinho** não revela PINs — seria preciso também a chave do Keychain. Eleva a fasquia de forma real, ao contrário de um hash salgado. _[Likely]_

### Opção 3 — Token rotativo por trabalhador em vez de PIN

O colaborador deixa de usar um PIN que decora e passa a um token. Resolve a criptografia, mas troca a usabilidade (o kiosk vive de gente que pica depressa com um PIN de cabeça). **Excesso de engenharia para esta fase. Rejeitada para MVP.** _[Likely]_

**Recomendação:** Opção 2, **com HMAC em Keychain**, e **só se** a picagem durante corte prolongado for mesmo requisito desta fase. Caso contrário, fica para depois (ver §6).

---

## 5. Consequências de segurança (não negociáveis se a Peça B avançar)

1. **"Revogar kiosk" entra no MESMO sprint.** Cachear PINs da loja num tablet partilhado só é defensável se houver forma de **matar a sessão do kiosk de imediato** (e invalidar a cache). É já um requisito firme; a Peça B promove-o de "pendente" a "obrigatório nesta unidade". _[Certain]_
   - Nuance: revogar a sessão **mata a capacidade de drenar a outbox**. Um tablet perdido com picagens por enviar perde-as. Trade-off aceite: segurança acima de recuperar registos de um dispositivo perdido (dispositivo perdido = dados locais perdidos de qualquer forma). _[Likely]_
2. **Foto em repouso no dispositivo.** Offline, fotos de rostos ficam no `FileSystem` até drenar. Minimizar: apagar localmente **logo** após upload confirmado; ativar proteção de dados do iOS (cifragem em repouso ligada ao desbloqueio). _[Likely]_
3. **Cache obsoleta.** Um trabalhador desativado ou com PIN mudado **enquanto o dispositivo está offline** ainda passa no check local. O servidor recusa no drain — mas isso reabre o problema da picagem perdida. **A recusa tem de ser exposta ao admin, não engolida** (§1). É um caso de exceção que pede atenção humana, raro porque offline é a exceção. _[Likely]_
4. **HMAC com chave de dispositivo**, não hash simples (§4, Opção 2). _[Likely]_

---

## 6. Faseamento recomendado

Separar o barato-e-seguro do caro-e-arriscado:

- **Sprint 3a — Outbox (Peça A).** Fila local como único caminho de escrita; `momento_dispositivo` autoritário; id no servidor no drain; idempotência; indicador de pendentes na UI; apagar foto local após upload. **Zero material de PIN no dispositivo.** Cobre o caso comum (blips de rede). É o grosso do valor com nenhum do risco. _[Likely]_
- **Sprint 3b — Autorização offline (Peça B), decisão consciente.** Só se "picar durante corte prolongado" for requisito desta fase. Traz: cache de PIN (HMAC/Keychain), revalidação no drain com exposição de recusas, **e "revogar kiosk" no mesmo bloco**. _[Likely]_
  > Pergunta de scope a fechar antes de 3b: no restaurante-piloto, qual é o cenário real — blips de Wi-Fi de segundos (3a chega) ou cortes de router de horas (obriga a 3b)? Se for o primeiro, 3b pode esperar e poupa-se o risco de PIN-no-tablet por agora.

---

## 7. Consequências de implementação

1. **Outbox local** (fila persistente): tabela/estrutura no dispositivo com estado por item (`pendente → registado(verificacao_id, path) → enviado → concluído`), para retomar só o sub-passo que falhou. _[Certain]_
2. **`registar_picagem` ganha chave de idempotência** (coluna + índice único na verificação, ou tabela de chaves), se adotada a Opção (i) do §3. _[Likely]_
3. **Cache de leitura fina**: códigos ativos + derivado HMAC do PIN + nome/`trabalhador_id`, atualizada quando online. _[Likely]_
4. **RPC dedicada para abastecer a cache** (devolve o derivado, nunca o PIN em claro; o kiosk continua sem `select` na coluna `pin`). _[Certain]_
5. **"Revogar kiosk"**: matar/rotacionar a sessão Auth do dispositivo no admin; ao revogar, a cache local fica inútil para escritas novas (sessão morta não drena). _[Likely]_
6. **Exposição de recusas no drain**: estado visível no admin para itens recusados na revalidação. _[Likely]_
7. **Indicador de pendentes** na UI do kiosk ("3 picagens por enviar"). _[Certain]_

---

## 8. Decisões fechadas vs a confirmar

**Fechadas (neste documento):**

- "Captura imune à rede" = duas peças separadas (escrita vs autorização).
- Peça A (outbox) faz-se primeiro, sem material de PIN no dispositivo; cobre o caso comum.
- A Opção 1 (recusar no drain sem check local) está fora — viola minimização e perde registos.
- Se a Peça B avançar, "revogar kiosk" entra no mesmo sprint, e o derivado do PIN é HMAC com chave em Keychain, não hash simples.
- `momento_dispositivo` é sempre a hora do toque, independente de quando drena.
  **A confirmar:**
- **Scope (§6):** o piloto precisa só de resiliência a blips (3a) ou de picar durante cortes prolongados (3b)? Decide se a Peça B é desta fase.
- **Idempotência (§3):** chave de idempotência (i) vs dedupe servidor (ii).
- **Prazo de retenção da foto local** antes de purgar em caso de drain falhado prolongado.
- **Formato da cache** e estratégia de refresh (intervalo, gatilho).
  > **Disclaimer:** documento de decisão de arquitetura, não parecer de segurança nem jurídico. O modelo de ameaça do PIN cacheado (§4) assenta no princípio já adotado "PIN fraco, foto é a prova"; se esse princípio mudar, esta análise muda com ele. O ponto sobre registo legal de tempos perdido (§1) deve ser validado com apoio laboral antes de produção com dados reais.
