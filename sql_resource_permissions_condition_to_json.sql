-- =====================================================================
-- resource_permissions: predicado de acesso da coluna `condition` para `json_data`
--
-- Contexto e motivo: docs/explicacao/condition-para-json-data.md
-- Banco alvo: sysnormal_sso_dev_v4  (o banco do SSO nao foi para o v5)
--
-- A migracao e feita em DOIS PASSOS, e a ordem importa.
-- Rodar so o PASSO 1 agora. O PASSO 2 esta comentado de proposito.
-- =====================================================================


-- ---------------------------------------------------------------------
-- ANTES: estado esperado
-- condition_preenchida = 1, json_preenchido = 0
-- ---------------------------------------------------------------------
SELECT
    sum(`condition` IS NOT NULL AND `condition` <> '') AS condition_preenchida,
    sum(json_data   IS NOT NULL AND json_data   <> '') AS json_preenchido,
    count(*)                                           AS total
  FROM resource_permissions;


-- ---------------------------------------------------------------------
-- PASSO 1 — escrita dupla: preenche json_data e MANTEM a condition
--
-- Seguro de rodar agora: nada le json_data ainda, entao o comportamento
-- nao muda. Limpar a condition neste momento apagaria a unica restricao
-- de linha em vigor, e o perfil SELLER passaria a ver os movimentos de
-- todos - sem erro e sem sintoma.
--
-- Idempotente: o WHERE casa com o texto exato da condition atual e so
-- age quando json_data ainda esta vazio.
-- ---------------------------------------------------------------------
UPDATE resource_permissions
   SET json_data = '{"predicates": {"seller_id": "#{collaborators.id}"}}'
 WHERE id = 2903
   AND `condition` = '#{TABLE_ALIAS}.seller_id = #{collaborators.id}'
   AND (json_data IS NULL OR json_data = '');


-- ---------------------------------------------------------------------
-- DEPOIS: conferencia do passo 1
-- Esperado: 1 linha, com as duas colunas preenchidas e o JSON valido.
-- ---------------------------------------------------------------------
SELECT
    id,
    resource_id,
    access_profile_id,
    `condition`,
    json_data,
    JSON_VALID(json_data) AS json_valido
  FROM resource_permissions
 WHERE id = 2903;


-- =====================================================================
-- PASSO 2 — SO DEPOIS que o report-service ler json_data e a leitura for
-- verificada em dev.
--
-- Pre-requisitos, os tres:
--   1. o leitor de json_data existe e foi testado;
--   2. esta decidido que, com as duas colunas preenchidas, json_data vence;
--   3. o relatorio do perfil SELLER foi conferido e continua restrito.
--
-- Descomente e rode apenas quando os tres valerem.
-- =====================================================================

UPDATE resource_permissions
   SET `condition` = NULL
 WHERE id = 2903
   AND json_data = '{"predicates": {"seller_id": "#{collaborators.id}"}}';

SELECT id, `condition`, json_data FROM resource_permissions WHERE id = 2903;
