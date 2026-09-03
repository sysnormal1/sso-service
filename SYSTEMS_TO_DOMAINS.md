# Proposta: `systems` → `domains`, com tabela de tipos

**Status:** proposta. Nada foi executado — nem DDL, nem cadastro, nem código.
**Origem:** discussão do `server-service` sobre de onde ele resolve a identidade e o
perfil de um agente. O problema apareceu lá, mas a correção é aqui.
**Data:** 2026-08-07.

---

## 1. O problema

A tabela `systems` do SSO responde hoje, na prática, a duas perguntas diferentes:

- **qual aplicação** o agente está usando — front-spa, sales-person-app, sso-front;
- **qual domínio de dados** o agente é, e com que identidade — Sysnormal, Winthor.

As duas convivem na mesma coluna `system_id`, e nada no esquema distingue uma da outra.

Isso trava um caso concreto. O dado do Sysnormal é um só, mas N serviços o acessam com
propósitos diferentes: `server-service` (backend oficial), `report-service` (relatórios),
`front-spa`, `jumbo-bi`. Se cada serviço vira uma linha em `systems`, então o
`report-service` precisa pedir ao SSO o vínculo do agente com o `server-service` — uma
relação que não existe, porque ele não consome o `server-service`, consome os **dados do
Sysnormal**.

O vínculo correto é com o domínio, não com o consumidor.

## 2. A evidência de que a tabela já é usada assim

Não é interpretação. Os únicos três `json_data` cadastrados dizem a que vieram:

```
system  4  "winthor-integration-service"   {"pcusuari":{"codusur":105}}
system 10  "report-service"                {"sysnormal":{"collaborators":{"id":105}}}
```

Nenhum dos dois descreve uma aplicação. O primeiro é a identidade do agente **no domínio
Winthor**; o segundo, **no domínio Sysnormal**. As duas linhas já são domínios — herdaram
o nome do primeiro serviço que precisou delas.

A distribuição de recursos confirma a separação, sem que ninguém a tenha planejado:

| system_id | nome | recursos |
|---|---|---|
| 2 | SSO WEBCLIENT | URL 9 |
| 3 | SYSNORMAL FRONT | URL 282 · MODULE 40 |
| 5 | sales-person-app | COMPONENT 1 |
| 10 | report-service | **TABLE 1** |

As linhas que são aplicação carregam exclusivamente recursos de aplicação (URL, MODULE,
COMPONENT). A única linha que funciona como domínio de dados carrega o único recurso
TABLE. A fronteira já existe de fato; só não existe no esquema.

## 3. A ingenuidade está escrita nas colunas

`systems` tem, além do nome:

```
system_platform_id  →  system_platform_types:  DESKTOP · WEB · MOBILE
system_side_id      →  system_sides:           SERVER SIDE · CLIENT SIDE
parent_id           →  existe · NULL nas 6 linhas
```

Plataforma e lado são atributos de **programa em execução**. Um banco de dados não é WEB
nem MOBILE. Um ecossistema não é SERVER nem CLIENT. As seis linhas têm os dois
preenchidos — inclusive a linha 4, que na prática é o domínio Winthor e está marcada
`DESKTOP / SERVER SIDE`.

A premissa "toda linha é uma aplicação" não é suposição: está declarada no esquema. A
tabela nasceu com propósito bom e escopo estreito, e o escopo é o que ficou pequeno.

## 4. Proposta de nome

**`systems` → `domains`**, e a FK `system_id` → `domain_id`.

A palavra já é a que a equipe usa: "identidade no domínio Winthor", "domínio Sysnormal".
O próprio `json_data` já é namespaceado por domínio (`{"sysnormal": …}`). O esquema
passaria a falar a língua que a conversa já fala, e as duas leituras ficam corretas:

```
agents_x_access_profiles_x_domains  →  o perfil e a identidade do agente NO DOMÍNIO X
resources.domain_id                 →  este recurso pertence AO DOMÍNIO X
```

Funciona também no caso que parece esticar, o de aplicação: a URL `/dashboard` do
front-spa só significa alguma coisa dentro do front-spa. A aplicação é o domínio de
nomeação daquele recurso.

