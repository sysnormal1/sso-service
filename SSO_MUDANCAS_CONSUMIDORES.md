# SSO — o que mudou para quem consome

> **Documento temporário.** Válido até que todos os consumidores listados na seção 8 estejam migrados.
> Depois disso este arquivo é apagado. O modelo permanente fica em [contratos/sso.md](../../../../docs/contratos/sso.md).
>
> **Não copie este arquivo para o seu repositório.** Linke-o. Cópias divergem e passam a ser acreditadas depois de erradas.

**Data:** 2026-08-13. **Vale para:** qualquer serviço ou aplicação que autentica ou consulta permissões no SSO.

O SSO renomeou o conceito de `system` para `domain`. Isso muda **três nomes de parâmetro**, **quatro endpoints** e **alguns campos das respostas**. Não há compatibilidade retroativa: as rotas antigas respondem **404** e os parâmetros antigos causam erro (**417** ou **500**, conforme o caso — seção 5).

Junto veio uma mudança de comportamento que **não é só renomeação**: consultar permissões sem informar o domínio agora é **erro**, e não mais "devolve tudo". Detalhes na seção 3.

**Os ids não mudaram.** Se o seu serviço aponta para um id fixo (ex.: `10`), ele continua valendo. Apenas os nomes de dois registros mudaram: o id `4` passou a se chamar `winthor` e o id `10`, `sysnormal`.

---

## 1. Os parâmetros que mudaram de nome

São exatamente estes três. Não há outros.

| antes | agora | tipo | onde vai |
|---|---|---|---|
| `systemId` | `domainId` | número | corpo do login, claim do JWT, e dentro de `queryParams` |
| `systemIds` | `domainIds` | lista de números | dentro de `queryParams` (só em `get_with_permissions`) |
| `systemName` | `domainName` | texto | **raiz do corpo**, não dentro de `queryParams` |

`domainId` continua **opcional** — se você não mandava, não precisa mandar agora.

```jsonc
// login: antes
{ "systemId": 3, "email": "...", "password": "..." }
// login: agora
{ "domainId": 3, "email": "...", "password": "..." }
```

Quem decodifica o token JWT precisa ler o claim **`domainId`** no lugar de `systemId`.

## 2. Os endpoints que mudaram de caminho

| antes | agora |
|---|---|
| `/records/systems` | `/records/domains` |
| `/records/agents_x_access_profiles_x_systems` | `/records/agents_x_access_profiles_x_domains` |
| `/records/system_platforms` | `/records/domain_platforms` |
| `/records/system_sides` | `/records/domain_sides` |

Nenhum outro caminho mudou. `/auth/*`, `/records/agents`, `/records/resources`, `/records/access_profiles`, `/records/resource_permissions` e `/records/resource_types` seguem iguais.

Cada endpoint de records aceita as operações de sempre: `get`, `get/{id}`, `PUT`, `PATCH /{id}`, `DELETE`.

## 3. Os três endpoints customizados de `/records/resources`

Estes têm parâmetros próprios dentro de `queryParams`. **Só as células em negrito mudaram.**

| endpoint | parâmetros |
|---|---|
| `/get_alloweds` | **`domainId`** (obrigatório), `resourceTypeId`, `accessProfileId`, `agentId`, `allowedAccess`, `allowedView`, `allowedCreate`, `allowedChange`, `allowedDelete` |
| `/get_resource_permissions` | **`domainId`** (obrigatório), `resourceTypeId`, `accessProfileId`, `resourcePaths` |
| `/get_with_permissions` | **`domainIds`** (obrigatório), `agentIds`, `accessProfileIds`, `resourceTypeIds`, `resourcePaths` |

> `get_with_permissions` é o único que usa **plural**. Se você monta o filtro por lista, o nome é `domainIds`.

### O domínio agora é obrigatório nestes três

Antes, requisição sem domínio devolvia o catálogo inteiro, de todos os domínios. **Isso mudou**: agora responde **417** com uma mensagem dizendo o que faltou.

```jsonc
{ "success": false, "httpStatusCode": 417,
  "message": "missing domainId: it is required to query resource permissions" }
```

Em `get_alloweds` e `get_resource_permissions`, o `domainId` é preenchido a partir do token quando ele traz o claim; o que você manda no corpo serve de complemento. Na prática: **se o seu login não informa `domainId`, estes dois endpoints passam a exigir que você mande `domainId` no corpo.** Em `get_with_permissions` não há token de onde tirar — `domainIds` sempre vem de você.

## 4. Os campos das respostas

| antes | agora | onde aparece |
|---|---|---|
| `resourceSystemId` | `resourceDomainId` | resposta dos **três** endpoints da seção 3 |
| `systemId` | `domainId` | registros de `/records/resources` e `/records/agents_x_access_profiles_x_domains` |
| `systemPlatformId` | `domainPlatformId` | registros de `/records/domains` |
| `systemSideId` | `domainSideId` | registros de `/records/domains` |

