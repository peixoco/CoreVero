alerta liga-se ao fluxo de ação corretiva — notifica → corrige → regista.

### 2.7 Dois tipos de utilizador

- **Admins/gestores:** contas Supabase Auth, claim `empresa_id`, âmbito empresa ou loja.
- **Colaboradores:** sem login individual. Identificam-se por `codigo_pessoal` + foto num kiosk que se autentica como identidade de loja. O kiosk só insere eventos da sua loja.

### 2.8 Licenciamento por lugares

Enforcement na BD: não se ativa o colaborador N+1 acima do limite pago. Desativar preserva histórico e liberta lugar. **Adiado na fase de teste** — a estrutura (colunas, contagem) fica, o enforcement liga-se quando entrar a faturação.

### 2.9 Configuração como dados — checklists definidas pelo admin, nunca em código

As checklists HACCP são **linhas** (`checklist_template` + `checklist_item`), criadas pelo administrador na UI. Nenhuma checklist é codificada. O motor é genérico: lê o tipo do item, a unidade e os limites, calcula conformidade e força ação corretiva quando aplicável — sem código por checklist. É isto que torna o produto escalável: um cliente novo, com plano HACCP diferente, configura tudo sem alterações de código. **Consequência de scope:** o construtor de templates no admin (adicionar itens, definir tipo/unidade/limites/frequência) é uma feature central do MVP, não um extra.

---

## 3. Fronteiras de responsabilidade

- O software é ferramenta de **monitorização e prova**, não o plano HACCP. A análise de perigos e os limites críticos vêm do plano existente (SARA) / de um responsável de segurança alimentar — e são introduzidos pelo admin, não codificados.
- A foto serve **atribuição por revisão humana**. Não há reconhecimento facial automático — adicioná-lo transformaria o tratamento em biométrico (RGPD art. 9.º) e é uma linha a não atravessar.
