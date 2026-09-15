---
title: Recurso restrito ou liberado por padrão — a coluna resources.is_restricted
description: Pedido ao SSO para declarar em cada recurso se ele é restrito ou liberado quando nenhuma concessão se aplica a quem pede, com o que muda no esquema, no back, nas respostas e no front.
tipo: explicacao
publico: desenvolvedor
atualizado: 2026-09-15
---

# Recurso restrito ou liberado por padrão — `resources.is_restricted`

Pedido do `report-service` e do `server-service` ao SSO, para o back (`sso-service` e `sysnormal-spring-boot-starter-sso`), o `react-sso` e o `sso-front`.
Leia antes de mexer em `resources`, em `/records/resources/get_alloweds` ou em `/records/resources/get_resource_permissions`.

> **Documento temporário.** Válido até o SSO publicar a coluna e escrever a documentação para os consumidores se adaptarem.
> Depois disso, o que sobrevive é a regra no [contrato de SSO](../../../../../../docs/contratos/sso.md) e o que o SSO decidir registrar em ADR; este arquivo é apagado.

## O que está acontecendo

Hoje ninguém declara o que acontece com um recurso quando **nenhuma concessão se aplica** a quem pede.
Cada consumidor deduz isso de alguma coisa que existe ou não no cadastro, e cada um deduz de uma coisa diferente:

| Consumidor | Sem concessão aplicável | Deduzido de |
|---|---|---|
| `get_alloweds` e `get_resource_permissions` (menu, rotas, telas) | **restrito** — o recurso não volta | `INNER JOIN` com `resource_permissions` |
| `report-service` (recurso `TABLE`) | **restrito** — a consulta é recusada | existir o recurso |
| `server-service` (recurso `TABLE` `collaborators`) | cai no recorte pela estrutura hierárquica | existir o recurso |

O custo apareceu em 2026-09-15.
Alguém quis **estreitar** o que o perfil SUPPLIER vê de `movement_items`: criou o recurso `TABLE` 9010 e a concessão 9011, com predicado por `supplier_id`.
A intenção era recortar o fornecedor.
O efeito foi **fechar a tabela para todos os outros perfis**: todo relatório customizado junta `movement_items`, e passou a responder `acesso negado: a tabela 135 (alias 'mi') é recurso protegido e este agente não tem concessão sobre ela` para qualquer um que não fosse fornecedor.

Não houve erro de cadastro.
O modelo não tem como dizer "este recurso é aberto, e esta concessão só estreita um perfil".

## O que se pede

Uma coluna em `resources`:

| Coluna | Tipo | Nulo | Padrão | Significado |
|---|---|---|---|---|
| `is_restricted` | `tinyint`, `CHECK (is_restricted in (0,1))` | não | `1` | O que vale para quem **nenhuma** concessão alcança: `1` nega, `0` libera |

A regra que todos os consumidores passam a seguir cabe numa tabela, e a coluna só muda **a primeira linha**:

| Situação para o agente que pede | `is_restricted = 1` | `is_restricted = 0` |
|---|---|---|
| nenhuma concessão aplicável | **nega** | **libera** |
| concessão com `allowed_access = 0` | nega | nega |
| concessão com predicado (`json_data`) | libera, recortado | libera, recortado |
| concessão sem predicado | libera tudo | libera tudo |

Todo o resto continua como está.
"Concessão aplicável" é a mesma de hoje: nominal ao agente vence a de perfil, vigência respeitada, excluída e inativa não contam.
Não há uma lógica de "expandir" separada de "estreitar": num recurso restrito a concessão libera, num aberto ela recorta ou nega, e as duas coisas são a mesma avaliação.

### Por que o padrão da coluna é `1`

Recurso cadastrado sem ninguém decidir não pode nascer aberto.
Com padrão `0`, cadastrar um recurso deixaria de proteger qualquer coisa até alguém lembrar de virar o campo — é a falha aberta que o modelo inteiro existe para evitar.