**Alternativa considerada: `realms`.** É o termo consagrado em IAM — no Keycloak, um
realm é exatamente esta fronteira. Mais preciso tecnicamente, não colide com nada. Foi
preterido por ser jargão: o problema que estamos resolvendo é justamente gente não
conseguir ler a tabela.

**Descartados:** `applications` (descreve só um dos tipos), `assets` (colide com
`Assets` do modelo de dados do Sysnormal), e manter `systems` (é o nome que causou a
confusão — descreve o conteúdo esperado, não o papel).

> Atenção durante a execução: `basic-data-model` tem uma entidade `System` própria, da
> tabela `systems` do banco **do Sysnormal**, que não tem relação com esta. São tabelas
> diferentes em bancos diferentes.

## 5. Tabela de tipos

Seguindo a convenção que o próprio SSO usa em `resource_types` — tabela de apoio, não
enum, porque foi justamente não poder crescer que criou o problema.

```
domain_types (id, name, description, …)   mesmo shape base de resource_types

    ECOSYSTEM     Sysnormal · Winthor
    APPLICATION   front-spa · sales-person-app · sso-front · jumbo-bi
    SERVICE       server-service · report-service · winthor-integration-service · sso-service
    DATABASE      sysnormal_dev_v3 · WINT
    CLUSTER       agrupamento de infraestrutura

domains.domain_type_id  →  domain_types.id
```

### De-para das 6 linhas existentes

| id | nome atual | tipo | observação |
|---|---|---|---|
| 1 | SSO SERVER | SERVICE | — |
| 2 | SSO WEBCLIENT | APPLICATION | 9 recursos URL |
| 3 | SYSNORMAL FRONT | APPLICATION | 322 recursos · 85 vínculos de agente |
| 4 | winthor-integration-service | **ECOSYSTEM** | renomear para `winthor`: o `json_data` é identidade de domínio, não de serviço |
| 5 | sales-person-app | APPLICATION | — |
| 10 | report-service | **ECOSYSTEM** | renomear para `sysnormal`: idem |

As linhas 4 e 10 são as que mudam de natureza. Se depois for preciso um vínculo com o
`report-service` **enquanto serviço** — para grants de ENDPOINT, por exemplo —, cria-se
uma linha nova do tipo SERVICE. São coisas distintas e passam a poder coexistir.

## 6. A regra que faz o tipo valer alguma coisa

Sem isto, `domain_type_id` é rótulo, e em um ano alguém pendura um resource TABLE numa
linha APPLICATION — de volta ao ponto de partida, agora com uma coluna afirmando que
está tudo certo.

**O tipo do domínio deve governar quais `resource_types` podem pertencer a ele:**

```
ECOSYSTEM · DATABASE   →  TABLE · COLUMN · DATA
APPLICATION            →  URL · SCREEN · COMPONENT · MODULE
SERVICE                →  ENDPOINT · METHOD · CLASS · PACKAGE
```

Validado no cadastro (no `save` de `resources`), é o que impede a confusão de voltar.
Como visto na §2, os dados atuais já respeitam essa matriz — a regra não quebra nada
existente, só congela o que já é verdade.

## 7. `parent_id` — a peça que já existe e não é usada

`domains.parent_id` está lá, NULL nas seis linhas. Com ele:

```
front-spa (APPLICATION)      →  parent = sysnormal (ECOSYSTEM)
sales-person-app (APPLICATION) →  parent = sysnormal (ECOSYSTEM)
sysnormal_dev_v3 (DATABASE)  →  parent = sysnormal (ECOSYSTEM)
```

Isso permite que a resolução de identidade **suba a árvore**: o agente se vincula à
aplicação onde ele de fato existe, e a identidade de dados é herdada do ecossistema.

O ganho é concreto e grande. Hoje há 85 vínculos de agente no domínio 3
(SYSNORMAL FRONT), com perfis reais (SELLER 20, GERENCIAL 6, INVOICING 4, SUPERVISOR 1,
DEFAULT 49…) e **zero `json_data`**. Sem herança, ligar RLS exigiria replicar os 85
vínculos no ecossistema. Com herança, exige um `parent_id` e o `json_data` no lugar
certo.

