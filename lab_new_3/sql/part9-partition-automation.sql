-- =====================================================================
-- Части 10-11: инфраструктура для автоматизации и alerting
-- =====================================================================
-- Таблица состояния нужна, чтобы alert не уходил бесконечно: сервис
-- помнит, о какой проблеме он уже сообщил и когда. Состояние лежит в БД,
-- а не в памяти процесса — перезапуск сервиса не должен приводить
-- к повторной рассылке, а несколько экземпляров должны видеть общую картину.
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = public;

CREATE TABLE IF NOT EXISTS public.partition_alert_state (
    alert_key        varchar(200) PRIMARY KEY,
    status           varchar(20)  NOT NULL,
    details          text,
    first_seen_at    timestamptz  NOT NULL,
    last_notified_at timestamptz,
    notify_count     integer      NOT NULL DEFAULT 0,
    updated_at       timestamptz  NOT NULL
);

COMMENT ON TABLE  public.partition_alert_state             IS 'Состояние alert''ов PartitionHealthCheck: подавление повторов и recovery';
COMMENT ON COLUMN public.partition_alert_state.first_seen_at    IS 'Когда проблема замечена впервые — из этого считается downtime в recovery-сообщении';
COMMENT ON COLUMN public.partition_alert_state.last_notified_at IS 'Когда уведомление реально ушло в канал; NULL, если проблема ещё не отправлялась';

-- Удобная витрина для дежурного: что есть, чего не хватает
CREATE OR REPLACE VIEW public.v_partitions AS
SELECT p.relname                          AS parent_table,
       c.relname                          AS partition_name,
       pg_get_expr(c.relpartbound, c.oid) AS bounds,
       pg_total_relation_size(c.oid)      AS size_bytes,
       c.reltuples::bigint                AS approx_rows
FROM pg_class c
JOIN pg_inherits i  ON i.inhrelid = c.oid
JOIN pg_class p     ON p.oid = i.inhparent
JOIN pg_namespace n ON n.oid = p.relnamespace
WHERE n.nspname IN ('public', 'lab3')
  AND c.relkind = 'r'   -- только сами партиции; локальные индексы тоже наследуются
ORDER BY p.relname, c.relname;

SELECT parent_table, count(*) AS partitions, pg_size_pretty(sum(size_bytes)) AS total
FROM public.v_partitions GROUP BY 1 ORDER BY 1;