E `1` preserva o comportamento atual de **todos** os recursos existentes: tela, componente, `DATA` e `TABLE` já são tratados como restritos hoje.
A migração não muda o acesso de ninguém.
A única linha que deve receber `0` depois da migração é a que motivou o pedido:

```sql
UPDATE resources SET is_restricted = 0 WHERE id = 9010; -- movement_items, domínio 10
```

## Back — `sysnormal-spring-boot-starter-sso`

### Esquema

O esquema do SSO sai das entidades: `V1__CreateAllTablesAndConstraints` cria as tabelas por reflexão, e `FlywayAfterHibernate` ordena as duas coisas.
A coluna entra em `database/entities/sso/Resource.java`, no molde de `show_in_menu`:

```java
@Column(name = "is_restricted", nullable = false)
@ColumnDefault("1")
@Check(constraints = "is_restricted in (0,1)")
private byte isRestricted = 1;
```

Para a base que já existe (`sysnormal_sso_dev_v4`), o `V1` versionado não roda de novo.
Cabe ao SSO escolher entre uma migração nova e recriar a base carregando os dados; se for migração, o efeito precisa ser este:

```sql
ALTER TABLE resources
  ADD COLUMN is_restricted TINYINT NOT NULL DEFAULT 1,
  ADD CONSTRAINT resources_chk_is_restricted CHECK (is_restricted IN (0,1));
```

### `get_alloweds` e `get_resource_permissions`

Os dois hoje fazem `INNER JOIN` de `resources` com `resource_permissions` (`ResourcesRepositoryImpl.findAlloweds` e `findResourcePermissions` com `JoinType.INNER`).
Com a coluna, um recurso aberto sem concessão aplicável **precisa voltar**, então o join vira `LEFT`, e o recurso volta quando:

- existe concessão aplicável; **ou**
- não existe, e `is_restricted = 0`.

⚠️ **A armadilha desta mudança.**
Hoje o filtro das flags — `allowedAccess = 1`, que o `react-sso` sempre manda — está no `ON` do join (`joinPredicates`).
Num `INNER JOIN` isso é o mesmo que estar no `WHERE`.
Num `LEFT JOIN` não é: a concessão que **nega** (`allowed_access = 0`) deixa de casar no `ON`, o lado direito vem nulo, e a linha fica indistinguível de "nenhuma concessão aplicável".
Num recurso aberto, isso vira **liberado**.
Ou seja, mover o join para `LEFT` sem mover o filtro transforma toda negação explícita em acesso.

O filtro das flags tem de valer sobre as flags **efetivas** — as da concessão aplicável, ou as do padrão quando não há concessão —, depois de decidir qual concessão se aplica, e nunca no `ON` do join.
Vale um teste que cadastre recurso aberto com uma concessão `allowed_access = 0` para um perfil e confira que aquele perfil **não** o recebe.

O mesmo cuidado vale para os predicados de visibilidade (`getVisibilityPredicates`): concessão excluída, expirada ou inativa tem de contar como "não aplicável", e não pode apagar a linha do recurso.

`get_with_permissions` já é `LEFT` e serve à tela de administração; ali basta devolver a coluna.

### O que um recurso aberto sem concessão devolve

A resposta desses endpoints hoje sempre carrega uma concessão.
Para recurso aberto sem concessão aplicável não há concessão a devolver, e o consumidor precisa saber quais flags valem.
A proposta é:

| Campo | Valor |
|---|---|
| `resourceIsRestricted` | `0` |
| `resourcePermissionId`, `...AccessProfileId`, `...AgentId` | `null` |
| `resourcePermissionAllowedAccess`, `resourcePermissionAllowedView` | `1` |
| `resourcePermissionAllowedCreate`, `...AllowedChange`, `...AllowedDelete` | `0` |
| `resourcePermissionCondition`, `resourcePermissionJsonData` | `null` |