Em `/records/domains` existe agora um campo **`domainTypeId`**. Você não precisa usá-lo; ele só classifica o registro.

> **Atenção:** `domainPlatformId` e `domainSideId` agora podem vir **nulos**. Se o seu código assume que sempre têm valor, ajuste.

## 5. O que **não** mudou

Vale conferir esta lista antes de sair renomeando: estas chaves continuam com o nome de sempre, tanto no envio quanto na resposta.

```
agentId · agentIds · accessProfileId · accessProfileIds
resourceTypeId · resourceTypeIds · resourcePaths
allowedAccess · allowedView · allowedCreate · allowedChange · allowedDelete
queryParams · where · data
```

A estrutura do corpo (`{ "queryParams": { "where": { ... } } }`) também é a mesma.

### O que acontece se você usar o nome antigo

Nos três endpoints da seção 3, usar `systemId`/`systemIds` dá **417** — porque o domínio virou obrigatório e o nome antigo não o informa. Nas consultas genéricas com `where`, dá **500** (`Could not resolve attribute 'systemId'`). Nos dois casos você descobre na hora.

```
get_with_permissions  {"queryParams":{"domainIds":[2]}}   ->  10 linhas
get_with_permissions  {"queryParams":{"systemIds":[2]}}   -> 417, "missing domainIds: ..."
```

A única exceção é o **corpo do login**: ali `systemId` é ignorado sem erro, e você recebe um token sem o claim de domínio. O sintoma aparece depois, nos endpoints acima, como o 417. Se você começar a ver 417 onde antes funcionava, confira primeiro se o login ainda manda `systemId`.

## 6. Se você usa uma das bibliotecas

**`sso-client-requester`** (Java) — atualize a dependência e renomeie a propriedade:

```yaml
sso:
  default-domain-id: 1     # antes: default-system-id
```

Os métodos `loginOnSso(...)`, `getToken(...)` e `refreshToken(...)` mantêm a mesma assinatura; só o nome do parâmetro mudou de `systemId` para `domainId`.

**`@sysnormal/react-sso`** — atualize o pacote e renomeie na chamada de `ssoConfig({...})`:

| antes | agora |
|---|---|
| `ssoThisSystemId` | `ssoThisDomainId` |
| `ssoSystemsEndpoint` | `ssoDomainsEndpoint` |
| `ssoAgentsXAccessProfilesXSystemsEndpoint` | `ssoAgentsXAccessProfilesXDomainsEndpoint` |

O campo `resourceSystemId` devolvido pelos helpers de recurso/permissão virou `resourceDomainId`.

## 7. Checklist

- [ ] Trocar `systemId` por `domainId` no corpo do login.
- [ ] Trocar a leitura do claim `systemId` por `domainId` em quem decodifica o token.
- [ ] Atualizar as quatro URLs da seção 2.
- [ ] Se usa `get_with_permissions`: trocar `systemIds` por **`domainIds`** (plural).
- [ ] Se filtra por nome em `agents_x_access_profiles_x_domains`: trocar `systemName` por `domainName` (na raiz do corpo).
- [ ] Renomear os campos da seção 4 no parsing das respostas.
- [ ] Tratar `domainPlatformId` / `domainSideId` possivelmente nulos.
- [ ] Se usa `sso-client-requester` ou `react-sso`: atualizar a versão e renomear as configurações da seção 6.
- [ ] Garantir que o domínio é informado nos três endpoints da seção 3 — via claim do token ou no corpo. Sem ele, agora é **417**.
- [ ] **Testar chamando a API**, não só compilar.

## 8. Rastreio da migração

Quando todas as linhas estiverem em "migrado", este documento é apagado e sobra apenas [contratos/sso.md](../../../../docs/contratos/sso.md).

| Consumidor | Tipo | Estado |
|---|---|---|
| `auth-core` | biblioteca | migrado |
| `security-core` | biblioteca | migrado |
| `sysnormal-spring-boot-starter-sso` | biblioteca | migrado |
| `sso-client-requester` | biblioteca | migrado |
| `@sysnormal/react-sso` | biblioteca | migrado |
| `sso-front` | aplicação | migrado |
| `report-service` | serviço | migrado |
| `winthor-integration-service` | serviço | migrado |
| `front-spa` | aplicação | **pendente** — a constante `resource_types.SYSTEM_ID` em `src/controllers/data/DataController.tsx:64` espelha o catálogo do SSO, cuja entrada de id 1 passou de `SYSTEM` para `DOMAIN`. O id não mudou, então nada quebra; só o nome diverge |
| `server-service` | serviço | não se aplica — ainda não consome o SSO |

Estado verificado em 2026-08-13 por varredura de `systemId`, `system_id`, `records/systems` e `agents_x_access_profiles_x_systems` no código de cada repositório.
