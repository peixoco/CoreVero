# 12-adenda — Q9 e Q10 (regime laboral da imagem)

> Anexar ao `12-respostas-juridicas-pre-parecer.md`. Duas questões que o documento original não enfrentava e que condicionam a foto de atribuição — a peça mais sensível do produto.

---

## Q9 — Qualificação da foto face aos arts. 20.º/21.º do CT (vigilância a distância)

### Posição

A captura fotográfica no momento da picagem **não constitui meio de vigilância a distância** na aceção do art. 20.º do CT, e o parecer deve afirmá-lo expressamente, com esta fundamentação:

1. **Não há observação contínua nem em tempo real** — o dispositivo não filma, não transmite, não permite a um superior "ver" o trabalhador; capta um único fotograma num instante determinado. _[Certain no facto técnico]_
2. **O gatilho é um ato voluntário do próprio trabalhador** (a picagem que ele inicia com o seu código), não uma decisão de observação do empregador. A finalidade é autenticar o ato do próprio — proteção do trabalhador contra picagens feitas por terceiros em seu nome — não observar o seu desempenho. _[Likely na qualificação]_
3. **Não serve, nem pode servir, para controlo de desempenho** (proibição do art. 20.º/2): a foto não mostra trabalho, mostra a pessoa a registar presença. O compromisso contratual de ausência de matching (cláusula 3 do DPA) reforça a limitação de finalidade.

### Consequência se o advogado discordar

Se a qualificação for de vigilância a distância: finalidade restrita a proteção de pessoas e bens (difícil de sustentar para autenticação de picagem), deveres de informação reforçados e afixação de avisos — e o produto teria de ser repensado nesta componente. Por isso esta é uma questão de **carimbo obrigatório**, não de nota de rodapé. _[Certain na consequência]_

### Mitigação já existente (a invocar)

O texto do art. 13.º (Q2) já é entregue no onboarding **e afixado junto ao kiosk** — materialmente equivalente ao dever de informação do regime de vigilância, o que torna a posição robusta nos dois cenários de qualificação.

---

## Q10 — O comparador adverso dos 90 dias: art. 31.º da Lei 58/2019

### O problema

A videovigilância no contexto laboral tem prazo de conservação legal de **30 dias** (art. 31.º da Lei 58/2019). Se a foto-por-picagem for analogizada a videovigilância, o default de 90 dias do Q3 excede um teto legal — e a CNPD faz analogias restritivas em matéria de imagem de trabalhadores. _[Likely no prazo; Certain no risco de analogia]_

### Posição

Os 90 dias sustentam-se **se e só se** a distinção do Q9 for carimbada: a foto de atribuição é registo probatório pontual acessório ao registo de tempos (relógio do art. 202.º CT), não gravação de sistema de videovigilância (relógio do art. 31.º). São finalidades e regimes distintos; o prazo segue a finalidade — três ciclos de conferência salarial.

### Plano B (já suportado pela arquitetura)

`foto_retencao_dias` é configurável por tenant. Se o advogado concluir que a analogia com o art. 31.º é um risco real, o default desce de 90 para 30 **por configuração, sem alteração de código** — o mecanismo de exceção por litígio (Q3) mantém-se válido em qualquer dos prazos. A decisão é jurídica, não técnica; nada bloqueia desenvolvimento.

---

## Lista do advogado — versão atualizada (substitui a secção "O que fica para o advogado")

1. **Carimbar a qualificação Q9** (foto ≠ vigilância a distância, arts. 20.º/21.º CT) — condiciona tudo o resto sobre a foto.
2. **Decidir Q10**: 90 dias com a distinção fundamentada, ou recuo para 30 — condiciona o default de `foto_retencao_dias`.
3. Escolher a base legal da foto — 6.º/1/f vs 6.º/1/c (Q2) — e carimbar o texto art. 13.º.
4. Validar/corrigir o DPA-tipo (Q1), com atenção às cláusulas 7, 9 e 10.
5. Carimbar a tabela de retenções, com foco nos itens 3 e 6.
6. Validar a AIPD-tipo quando redigida (Q7) — deve incorporar expressamente a análise Q9/Q10 na secção de necessidade e proporcionalidade.
7. Confirmar o desenho dos dois registos art. 30.º (Q8)