**Questão que fica aberta e não é técnica:** o perfil gravado no vínculo de aplicação
nasceu para dizer *o que a pessoa abre no front*. Usá-lo como perfil de **escopo de
dados** é uma suposição — provavelmente verdadeira hoje, mas é uma suposição. Se perfil
de aplicação e perfil de domínio precisarem divergir, a herança tem que valer para
identidade e **não** para perfil. Vale decidir de propósito, e não por omissão.

## 8. Impacto

Menor do que a mudança sugere. No banco, só duas colunas referenciam a tabela:

```
agents_x_access_profiles_x_systems.system_id
resources.system_id
```

Mais os dois lookups `system_platform_types` e `system_sides`, que passam a fazer sentido
apenas para APPLICATION e SERVICE — e portanto viram **nuláveis**.

No código:

| onde | o quê |
|---|---|
| `sysnormal-spring-boot-starter-sso` | entidades `System`, `AgentXAccessProfileXSystem`, `Resource`, `SystemPlatformType`, `SystemSide`; `SystemsController`; `SystemsService` |
| API de records | `/records/systems/*` e `/records/agents_x_access_profiles_x_systems/*` mudam de nome — **quebra consumidor** |
| `report-service` | `SsoDataScopeProvider` chama `/records/agents_x_access_profiles_x_systems/get` e `/records/resources/get`; propriedade `sso.system-id` |
| `server-service` | ainda não consome — a integração está sendo desenhada agora e já nasce no nome novo |

A quebra da API de records é o ponto que exige combinação: os endpoints são nomeados a
partir das tabelas, então renomear a tabela renomeia a rota. Ou se aceita a quebra
(poucos consumidores hoje), ou se mantém alias temporário na rota antiga.

**Por que agora:** o cadastro de dados está praticamente vazio — 1 resource TABLE, 1
`condition`, 3 vínculos com `json_data`. Remodelar hoje custa três linhas de dados.
Depois que 85 pessoas tiverem identidade preenchida e houver conditions em várias
tabelas, custa migração com janela de risco de alguém enxergar o que não deve.

## 9. DDL proposto

Segue o shape base das tabelas do SSO, espelhado de `resource_types`.

