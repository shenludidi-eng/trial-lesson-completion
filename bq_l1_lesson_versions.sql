-- L1 lesson-version mapping for the local V3 / V4 comparison.
--
-- Covers the full dashboard history. The key uses the class's all-time first
-- start so it matches the existing class-level dashboard row, including
-- re-entered classes. In the UI, the former structural V2 bucket is called V3;
-- lesson_version=4 is split out as V4.
WITH stage_starts AS (
  SELECT
    CAST(class_id AS STRING) AS class_id,
    CAST(uid AS STRING) AS user_id,
    COALESCE(
      TIMESTAMP_MILLIS(client_event_time_ms),
      TIMESTAMP_MICROS(event_timestamp)
    ) AS event_at
  FROM `dino-english-497507.de_dwd.dwd_firebase_event_di`
  WHERE DATE(stat_date) BETWEEN DATE '2026-07-01' AND @end_date
    AND event_name = 'trigger'
    AND event_id = 'class_stage_start'
    AND CAST(lesson_id AS STRING) = '732'
    AND class_id IS NOT NULL
    AND uid IS NOT NULL
),
class_keys AS (
  SELECT
    class_id,
    ARRAY_AGG(user_id ORDER BY event_at, user_id LIMIT 1)[OFFSET(0)] AS user_id,
    MIN(event_at) AS first_start_at
  FROM stage_starts
  GROUP BY class_id
  HAVING MIN(event_at) >= TIMESTAMP '2026-08-01 00:00:00+00'
)
SELECT
  FORMAT_DATE('%F', DATE(k.first_start_at)) AS start_date,
  k.class_id,
  LOWER(SUBSTR(TO_HEX(SHA256(k.user_id)), 1, 12)) AS user_key,
  FORMAT_TIMESTAMP('%Y-%m-%dT%H:%M:%S', k.first_start_at, 'UTC') AS start,
  COALESCE(CAST(sc.lesson_version AS STRING), '') AS lesson_version
FROM class_keys k
LEFT JOIN `dino-english-497507.de_ods.student_class` sc
  ON CAST(sc.id AS STRING) = k.class_id
 AND SAFE_CAST(sc.lesson_id AS INT64) = 732
ORDER BY start, class_id;