**Liberado por padrão concede acessar e ver, e não criar, alterar nem excluir.**
Numa tabela de dado isso não faz diferença.
Numa tela de cadastro faz: liberar as cinco flags daria **exclusão** a todo mundo que abrisse a tela.
Quem precisa escrever num recurso aberto recebe concessão explícita, como hoje.
Essa é a única regra deste pedido que ainda **não foi confirmada** pelo dono do sistema — confirme antes de fechar a implementação.

`resourcePermissionId = null` passa a ser resposta legítima.
Consumidor que hoje trata concessão nula como "sem acesso" precisa ser avisado.

`ResourcePermissionView` ganha `resourceIsRestricted`, e o `records/resources/get` genérico passa a trazer `isRestricted` pela entidade.

## Front

### `react-sso`

`ResourcePermissionData`, em `src/sso/resourceService.ts`, ganha `resourceIsRestricted?: 0 | 1`, e o comentário do tipo passa a dizer que `resourcePermissionId` pode vir nulo num recurso aberto.
`useGetAllowedResources` não precisa mudar a chamada: continua mandando `allowedAccess: 1`, e é o servidor que resolve.
Mudar o tipo pede versão nova publicada — o `front-spa` depende do pacote.

### `sso-front`

Em `src/config/entities.ts`, `resourcesEntity`:

- coluna na listagem, junto de `showInMenu`;
- campo no formulário **obrigatório e sem valor pré-marcado** — "Restrito" ou "Liberado por padrão".
  Um checkbox que já vem marcado é decisão tomada pela tela, não por quem gerencia o recurso.

A ajuda do campo precisa dizer, em uma frase, que a escolha só vale para quem nenhuma concessão alcança.

`ResourcePermissionsScreen.tsx` e `permission.ts` leem `get_resource_permissions`; confira se tratam concessão nula como ausência.

## Aproveitando: nome de recurso `TABLE` repetido

Desde 2026-09-15, `report-service` e `server-service` identificam a tabela de um recurso `TABLE` **pelo nome**, e não mais pelo `id_at_origin`, que ficou opcional para esse tipo (ver o [contrato de SSO](../../../../../../docs/contratos/sso.md)).

O unique `resources_u1` é `(coalesce(parent_id,-1), record_status_id, domain_id, resource_type_id, name)` — inclui o pai.
Dois recursos `TABLE` com o mesmo nome e pais diferentes passam hoje, e os dois protegeriam a mesma tabela com concessões diferentes.
Os consumidores não têm como decidir qual vale.
Vale o SSO recusar nome de `TABLE` repetido no mesmo domínio, na gravação.

## Depois de implementado

O SSO documenta a regra para os consumidores.
Os que leem recursos e concessões hoje, e o que cada um precisa rever:

| Consumidor | Onde | O que muda |
|---|---|---|
| `report-service` | `SsoDataScopeProvider`, `SecurityDecorator` | tabela protegida sem concessão aplicável: nega se `1`, libera se `0` |
| `server-service` | `SsoCollaboratorsRestrictionProvider`, `SsoRegisterAccessGuard` | idem; no escopo de colaboradores, "liberado" é o recorte pela estrutura, não todos os colaboradores |
| `winthor-integration-service` | `AgentsService`, `WinthorReachService` | recursos `DATA` (equipes): alcance sem concessão |
| `front-spa` | `App.tsx`, `SsoPanelController`, `PanelAccess`, `ActivityLogConfig` | recurso pode vir com concessão nula |
| `sso-front` | `App.tsx`, `permission.ts`, `ResourcePermissionsScreen.tsx` | idem |

Até cada consumidor se adaptar, todos continuam tratando recurso sem concessão como restrito, e isso segue correto para as linhas com `is_restricted = 1`.
O recurso 9010 com `0` só passa a valer no `report-service` quando o `report-service` ler a coluna.
