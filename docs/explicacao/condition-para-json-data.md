---
title: Da coluna condition para json_data em resource_permissions
description: O que muda no SSO, back e front, com o predicado de acesso passando a ser declarado em JSON estruturado, e por que a mudança é necessária.
tipo: explicacao
publico: desenvolvedor
atualizado: 2026-08-19
---

# Da coluna `condition` para `json_data` em `resource_permissions`

Aviso do `report-service` ao SSO sobre uma mudança em curso no formato do predicado de acesso, e o que cada lado precisa saber.
Leia antes de mexer na edição de `resource_permissions`, no back ou no front.

> **Documento temporário.** Válido até a decisão ser fechada e o `report-service` passar a ler `json_data`.
> Depois disso, o que sobrevive é o ADR da decisão e a página de contrato do SSO; este arquivo é apagado.

## O que está acontecendo

O `report-service` consome `resource_permissions` para restringir linhas nos relatórios: lê a `condition` da concessão que alcança o agente e mescla o texto como predicado na consulta que está montando.

Isso funciona enquanto há **um** consumo. Passaram a existir dois, e eles são incompatíveis:

- **mesclar** — o `report-service` enfia o predicado na consulta que está compondo;
- **resolver** — o `server-service` precisa executar o mesmo critério contra a própria tabela para devolver a lista de ids que o agente alcança.

O caso que expôs isso: uma concessão de `collaborators` **sem** `condition`. Para a mesclagem ela está certa — o join existe para resolver nome e hierarquia, e a restrição de verdade está na permissão de `movements`. Lida pelo consumo de ids, a mesma linha significa "irrestrito", e o vendedor passa a alcançar todos os colaboradores. Medido em dev: 86.

O raciocínio completo, com o histórico e as alternativas descartadas, está em `SYSNORMAL/reports/report-service/docs/explicacao/predicado-de-acesso-em-json.md`.
Esta página não repete aquilo — cobre só o que toca o SSO.

## Por que JSON, e não continuar em texto

Em `condition`, **o seletor e o predicado estão fundidos numa string**:

```sql
#{TABLE_ALIAS}.seller_id = #{collaborators.id}
```

Não dá para perguntar a esse texto "a qual ocorrência da tabela isso se aplica" sem parsear SQL. E a pergunta é real: no catálogo de relatórios, `collaborators` é montada **três vezes**, com sentidos diferentes — uma vez no esqueleto, uma como supervisor, uma como vendedor. Hoje o motor prende o predicado numa delas, escolhida por ordem de percurso.

O JSON separa as duas coisas:

```json
{
  "predicates": { "seller_id": "#{collaborators.id}" }
}
```

E abre espaço para dizer **onde** se aplica, quando a tabela aparece mais de uma vez.
A gramática desse "onde" ainda está em discussão — não a implemente no front agora.

O `#{...}` de identidade continua funcionando como hoje, resolvido contra o `json_data` do vínculo do agente, e continua virando bind na consulta.

## O que muda no `sso-service`

**No esquema, nada.** A coluna já existe: `resource_permissions.json_data`, `longtext` nulável, e está **sem uso nas 2.899 linhas**.

**A invariante continua a mesma, e é a parte importante:** o SSO **armazena e não interpreta**. Ele guarda o texto; quem entende e aplica é o serviço que lê o recurso. Trocar `condition` por `json_data` não muda isso — e ninguém deve aproveitar a mudança para pôr no SSO um compilador de JSON para SQL. Se isso acontecer, o SSO passa a conhecer o dialeto e o esquema de todos os consumidores.

**Uma decisão para vocês:** validar no `save` que o `json_data` é **JSON bem formado**. Recomendo que sim, e só isso — sintaxe, nunca semântica. JSON quebrado hoje só apareceria na hora de emitir um relatório, em outro serviço, como erro de montagem sem relação aparente com o cadastro.

**A `condition` não morre.** Ela fica como escape para o que o JSON não expressar, e passa a ser exceção em vez de caminho normal. Hoje **uma única linha** a usa.

## O que muda no `sso-front`

Menos do que parece: **o campo já existe**. Em `src/config/entities.ts`, a `resourcePermissionsEntity` já declara `jsonDataField` ao lado de `condition`, como `multiline`. Dá para preencher `json_data` hoje, sem nenhuma alteração.

O que agregaria, em ordem de utilidade:

1. **Validar e formatar JSON** no campo — recusar salvar texto malformado e indentar o que está lá. É barato e pega o erro no lugar onde ele nasce.
2. **Sinalizar a coexistência.** Enquanto durar a transição, uma permissão pode ter `condition` e `json_data` preenchidos. Mostrar isso explicitamente evita que alguém edite um e ache que corrigiu o outro.
3. **Formulário guiado** — só depois. A gramática de seleção de ocorrência (`rules`, `unmatched`, `predicates`) ainda está sendo desenhada, e um formulário construído sobre ela agora precisaria ser refeito.

## A migração dos dados: uma linha, e a ordem importa

No `sysnormal_sso_dev_v4` existe **uma** permissão com `condition` preenchida:

```
id 2903   resource 367 (movements)   perfil 10 (SELLER)
condition: #{TABLE_ALIAS}.seller_id = #{collaborators.id}
```

**Não limpe a `condition` agora.** Nada lê `json_data` ainda: mover a informação hoje apagaria a única restrição de linha em vigor, e o perfil SELLER passaria a enxergar os movimentos de todo mundo — sem erro, sem sintoma, só mais dados.

A ordem segura é escrita dupla:

1. **Agora** — preencher `json_data` **mantendo** a `condition`. Nada muda de comportamento: o `report-service` continua lendo só a `condition`.
2. **Depois que o leitor de `json_data` existir e for verificado** — limpar a `condition` da linha migrada.

Isso impõe uma regra ao leitor, que precisa estar decidida antes do passo 2: **quando os dois estiverem preenchidos, `json_data` vence**. Sem essa regra a escrita dupla não é segura, porque a linha teria duas verdades simultâneas.

O script dos dois passos está em `sql_resource_permissions_condition_to_json.sql`, na raiz deste repositório. O passo 1 é idempotente e casa com o texto exato da condition atual; o passo 2 vem comentado, para ser liberado só quando a hora chegar.

## Estado verificado em 2026-08-19

```
sso-service aponta para  sysnormal_sso_dev_v4   (o banco do SSO não foi para o v5)
resource_permissions     2.899 linhas
  com condition          1   (id 2903)
  com json_data          0

resources tipo TABLE no domínio sysnormal (10)
  367  movements      id_at_origin 5
  368  collaborators  id_at_origin 19
```

O banco do Sysnormal foi recriado como `sysnormal_dev_v5` e ganhou duas colunas novas no catálogo de relatórios, do lado do consumidor. Elas não têm equivalente no SSO e não pedem nada daqui.

## Onde ver na prática

- `SYSNORMAL/reports/report-service/docs/explicacao/predicado-de-acesso-em-json.md` — a proposta completa
- `SYSNORMAL/reports/report-service/docs/referencia/escopo-de-dados.md` — como o `report-service` consome hoje
- `SYSNORMAL/docs/contratos/sso.md` — o contrato do ecossistema, que passa a precisar de ajuste quando a decisão fechar