```sql
-- 1. tabela de tipos
CREATE TABLE `domain_types` (
  `id`               bigint      NOT NULL AUTO_INCREMENT,
  `parent_id`        bigint      DEFAULT NULL,
  `created_at`       datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at`       datetime(6) DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP(6),
  `id_at_origin`     varchar(127) DEFAULT NULL,
  `source_id`        bigint      DEFAULT NULL,
  `deleted_at`       datetime(6) DEFAULT NULL,
  `is_sys_rec`       tinyint     NOT NULL DEFAULT '0',
  `record_status_id` bigint      NOT NULL DEFAULT '1',
  `creator_agent_id` bigint      NOT NULL DEFAULT '1',
  `updater_agent_id` bigint      DEFAULT NULL,
  `name`             varchar(127) NOT NULL,
  `description`      longtext,
  `notes`            longtext,
  PRIMARY KEY (`id`),
  UNIQUE KEY `domain_types_u1` ((coalesce(`parent_id`,-(1))),`record_status_id`,`name`),
  KEY `domain_types_parent_id_domain_types_id_fk` (`parent_id`),
  CONSTRAINT `domain_types_parent_id_domain_types_id_fk`
      FOREIGN KEY (`parent_id`) REFERENCES `domain_types` (`id`) ON DELETE CASCADE,
  CONSTRAINT `domain_types_record_status_id_record_status_id_fk`
      FOREIGN KEY (`record_status_id`) REFERENCES `record_status` (`id`),
  CONSTRAINT `domain_types_creator_agent_id_agents_id_fk`
      FOREIGN KEY (`creator_agent_id`) REFERENCES `agents` (`id`),
  CONSTRAINT `domain_types_updater_agent_id_agents_id_fk`
      FOREIGN KEY (`updater_agent_id`) REFERENCES `agents` (`id`),
  CONSTRAINT `domain_types_chk_1` CHECK ((`is_sys_rec` in (0,1)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `domain_types` (`name`, `description`, `is_sys_rec`) VALUES
  ('ECOSYSTEM',   'Conjunto de dados e sistemas de um mesmo domínio de negócio', 1),
  ('APPLICATION', 'Programa com que uma pessoa interage',                        1),
  ('SERVICE',     'Programa consumido por outro programa',                       1),
  ('DATABASE',    'Banco de dados ou schema',                                    1),
  ('CLUSTER',     'Agrupamento de infraestrutura',                               1);

-- 2. renomeações
RENAME TABLE `systems` TO `domains`;
RENAME TABLE `agents_x_access_profiles_x_systems` TO `agents_x_access_profiles_x_domains`;

-- `domains` não tem coluna `system_id`: a auto-referência dela é `parent_id`
ALTER TABLE `agents_x_access_profiles_x_domains`  RENAME COLUMN `system_id` TO `domain_id`;
ALTER TABLE `resources`                           RENAME COLUMN `system_id` TO `domain_id`;

-- 3. tipo no domínio
ALTER TABLE `domains`
  ADD COLUMN `domain_type_id` bigint NULL AFTER `parent_id`,
  ADD CONSTRAINT `domains_domain_type_id_domain_types_id_fk`
      FOREIGN KEY (`domain_type_id`) REFERENCES `domain_types` (`id`);

-- 4. plataforma e lado passam a ser opcionais (só APPLICATION e SERVICE têm)
ALTER TABLE `domains`
  MODIFY COLUMN `system_platform_id` bigint NULL,
  MODIFY COLUMN `system_side_id`     bigint NULL;

-- 5. classificação das linhas existentes
UPDATE `domains` SET `domain_type_id` = (SELECT id FROM domain_types WHERE name='SERVICE')     WHERE id = 1;
UPDATE `domains` SET `domain_type_id` = (SELECT id FROM domain_types WHERE name='APPLICATION') WHERE id IN (2,3,5);
UPDATE `domains` SET `domain_type_id` = (SELECT id FROM domain_types WHERE name='ECOSYSTEM'),
                     `name` = 'winthor',
                     `system_platform_id` = NULL, `system_side_id` = NULL                      WHERE id = 4;
UPDATE `domains` SET `domain_type_id` = (SELECT id FROM domain_types WHERE name='ECOSYSTEM'),
                     `name` = 'sysnormal',
                     `system_platform_id` = NULL, `system_side_id` = NULL                      WHERE id = 10;

-- 6. hierarquia: aplicações do Sysnormal passam a apontar para o ecossistema
UPDATE `domains` SET `parent_id` = 10 WHERE id IN (3,5);

-- 7. depois de classificar todas as linhas
ALTER TABLE `domains` MODIFY COLUMN `domain_type_id` bigint NOT NULL;
```

Os nomes de coluna `system_platform_id` e `system_side_id` foram mantidos de propósito
neste passo — renomeá-los é cosmético e pode ir em migração separada, para esta não
misturar mudança estrutural com mudança de nome.

## 10. Decisões em aberto

1. **`domains` ou `realms`?** Recomendação: `domains`, por legibilidade.
2. **A API de records quebra ou ganha alias?** Poucos consumidores hoje; alias custa
   pouco e evita coordenar deploy.
3. **Herança de perfil ou só de identidade** pelo `parent_id` (§7).
4. **`system_platform_types` e `system_sides` acompanham o rename?** Ficariam
   `domain_platform_types` / `domain_sides`, ou viram algo mais estreito, já que só se
   aplicam a dois dos cinco tipos.

## 11. O que depende disto

O `server-service` está com a função `getCollaboratorsIds` desenhada e parada, à espera.
Ela resolve identidade e perfil do agente pelo SSO, e o contrato já está fechado
(`table`, `collaboratorTypes`, `requireRestriction`; grant sobrepõe estrutura; estrutura
restritiva por padrão). O que falta é saber contra qual linha resolver — que é
exatamente o que esta proposta define.

A branch `feature/sellers-scope` do `server-service` está criada e vazia, aguardando.
